# HS-2 P1 + P2 — App Handoff

> **From: the HealthyPi Move *firmware* coding agent.**
> Repo: `healthypi-move-fw-next`. Commits: `794d756` (P1), `a6fd48e` (P2).
> Status: **build-verified, not yet exercised on device** (board was disconnected).
> Background: `docs/HS_SYNC_REDESIGN_PLAN.md`, `docs/hs_sync_redesign.html`.
> This doc is copied into the app repo as `docs/FIRMWARE_HANDOFF_HS2.md`.

---

## TL;DR for the app team

| | |
|---|---|
| **Does the app still work unmodified?** | **Yes.** Wire format, commands and cursor are unchanged. It will parse, sync, dedup and not crash. |
| **Is it still *correct* unmodified?** | **No.** Peak HR will silently under-report. **One change is required** — see §2. |
| **Schema bump?** | **No.** All new type ids are additive; old clients skip unknown ids. |
| **Do I need to re-pull everything?** | **Yes, once.** P2 migrates the on-flash layout and discards the old log. See §5. |

The device now stores **~6,000 samples/day instead of ~46,000** and serves a page
with one seek instead of rescanning the whole log. Daily sync payload drops from
~830 KB to ~105 KB; flash reads for a full sync drop from ~277 MB to roughly the
payload size.

---

## 1. What changed on the wire

**Nothing structural.** Same 18-byte packed record (`<IqBBi` — `seq`, `ts_utc`,
`type`, `quality`, `value`), same `HELLO`/`TYPES`/`SYNC`/`SUMMARY`/`RECORDS`/`ACK`
commands, same seq cursor, same paging.

**What changed is the *meaning* and *rate* of the samples.**

### 1.1 An `HR` sample is now a per-minute MEAN, not an instant

Previously HR was recorded on every publish (~every 3 s). Now it is aggregated into
a **1-minute epoch** and one record is emitted per statistic.

- `ts_utc` on an epoch record = **END of the window** (not an instant of measurement).
- Density drops ~20× (one HR mean per minute instead of one every 3 s).

### 1.2 Skin temp is a 5-minute mean; steps are unchanged

- `SKIN_TEMP` → mean over a **5-minute** epoch, plus a new `skin_temp_cnt`.
- `STEPS` → **still CUMULATIVE** (unchanged semantics!), just rate-limited to at
  most one record per minute. **No app action needed for steps.**

---

## 2. ⚠️ REQUIRED APP CHANGE — otherwise peak HR regresses

Because `hr` now carries the epoch **mean**, **any peak the app computes from the
raw `hr` series will be a peak-of-means and will be systematically too low.** A
10-second spike to 150 bpm is `150` today; as a minute-mean it collapses to ~110.

**Pick one:**

### (a) Read HR peaks from `SUMMARY` — cheapest, possibly zero work
`SUMMARY` already returns `hr_min` / `hr_avg` / `hr_max`, and the firmware now
computes them from the **true epoch extremes**, so they remain exact.
**If the app already uses `SUMMARY` for its cards, this may be no work at all — as
long as it does not *also* recompute peaks from the raw `hr` series.**

### (b) Use the new `hr_min` / `hr_max` type ids
Additive, harmlessly skipped by old builds, and lets you draw a proper min/max band
around the mean line. Daily peak = `max(hr_max series)` / `min(hr_min series)`.

### Also
- **Render `hr` as a per-minute mean** (a smoother line with ~1 point/min), not as
  instantaneous readings.
- **Remove any "no sample in the last N seconds ⇒ stale/disconnected" logic** keyed
  on the old ~3 s cadence. It will misfire at 1 sample/min.
- **Treat `ts_utc` on epoch types as the END of the window.**

---

## 3. Full type registry (as-built)

`TYPES` is **paged, 5 entries per call**. `total` is now **19** (was 16). Loop
`from := next` until `next == total`.

Legend — **class**: `D` discrete, `C` cumulative, `E` event.
**real value = `value` / `scale`**.

| id | key | unit | scale | class | new? | epoch | meaning |
|---|---|---|---|---|---|---|---|
| `0x01` | `hr` | bpm | 1 | D | | **1 min** | **MEAN HR over the window** (was: instantaneous) |
| `0x02` | `resting_hr` | bpm | 1 | D | | — | derived |
| `0x03` | `ecg_hr` | bpm | 1 | E | | — | ECG spot check (raw, unchanged) |
| `0x04` | `hr_min` | bpm | 1 | D | **NEW** | **1 min** | **min HR within the window** — use for daily lows |
| `0x05` | `hr_max` | bpm | 1 | D | **NEW** | **1 min** | **max HR within the window** — use for daily PEAKS |
| `0x10` | `spo2` | % | 1 | D | | — | raw, unchanged |
| `0x20` | `skin_temp` | degC | 100 | D | | **5 min** | **MEAN skin temp over the window** |
| `0x21` | `skin_temp_dev` | degC | 100 | D | | — | deviation vs baseline (derived) |
| `0x22` | `skin_temp_cnt` | count | 1 | D | **NEW** | **5 min** | **samples backing the mean** — reject sparse windows |
| `0x30` | `bp_sys` | mmHg | 1 | E | | — | raw, unchanged |
| `0x31` | `bp_dia` | mmHg | 1 | E | | — | raw, unchanged |
| `0x40` | `steps` | count | 1 | C | | ≤1/min | **CUMULATIVE daily total — UNCHANGED semantics** |
| `0x41` | `active_energy` | kcal | 1 | C | | ≤1/min | cumulative (no producer yet) |
| `0x50` | `hrv_sdnn` | ms | 10 | D | | — | today: ECG spot check only |
| `0x51` | `hrv_rmssd` | ms | 10 | D | | — | reserved (continuous HRV lands in P3) |
| `0x52` | `hrv_lfhf` | ratio | 100 | D | | — | derived |
| `0x60` | `eda_scl` | uS | 100 | D | | — | raw, unchanged |
| `0x61` | `eda_scr_rate` | /min | 1 | D | | — | raw, unchanged |
| `0x62` | `stress` | index | 1 | D | | — | derived |

### `quality` bitmask (unchanged)

| bit | flag | meaning |
|---|---|---|
| `1<<0` | `VALID` | timestamp valid (RTC synced) + in range. **Always set** — the store drops anything else. |
| `1<<1` | `ON_SKIN` | sensor reported skin contact |
| `1<<2` | `LOW_MOTION` | IMU below the motion threshold |
| `1<<3` | `HIGH_CONF` | sensor/algo confidence high |
| `1<<4` | `DURING_SLEEP` | captured in a detected sleep window |
| `1<<5` | `MANUAL` | user-initiated spot check |

> On an **epoch** record, `quality` is the **AND** of every sample in the window —
> conservative. `ON_SKIN` set means the watch was on-skin for the *whole* window.

### `SUMMARY` fields (unchanged shape; `hr_min`/`hr_max` now exact)

`day_start_ts`, `hr_resting` + `hr_resting_valid`, **`hr_min` / `hr_avg` / `hr_max`**,
`spo2_avg` / `spo2_min` + `spo2_valid`, `temp_dev_x100` + `temp_dev_valid` +
`temp_baseline_nights`, `hrv_sdnn_x10` / `hrv_sdnn_base_x10` + `hrv_valid`,
`steps_today`, `energy_today_kcal`, `stress_last` + `stress_valid`.

---

## 4. `HELLO` — new fields (shipped earlier in `7d9112b`)

```
{ schema, group, dev, uid, head, oldest, types }
```

- **`uid`** — per-unit id (hex of the SoC device id). **Key your sample store on
  this, not on `dev`.** `dev` is a fixed class string (`"healthypi-move"`), identical
  on every watch: two watches paired to one phone would collide on
  `PRIMARY KEY (device, seq)`.
- **`oldest`** — oldest seq still retrievable. **`oldest > head` ⇒ the store is
  empty.** If your cursor is `< oldest - 1`, you have missed samples that are gone —
  **restart from `since = oldest - 1`** rather than looping.
- **`more`** on `SYNC` is now `n > 0 && next < head`, so it is never `true` on an
  empty page. Safe to loop on.

---

## 5. ⚠️ ONE-TIME: the on-flash log is discarded on first boot of this firmware

P2 changed the segment layout from variable-length to fixed-count so that a seq can
be located arithmetically. **The old segments cannot be read with the new mapping**
— doing so would return structurally-valid garbage, which is worse than an error. So
on first boot the firmware **deletes the old durable log** and restarts it at a clean
segment boundary.

**What this means for the app:**

- **`seq` is never rewound.** It is rounded *up* to a segment boundary, so some seq
  values are simply skipped and never existed. Your `PRIMARY KEY (device, seq)` dedup
  is safe; you will just never see those seqs.
- **The unsynced tail of the old log is gone** (bounded by retention, ~1 day).
- **`HELLO.oldest` will jump forward.** Follow it: if your cursor is below
  `oldest - 1`, resume from `oldest - 1`. If you already implement the `oldest`
  handling in §4, **this needs no special-casing** — it is exactly the "cursor is
  stale" path.

Anything the app already synced and stored stays valid.

---

## 6. What is NOT changing

- `RECORDS` (episodic raw captures — ECG, GSR/BioZ, HRV R-R): untouched.
- `ACK` still **does not free flash** (`hpi_hs_ack()` is a no-op; retention is
  size-based). Do not depend on it to reclaim space.
- SMP transport, netbuf size, batch size (40): untouched, as requested.

---

## 7. Coming next (not in this drop)

- **P3 — continuous HRV.** The MAX32664C already emits R-R intervals with a
  confidence value and nothing reads them; HRV/stress today needs a manual ECG spot
  check. P3 will compute RMSSD / SDNN / mean-RR / **coverage** in 5-minute gated
  windows. New additive type ids — you will want to **respect `coverage`** and not
  plot low-coverage windows (they are motion artefacts, not physiology).
- **P4 — `SEGS` bulk fetch.** Whole-segment chunked get, mirroring `RECORDS get`
  (which you already implement). Segments are immutable once rolled, so "already have
  segment N? skip it" is safe forever. This is the "send the whole file" model.
- **P5/P6** — background flash churn + retention. No app impact.

---

## 8. Questions back to the firmware side

1. **Does anything in the app consume 3-second-resolution HR?** As far as we can
   trace, no — but please confirm. If you have built on raw sample density, we will
   keep a high-resolution window for the last N hours.
2. **Does the app currently recompute HR min/max from the raw series, or read them
   from `SUMMARY`?** This determines whether §2 is real work or zero work for you.
