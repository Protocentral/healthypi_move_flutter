# HS-2 P1 + P2 + P3 (+P5/P6) — App Handoff

> **From: the HealthyPi Move *firmware* coding agent.**
> Repo: `healthypi-move-fw-next`. Commits: `794d756` (P1), `a6fd48e` (P2),
> P3 = continuous HRV + HRV-derived stress (see §6, **new — action needed**).
> Status: **VALIDATED ON DEVICE AND END-TO-END WITH THE APP (2026-07-12).**
> - P2 layout migration ran on hardware exactly as designed: seq 35088 -> 35392
>   (segment 79), `layout=2`, seq moved FORWARD and was never rewound.
> - P1 measured on a 7-day synthetic dataset: ~48,000 samples/day fed -> ~5,500
>   records/day stored, i.e. the promised **~8x reduction**. The app pulled the full
>   ~38,900-record backlog successfully.
> - `HR_MAX` demonstrably preserves peaks the mean destroys: a minute whose true max
>   was **164 bpm** has a mean of **136**. That 28 bpm is exactly what a mean-only
>   epoch would have silently thrown away.
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
| **Anything new to ignore?** | **Yes** — filter out samples with `quality & (1<<6)` (`SYNTHETIC`). See §2(c). |
| **Anything new to *use*?** | **Yes** — **continuous HRV** (RMSSD/SDNN/mean-RR), no ECG needed. But you must respect `hrv_coverage`. See §2(d). |

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

### (c) ⚠️ Filter out `HPI_HS_Q_SYNTHETIC` (quality bit `1<<6`) — NEW

The firmware can now generate synthetic data on-device, so that trends, the 7-day
skin-temp baseline and sync-at-scale can be tested without wearing the watch for a
week (a 7-day baseline otherwise takes seven days). **Synthetic samples land in the
same store, alongside real ones** — on a bench board we observed the real
temperature sensor's readings interleaved with generated data.

Every fabricated sample carries `quality & (1<<6)`. **The app must not render a
synthetic sample as a health measurement.** Drop them from charts, summaries and any
export. Storing them is fine (and useful) as long as they are flagged.

This only ever appears on a build with `CONFIG_HPI_HS_SYNTH=y`, which is off in
release — but the app should be robust to it regardless, because the whole point of
the bit is that fabricated data can never be *silently* mistaken for a measurement.

### (d) ⚠️ NEW CAPABILITY: continuous HRV — and you **must** respect `hrv_coverage`

The watch now produces **HRV continuously** from the wrist PPG, in 5-minute windows —
no ECG spot check required. This is new product surface: overnight HRV, recovery, and
a much stronger stress signal (ours is EDA-only today).

You get four types per window: `hrv_rmssd` (0x51), `hrv_sdnn` (0x50),
`hrv_mean_rr` (0x53) and **`hrv_coverage` (0x54)**.

**`hrv_coverage` is not decoration.** It is the share of the 5-minute window actually
backed by valid beats. **Do not plot or trend a window without checking it.**

- The firmware already discards anything below **50 % coverage or 30 beats**, so what
  reaches you is never garbage — but coverage still varies (50 % vs 95 % are very
  different confidences in the same number).
- **A low-coverage window is how a noisy five minutes becomes a "recovery dip" in the
  UI.** Weight by it, grey it out, or exclude it — but do not treat 55 % and 95 %
  windows as equally trustworthy.
- Overnight (still, on-skin) is where coverage is high and HRV is most meaningful. That
  is the window worth surfacing.

**RMSSD is the headline metric** — it is what Whoop/Oura report, and it is the most
robust of the four over a short window. `hrv_sdnn` (0x50) previously appeared only after
a manual ECG session; it is now continuous, so any UI keyed on "HRV = ECG spot check"
needs revisiting.

### Also
- **Render `hr` as a per-minute mean** (a smoother line with ~1 point/min), not as
  instantaneous readings.
- **Remove any "no sample in the last N seconds ⇒ stale/disconnected" logic** keyed
  on the old ~3 s cadence. It will misfire at 1 sample/min.
- **Treat `ts_utc` on epoch types as the END of the window.**

---

## 3. Full type registry (as-built)

`TYPES` is **paged, 5 entries per call**. `total` is now **21** (was 16). Loop
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
| `0x50` | `hrv_sdnn` | ms | 10 | D | | **5 min** | **now CONTINUOUS** (was: ECG spot check only) |
| `0x51` | `hrv_rmssd` | ms | 10 | D | **NEW (live)** | **5 min** | **RMSSD — the headline HRV metric** |
| `0x52` | `hrv_lfhf` | ratio | 100 | D | | — | derived (not emitted yet) |
| `0x53` | `hrv_mean_rr` | ms | 1 | D | **NEW** | **5 min** | mean R-R interval |
| `0x54` | `hrv_coverage` | % | 1 | D | **NEW** | **5 min** | **⚠️ quality gate — see §2(d)** |
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
| `1<<6` | **`SYNTHETIC`** | **fabricated test data — NOT a measurement. FILTER THIS OUT of anything user-facing.** |

> On an **epoch** record, `quality` is the **AND** of every sample in the window —
> conservative. `ON_SKIN` set means the watch was on-skin for the *whole* window.

### `SUMMARY` fields (unchanged shape; `hr_min`/`hr_max` now exact)

`day_start_ts`, `hr_resting` + `hr_resting_valid`, **`hr_min` / `hr_avg` / `hr_max`**,
`spo2_avg` / `spo2_min` + `spo2_valid`, `temp_dev_x100` + `temp_dev_valid` +
`temp_baseline_nights`, `hrv_sdnn_x10` / `hrv_sdnn_base_x10` + `hrv_valid`,
`steps_today`, `energy_today_kcal`, `stress_last` + `stress_valid`.

**New in P3 (additive keys — old clients keep working):**

| key | meaning |
|---|---|
| `rmssd` | today's mean RMSSD, **ms x10** |
| `rmssd_base` | the user's 7-day rolling RMSSD baseline, ms x10 |
| `hrv_wins` | how many 5-min windows are behind that baseline |
| `stress_hrv` | **0..100** HRV-derived stress (see §6) |
| `stress_hrv_v` | **`false` = NO SCORE YET. It does not mean "zero stress".** |

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


---

## 6. P3 — continuous HRV, and a stress score that finally means something

**This is the one section with real app work in it.** Everything above was
firmware-internal; this adds a metric the app should surface, and one it should
reconsider.

### What changed in the firmware

The MAX32664C wrist sensor has been emitting **R-R intervals and a per-beat
confidence all along** — the driver even parsed them. **Nothing ever read them.**
(`smf_ppg_wrist.c` was not copying `rtor_confidence` at all: it was always zero.)

So HRV existed only if the user sat down and ran a **manual ECG session**.

P3 turns that into a continuous background metric: R-R intervals are gated
(confidence >= 80, on-skin, still, 300-1500 ms) and aggregated into **5-minute
windows** (the standard Task-Force short-term HRV window), each producing:

| type | key | id | scale |
|---|---|---|---|
| `HRV_RMSSD` | `hrv_rmssd` | `0x51` | ms x10 |
| `HRV_SDNN` | `hrv_sdnn` | `0x50` | ms x10 |
| `HRV_MEAN_RR` | `hrv_mean_rr` | `0x53` | ms |
| `HRV_COVERAGE` | `hrv_coverage` | `0x54` | **%** |

> **Bind on the `key` string from `TYPES`, never on the numeric id.** The ids above are
> the as-built registry (`hpi_hs_types.h`), but an earlier revision of this section had
> two of them wrong — and *both wrong ids collided with live, different types*
> (`0x52` is `hrv_lfhf`; `0x60` is `eda_scl`, tonic skin conductance in uS x100). An
> id-keyed client would not have failed to bind: it would have silently charted LF/HF as
> SDNN, and a conductance level as a 0..100 stress index. `TYPES` exists so ids can be
> renumbered; treat them as informational.

**`HRV_COVERAGE` is not decoration — please gate on it.** It is the fraction of the
5-minute window actually accounted for by accepted beats. A window with 300 clean
beats is ~100%; one with 40 beats scattered through a noisy walk is ~13%, and its
RMSSD is an artefact that will still plot as a perfectly plausible line. The firmware
already discards anything under 50%, but if you chart per-window HRV, **prefer high
coverage** and consider showing it.

### The stress score

The existing stress number (`stress_last`) is **EDA-only**: it comes from a *manual*
30-second GSR spot check and is scored on **absolute skin conductance**. Absolute EDA
is not comparable between people, or even between two sessions on the same person
(electrode contact, hydration, room temperature). It looks like a measurement and
behaves like a mood ring. **We have not removed it or changed it** — it still records
its own `STRESS` sample on a spot check.

`stress_hrv` is the replacement, and it differs in the way that matters: it is scored
**against the user's own rolling RMSSD baseline**, not against an absolute scale. An
RMSSD of 30 ms is low for one person and normal for another; only the deviation from
*their own* normal carries information. This is what Whoop/Oura/Garmin actually do.

```
ratio = rmssd / personal_baseline
  1.0 -> 50    at your own normal
  0.5 -> 100   HRV halved: strongly suppressed
  1.5 -> 0     HRV well above normal: relaxed
```

It uses the **most recent** window (where am I *now* vs my normal), and is suppressed
if that window is over an hour old — stale HRV is not current stress.

### What the app must do

1. **Read `stress_hrv` / `stress_hrv_v` from `SUMMARY`.** Prefer it over `stress_last`
   for the Stress card. It needs no user action; the EDA spot check needs 30 seconds of
   deliberate effort.
2. **`stress_hrv_v == false` means SHOW NOTHING** — "Building your baseline" or similar,
   *not* a zero. It stays false until ~20 valid windows (~100 min of still, on-skin HRV;
   realistically one decent night). A stress score presented before the baseline exists is
   a number the user would believe and that means nothing. This is the single most
   important line in this section.
3. **Distinguish the two `STRESS` samples in the sample stream.** Both the continuous
   HRV score and the EDA spot check record type `STRESS` (key `stress`, id `0x62`). They are told apart by
   the **`MANUAL` quality bit (`1<<5`)**: set = the EDA spot check, clear = the continuous
   HRV score. If you plot them on one axis without separating them you are mixing two
   different scales.
4. If you chart HRV, chart **`HRV_RMSSD`**, not SDNN — RMSSD is the short-window
   parasympathetic marker and is what the stress score is built on.

### Also shipped alongside (no app impact, FYI)

- **P5** — the summary recompute did **9 full scans** of the log per rebuild; now 1.
- **P6** — retention: segments now hold 4480 records and the summary scan skips segments
  outside the 7-day window. Retention went from **~1.2 days to comfortably past a week**,
  which was the entire point of P1: a missed sync must not be permanent data loss.
- The store's on-disk layout is now **v3**; migration is automatic and, as with v2, **seq
  only ever moves forward** — your `(uid, seq)` dedup stays safe across the upgrade.

### Synthetic data now covers P3 (2026-07-13)

The `SYNTH` generator previously emitted **no RMSSD and no coverage at all**, so on a
synthetic dataset `stress_hrv_v` could never go true and your `baselining` state had
nothing to come out of. Fixed. A 7-day generate now produces ~1,650 HRV windows, so:

- **`stress_hrv_v` goes true**, and **today is generated as a deliberately high-strain
  day**, so the score reads *elevated* rather than neutral — a fixture whose right
  answer is exactly 50 cannot tell a working score from a stub returning the midpoint.
- **`hrv_coverage` spans 50-98%** (asleep ~90, awake ~71 — awake HRV coverage really is
  that much worse), so your coverage gate has real variety to act on.
- **It never emits a window below 50%**, because the firmware discards those *before*
  recording — a fixture that emits samples the device cannot produce is a fixture that
  lies. Your defensive re-check is still correct (our floor is a compile-time constant
  and can move); it just will not fire on this data. Don't read that as your gate being
  dead.
- Everything still carries **`SYNTHETIC` (`1<<6`)** — keep filtering it.
