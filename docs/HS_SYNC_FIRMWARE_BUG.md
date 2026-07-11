# HPI_HS `SYNC` returns 0 records after a reboot — durable segments are never read

**For:** HealthyPi Move firmware (`healthypi-move-fw-next`)
**File:** `app/src/health/hpi_health_store.c`, `hpi_hs_read_since()` (~line 234)
**Reported by:** companion-app side (`healthypi_move_flutter_next`), FW **2.1.1+0**
**Severity:** blocking — no health data can be synced off the device after any reboot
**App-side status:** ruled out. The app sends exactly the shape the handler decodes.

---

## Summary

`SYNC` always returns `n=0` once the RAM ring is cold, even though the device
reports `head=35088` and the samples are safely on flash. The read path
short-circuits to the (empty) RAM ring and **never reads the durable segment
files**, so the flash-resident history is unreachable.

This reproduces on every boot, because `s_seq` is restored from persisted meta
while the ring is volatile.

## Observed on the wire

`HELLO` is healthy:

```
dev=healthypi-move  schema=…  head=35088  types=5
```

`SYNC` — every request, every cursor value, returns nothing:

```
SYNC(since=0,     max=256) -> n=0 next=0     more=true  bytes=0
SYNC(since=35024, max=32 ) -> n=0 next=35024 more=true  bytes=0
```

Note `next` echoes `since` back, which proves the handler **is** decoding our
payload correctly — the request shape is not the problem.

## Root cause

`hpi_health_store.c:245-257`:

```c
uint32_t head = s_seq;
uint32_t oldest_ring = (s_count > 0) ? (s_seq - s_count + 1) : (head + 1);

/* Fast path: the requested range is entirely within the RAM ring … */
bool ring_only = (s_count == 0) || ((uint64_t)since_seq + 1u >= oldest_ring);
if (ring_only) {
    ring_foreach(read_cb, &a);      /* RAM ring only */
}
k_mutex_unlock(&s_lock);

if (!ring_only) {
    /* Catch-up: read ascending from the durable segments … */   <-- never runs
}
```

**`s_count == 0` forces `ring_only = true`.** The function then iterates an empty
ring, returns `n = 0`, and the segment-scan branch is skipped entirely.

The `s_count == 0` clause looks like it was meant to express *"ring empty ⇒
nothing to send"* (the trivial caught-up case). But an empty ring does **not**
imply an empty store — it also happens whenever the ring is cold and the data
lives on flash.

### Why the ring is always cold at boot

`hpi_health_store.c:83` — the ring is volatile and zeroed at init:

```c
s_head = s_count = s_seq = 0;
```

`hpi_health_store.c:571-573` — but the sequence counter is restored from meta:

```c
s_seq         = m.seq;   /* keep the sync cursor monotonic  */
s_flushed_seq = m.seq;   /* everything persisted is flushed */
s_seg_index   = m.seg_index;
```

So after any reboot: `s_seq = 35088`, `s_count = 0`. The device correctly knows
it holds 35,088 samples, they are correctly written to the segment files — and
`hpi_hs_read_since()` refuses to look at them.

Until the ring refills, **100% of the device's history is unreachable**, and once
it does refill only the last ≤512 samples (`HS_RING_N`) become visible while
everything older stays stranded on flash.

## Proposed fix

Separate "caught up" from "ring is cold":

```c
    k_mutex_lock(&s_lock, K_FOREVER);
    uint32_t head = s_seq;
    uint32_t oldest_ring = (s_count > 0) ? (s_seq - s_count + 1) : (head + 1);

    /* Nothing newer than the client's cursor — no work, no I/O. */
    bool caught_up = (since_seq >= head);

    /* The requested range is entirely inside the RAM ring: serve it hot. */
    bool in_ring = (s_count > 0) &&
                   ((uint64_t)since_seq + 1u >= oldest_ring);

    bool ring_only = caught_up || in_ring;
    if (ring_only && !caught_up) {
        ring_foreach(read_cb, &a);      /* oldest-first => ascending seq */
    }
    k_mutex_unlock(&s_lock);

    if (!ring_only) {
        /* Client is behind the ring, or the ring is cold after a reboot:
         * read ascending from the durable segments. */
        …existing segment-scan code, unchanged…
    }
```

The segment branch already does the right thing — it filters `s.seq > since_seq`,
walks segments ascending, and caps at `cap` — so no change is needed there.

**Behaviour after the fix**

| State | `since` | Path taken |
|---|---|---|
| Ring cold (post-reboot), data on flash | `0` | segments ✅ *(today: returns 0)* |
| Ring warm, client far behind | `< oldest_ring` | segments ✅ |
| Ring warm, client recent | `>= oldest_ring - 1` | ring (hot) ✅ |
| Client caught up | `>= head` | none, `n=0` ✅ |

## How to reproduce

1. Let the watch accumulate samples, then **power-cycle it** (this is the key
   step — it empties the ring while `s_seq` survives).
2. From a fresh client (no cursor), issue `SYNC {since: 0, max: 40}`.
3. **Expected:** up to 40 records from the oldest retained segment.
   **Actual:** `n=0, next=0, more=true, recs=<empty bstr>`.

## Suggested test

Worth covering both, since they fail differently:

- **Cold ring:** boot with populated segments and `s_count == 0`; assert
  `SYNC(since=0)` returns `n > 0` and ascending seqs. *(This is the bug.)*
- **Cold-ring drain:** repeatedly `SYNC` + `ACK` from `since=0` and assert the
  cursor advances to `head`, i.e. the whole history drains.
- **Caught up:** `SYNC(since=head)` returns `n=0` with **no flash I/O**.

---

## Secondary observations (not blockers)

1. **`more` is misleading.** `hpi_hs_read_since()` sets

   ```c
   if (more) *more = (a.next < head);
   ```

   so `more` is purely `next < head` and is `true` even when `n == 0` and no
   records exist to send. A client can't use it as "there is more data" — it
   cost us a debugging cycle. Consider `*more = (a.n > 0) && (a.next < head);`
   so a client can loop on `more` safely.

2. **Confirmed-good shapes** (the app now pins to these, no guessing):
   - `SYNC` request `{since, max}` → `{recs: bstr(n*18), n, next, more}`;
     `max` is clamped device-side to `HS_SYNC_MAX_BATCH` (40).
   - `TYPES` emits `class` as a **uint** and `derived` as a **bool**
     (the design doc had these as unpinned; app parses both).

3. **Retention vs. `head`.** `HELLO` exposes `head` but no *oldest retained seq*
   and no record count, so a client can't tell "store is empty" from "my cursor
   is stale" without probing. An `oldest` (or `count`) field in `HELLO` would
   make the client's first sync deterministic instead of exploratory.

---

# Issue 2 (new): the catch-up segment scan is O(since) per request

**Status:** the cold-ring fix above works — the app now drains real samples
(`cursor` reached 6960). But the drain then **times out and dies**, and it gets
slower the further it gets.

## Symptom

```
[HS-Sync] dev=5e54caf66ab8689a cursor=6960 head=35088 types=5
[HS-Sync] failed: SmpException(SMP request timed out, grp:0x1000 id:2 seq:94)
[ConnectionManager] link lost; force-releasing SMP lock
```

Early pages are fast; by ~seq 7 000 the requests exceed a 10 s SMP timeout and
the link drops. Raising the app's timeout to 40 s pushes the wall further out but
does not remove it — the cost grows without bound.

## Root cause

`hpi_hs_read_since()`, segment branch: for **every** request it reopens the
segments and re-reads from the *start*, discarding records until it passes
`since`:

```c
for (uint32_t idx = first; idx <= s_seg_index && a.n < cap; idx++) {
    ...
    while (a.n < cap && (rd = fs_read(&f, rbuf, sizeof(rbuf))) > 0) {
        for (int i = 0; i < nrec && a.n < cap; i++) {
            ...
            if (s.seq > since_seq) {   /* everything below `since` is read, then thrown away */
```

So one page costs **O(since)** flash reads, and a full drain is **O(n²/batch)**.
With `head = 35 088` and `HS_SYNC_MAX_BATCH = 40` that's ~877 requests whose scan
cost climbs from ~0 to ~35 000 records — roughly **15 million record reads**
(~270 MB of flash I/O) to move 630 KB of samples. Each individual request
eventually exceeds any reasonable SMP timeout.

## Suggested fix

Records are **fixed-size (18 B) and ascending within a segment**, so the scan can
be replaced with arithmetic:

1. **Skip whole segments.** Keep each segment's `first_seq`/`last_seq` (or derive
   from its first/last record). If `last_seq <= since_seq`, `fs_close()` and move
   on without reading the body.
2. **Seek within the target segment.** Once the right segment is found, the
   offset of the first record with `seq > since` is
   `(since_seq - first_seq + 1) * HPI_HS_SAMPLE_WIRE_SIZE` — a single
   `fs_seek()`, no scanning.

That makes each page O(batch) instead of O(since), and the whole drain linear.

A cheaper stopgap, if the above is too invasive: raise `HS_SYNC_MAX_BATCH` (the
netbuf allows ~40×18 B = 720 B today; a larger MTU/netbuf would allow more) to
cut the number of round-trips. It reduces the constant but not the quadratic.

## App-side mitigation already shipped

The app no longer depends on a single uninterrupted drain:

- SMP timeout for sync raised to **40 s**.
- The drain is **resumable**: every page is committed and the cursor persisted
  before the ack, so a timeout or link drop loses no work. The app reconnects and
  continues from the persisted cursor (up to 6 attempts), and reports a partial
  sync honestly if it still can't reach `head`.
- Trends are derived from whatever was stored, so a partial drain still surfaces
  real data in the UI.

This makes the sync *survivable*, not *fast* — with the quadratic scan a full
35 k-sample backlog will still take a very long time and many reconnects. The
firmware fix is what makes it actually usable.

---

## Resolved by firmware (app side updated — no action needed)

- **`HELLO.uid`.** Confirmed: `dev` is retained but will always be
  `"healthypi-move"`. The app now keys its raw sample store on **`HELLO.uid`**,
  with a one-shot migration (`DatabaseHelper.rekeyHealthStoreDevice`) that moves
  any rows written under the old model-string key. `uid` is parsed defensively
  (string / byte-string / int all normalise to a stable text key).
- **`ACK` does not free flash.** Confirmed: `hpi_hs_ack()` is a no-op and
  retention is size-based only (H4, as designed). The app no longer expects ACK
  to reclaim space. It still acks strictly *after* the page is durable, on
  purpose — the API contract says an ack may drop data and a future firmware
  could honour it, so the ordering is kept as cheap insurance.

## App-side context

The companion app is ready and waiting on this:

- It sends `{since, max}` — byte-for-byte what `hs_h_sync()` decodes.
- On each page it commits samples to SQLite **and** advances its cursor in one
  transaction, and only then calls `ACK` with the highest seq it actually
  stored. It never acks `head`, so a fixed firmware cannot lose data to the app.
- Re-inserting a seq is a no-op (`PRIMARY KEY (device, seq)`), so retried or
  duplicated pages are harmless.
