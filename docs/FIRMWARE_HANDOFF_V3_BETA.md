# Firmware handoff — v3.0.x beta findings

Firmware-side work arising from a beta report against the HealthyPi Move companion
app (v3.0.1+89). Eight defects were reported; **six were app-side and are fixed**
in the app repo. The items below are the remainder, plus one contract
confirmation that needs no code change.

References are to `healthypi-move-fw` at the tree this was analysed against —
please re-check line numbers before editing, the surrounding code moves.

| # | Item | Severity | Shape of change |
|---|---|---|---|
| FW-1 | GSR characteristic notifies ECG samples | **High** — live GSR is wrong data | Delete one line |
| FW-2 | No way for a client to know ECG/GSR capture is active | Medium — UX dead end | New HPI_HS cmd or GATT status |
| FW-3 | PPG records declare `SFMT_I32` for `uint32_t` data | Low — latent | Type or enum change |
| FW-4 | Record payload units/scaling undocumented | Low — doc | `HPI_HS_API.md` |
| FW-5 | Signal enum — **no change needed**, confirmation only | — | — |

---

## FW-1 · The GSR characteristic emits ECG samples

**Severity: high.** Anything reading live GSR receives ECG.

`app/src/data_module.c`, in the ECG drain block:

```c
if (k_msgq_get(&q_ecg_sample, &ecg_sensor_sample, K_NO_WAIT) == 0)
{
    processed_data = true;
    if (settings_send_ble_enabled)
    {
        ble_ecg_notify(ecg_sensor_sample.ecg_samples, ecg_sensor_sample.ecg_num_samples);
        ble_gsr_notify(ecg_sensor_sample.ecg_samples, ecg_sensor_sample.ecg_num_samples);  // <-- wrong
    }
```

The second call pushes the **ECG** buffer to the GSR characteristic
(`hpi_ecg_gsr_service.attrs[4]`, `ble_module.c:301-317`).

This is a duplicate, not a missing feature: the correct GSR notify already
exists in the BioZ drain block, ~100 lines below, sourced from the right queue —

```c
if (k_msgq_get(&q_bioz_sample, &bsample, K_NO_WAIT) == 0)
{
    if (settings_send_ble_enabled)
    {
        ble_gsr_notify(bsample.bioz_samples, bsample.bioz_num_samples);   // correct
```

**Requested change:** delete the `ble_gsr_notify(...)` call inside the ECG block.
Nothing else moves.

**Why it matters beyond "wrong trace":** the two sources run at different rates
(ECG 128 Hz, BioZ 32 Hz) and both write the same characteristic, so a subscriber
currently receives two interleaved signals on one stream with no way to tell them
apart. Any consumer that integrates or thresholds GSR is acting on ECG.

**Verify:** subscribe to `babe4a4c-7789-11ed-a1eb-0242ac120002` during an ECG spot
check. Expect ~32 notifications/s of slowly-varying conductance, not ~128/s of
ECG. Before the fix the app's Live → GSR view shows an ECG-shaped trace; after,
it should be flat-ish and slow.

---

## FW-2 · Expose whether an ECG/GSR capture is running

**Severity: medium.** This is the root cause of the beta report *"Live — PPG
streaming is working but ECG is not, out of 4 times only the second time it
streamed."*

ECG and GSR samples are only queued while a measurement is active on the watch:

```c
/* smf_ecg_bioz.c */
if (get_ecg_active() || get_gsr_active())
{
    int ret = k_msgq_put(&q_ecg_sample, &ecg_sensor_sample, K_NO_WAIT);
```

`g_ecg_active` is set by the Start button on the watch's own ECG screen
(`scr_ecg_monitor.c`; `smf_display.c` documents it as *"spot check: gated on
Start/Stop"*). Wrist PPG, by contrast, free-runs — which is exactly why PPG
always worked and ECG appeared to work only occasionally.

**This behaviour is correct.** The gap is that a BLE client cannot observe it, so
a phone that has subscribed successfully and a phone whose watch is simply idle
look identical: an empty grid under a "connected" badge. The app has been changed
to explain the precondition in prose, but it is guessing — it infers "idle" from
a 3-second sample drought and cannot distinguish *not started*, *leads off*, or
*subscribe silently failed*.

**Requested change — either is fine, in preference order:**

1. **A status read on HPI_HS** (preferred; mirrors `BPT_CAL_STATUS`, cmd 10).
   Commands 0–11 are taken (`hpi_hs_sync.h:33-56`), so this would be **cmd 12**:

   ```
   HPI_HS_CMD_STREAM_STATUS = 12,  /* READ {} → {ecg:bool, gsr:bool, ppg:bool, lead_off:bool} */
   ```

   SMP cannot push, so the app would poll it (~1 Hz) while the Live screen is
   open — the same pattern already used for BPT calibration. Cheap and needs no
   new GATT service.

2. **A notify-on-change status byte** on the existing ECG/GSR service. Better
   (event-driven, no polling), but costs a characteristic and a UUID.

If **(1)**, please also confirm whether `lead_off` should be reported per-signal;
the app would like to distinguish "not started" from "started but leads off",
since the user action differs (press Start vs. touch the bezel).

**Longer term, worth discussing:** should a phone be able to *start* an ECG spot
check remotely? It would remove the mode error entirely. We are not requesting it
now — there are safety and consent questions around a phone initiating a
measurement — but if you see a clean way to do it, say so and we will scope the
app side.

**Verify:** with the watch idle, the status read reports `ecg:false`; press Start
on the watch and it flips to `true` within a poll interval, and samples begin
arriving on the ECG characteristic in the same window.

---

## FW-3 · PPG records declare a signed format for unsigned data

**Severity: low** (latent — currently benign).

`ppg_record_reconcile()` opens PPG records as `HPI_HS_SFMT_I32`:

```c
int r = hpi_hs_rec_start(sig, HPI_HS_SFMT_I32, 1, rate);
```

but the payload appended is `uint32_t`:

```c
uint32_t raw_green[PPG_POINTS_PER_SAMPLE];   /* hpi_common_types.h */
hpi_hs_rec_append((uint32_t)s_ppg_wrist_rid, ppg_wr_sensor_sample.raw_green, ...);
```

Clients decode `SFMT_I32` as **signed** (this is pinned in `HPI_HS_API.md` and in
the Dart client). MAX32664C counts sit well inside 31 bits today, so nothing is
misread in practice — but any sample at or above `0x8000_0000` would decode as a
large negative number, and the declared contract is simply not what is being sent.

ECG and BioZ are genuinely `int32_t` (`hpi_common_types.h:58, 75`) and are
correctly declared; this affects PPG wrist and finger only.

**Requested change — pick one:**
- add `HPI_HS_SFMT_U32` to `enum hpi_hs_sfmt` and declare PPG with it (cleanest,
  but a wire-contract addition — tell us and we will add the decode); **or**
- confirm in writing that PPG counts are bounded below 2³¹, and we will document
  the declaration as deliberate.

No urgency, but please don't leave it undecided — this is exactly the class of
"plausible but wrong" decode that cost us the signal-enum bug below.

---

## FW-4 · Document record payload units and scaling

**Severity: low** (documentation).

`hpi_common_types.h:75` says BioZ is *"Conductance in µS × 100 (fixed-point from
driver)"*. That scaling exists nowhere in `HPI_HS_API.md`, so the app currently
plots and exports GSR in raw counts with no unit — and a client written from the
protocol doc alone has no way to recover µS.

**Requested change:** for each `hpi_hs_signal`, state in `HPI_HS_API.md` (or a
firmware doc we can mirror) the physical unit and any fixed-point scale factor —
BioZ µS×100, ECG (LSB → mV?), PPG (raw counts, unitless?), HRV (ms), accel
(LSB → g?). We will mirror it into the client and label the axes.

---

## FW-5 · Signal enum — confirmation only, no change

`enum hpi_hs_signal` (`hpi_hs_types.h:155-162`) is **1-based**:

| Value | Signal |
|---|---|
| `0x01` | ECG |
| `0x02` | BioZ / GSR |
| `0x03` | PPG wrist |
| `0x04` | PPG finger |
| `0x05` | HRV R-R |
| `0x06` | IMU accel |

The client's table was 0-based, which shifted every code: ECG sessions listed as
GSR, GSR as PPG, IMU dropped off the end, and because nothing ever emits `0` the
ECG bucket could never be filled — so ECG recordings were invisible in the app
entirely. **This was the client's bug and is fixed there**, pinned against this
header and covered by a regression test.

**No firmware change requested.** Two asks:

1. **Treat these values as a wire contract.** Renumbering, or inserting a signal
   mid-enum, silently relabels every stored record on every deployed phone. If a
   new signal is needed, append it.
2. If you change the enum anyway, **say so in the release notes** — the failure
   is silent on both sides. Nothing errors; recordings just quietly become the
   wrong kind.

---

## Already handled app-side — no firmware action

Listed so nothing here gets debugged twice:

- Recordings mislabelled / ECG missing → client signal-code table (FW-5).
- Recorded PPG plotting as a straight line → client rendered raw DC-coupled
  counts on a min/max autoscale. The firmware data was fine; the app now uses a
  robust (median ± MAD) y-window and exports a detrended CSV column alongside the
  raw one.
- Trends export, Month/6M ranges, SpO₂ missing from trends, delete-all leaving
  stale UI and orphaned payload files → all client-side.
- Live ECG failing to start on the first attempt → partly the client (it never
  re-subscribed when the link came up, and the default signal could not be
  re-armed by tapping its chip); the remaining part is FW-2.

## Suggested order

FW-1 first and alone — it is a one-line deletion that fixes wrong data on a live
characteristic, and it is worth a point release on its own. FW-2 is the one that
closes the beta report properly and needs a short design agreement (which of the
two options, and the `lead_off` question) before implementation. FW-3 and FW-4
can ride the next feature build.
