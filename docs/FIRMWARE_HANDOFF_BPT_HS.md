# Firmware handoff — BPT calibration over HPI_HS (MCUmgr group `0x1000`)

**Audience:** HealthyPi Move firmware.
**Status:** proposed, app side already staged behind a transport seam.
**Companion contract:** `HPI_HS_API.md` (firmware repo). This doc *extends* that
group; it does not change any existing command.

---

## 1. What this asks for

Move the three BPT (blood-pressure) **calibration control commands** off the
custom cmd/data GATT service and into the **HPI_HS MCUmgr group `0x1000`** — the
same group that already carries `HELLO`/`SYNC`/`RECORDS`/`SUMMARY`/`ACK`/`SET_TZ`.
This is the last consumer of the retiring custom-command channel; folding it into
HPI_HS gives BPT the same reliable, framed, CRC-checked, sequence-numbered
request/response path as everything else, and lets the app drop the raw
write+notify code path entirely.

The precedent to copy is **`SET_TZ` (cmd 7)**, added recently: a small vendor
`WRITE` with a CBOR request `{off:<int>}` and a `{rc}` response. BPT is the same
shape, plus one wrinkle called out in §4.

## 2. The one hard constraint — SMP has no server push

BPT calibration is **two** things on the wire, and only one of them moves cleanly:

| Piece | Nature | Fits SMP? |
|---|---|---|
| **Control** — enter mode, start a point (`sys,dia,idx`), end mode | request → response | ✅ yes |
| **Feedback** — contact quality + progress `0→100`, streamed continuously while a point runs | **server → client push** | ❌ no |

MCUmgr/SMP is strictly client-initiated request→response; the server cannot push
an unsolicited notification. So the feedback cannot simply "become an SMP
command." Two ways to resolve it — **firmware should confirm which to implement
(§5)**:

- **(A) Hybrid (recommended).** Control commands move to HPI_HS; the live
  `[status, progress]` feedback **stays** on the existing notify characteristic.
  Least firmware churn, keeps push where push belongs.
- **(B) Fully on SMP.** Add a pollable `BPT_CAL_STATUS` read (cmd 10 below); the
  app polls it at ~5–10 Hz during a point. No notify characteristic needed, but
  chatty and the firmware must keep a current status snapshot readable at any
  time.

The command set in §4 includes the status read so **both** options are covered by
the same firmware; the only decision is whether the app polls it or listens on
the notify characteristic.

## 3. Current protocol (what exists today, to be replaced)

Custom cmd/data GATT service (`UUID_SERVICE_CMD`), for reference:

| Op | Bytes (write to `UUID_CHAR_CMD`) | Meaning |
|---|---|---|
| Set mode | `0x60` | Enter BPT calibration mode |
| Start point | `0x61, sys, dia, idx` | Begin point `idx` (0-based) with the cuff reading `sys`/`dia` (each one byte) |
| End | `0x62` | Exit calibration mode |

Feedback: notifications on `UUID_CHAR_CMD_DATA`, **2 bytes** `[status, progress]`,
streamed while a point runs. A full calibration is **3 points**.

## 4. Proposed HPI_HS command set (group `0x1000`)

Existing ids run 0–7 (`HELLO`…`SET_TZ`). BPT takes the next block. **Ids are
proposed — firmware owns the final numbering; the app binds to fixed ids, so pin
these before either side ships.** CBOR keys are kept short to match the group.

| Cmd | Name | Op | Request | Response | Replaces |
|---|---|---|---|---|---|
| **8** | `HPI_HS_CMD_BPT_CAL_ENTER` | WRITE | `{}` | `{rc}` | `0x60` |
| **9** | `HPI_HS_CMD_BPT_CAL_POINT` | WRITE | `{sys:<u8>, dia:<u8>, idx:<u8>}` | `{rc}` | `0x61,…` |
| **10** | `HPI_HS_CMD_BPT_CAL_STATUS` | READ | `{}` | `{st:<u8>, prog:<u8>, idx:<u8>, run:<bool>}` | (poll path) |
| **11** | `HPI_HS_CMD_BPT_CAL_END` | WRITE | `{}` | `{rc}` | `0x62` |

Field semantics:

- **`sys`, `dia`** — the reference cuff reading for this point, mmHg, 0–255. Same
  values the old `0x61` payload carried.
- **`idx`** — 0-based point index (0,1,2). Firmware should reject an out-of-range
  or out-of-order index with a non-zero `rc` rather than silently accepting it.
- **`st`** — current status code (§6). **`prog`** — 0–100. **`run`** — true while
  a point measurement is in flight (false before the first point and after a
  terminal `st` of 2/6).
- **`rc`** — 0 on success; see §7.

Notes:

- `BPT_CAL_ENTER`/`END` carry an empty map, exactly like a parameterless vendor
  command; keep them explicit (don't overload one toggle) so the app's
  enter/measure/exit lifecycle maps 1:1.
- If option (A) is chosen, cmd 10 is still worth implementing — it lets the app
  reconcile state after a reconnect mid-calibration without waiting for the next
  push.

### Alternative: a sibling group `0x1001`

If overloading the health *store* group with device *control* is unwanted,
these four commands can live in a new `0x1001` "device control" group instead,
with identical shapes. The app seam (§8) doesn't care which group id it is — it's
one constant. Firmware's call; the app follows.

## 5. Decision firmware must return

1. **Feedback transport:** hybrid (A, keep notify) or poll (B, cmd 10 only)?
2. **Final command ids** (8–11 as proposed, or others), and **group** (`0x1000`
   vs `0x1001`).
3. Whether `BPT_CAL_ENTER` implicitly resets any in-progress calibration, or
   errors if already in calibration mode.

## 6. Status code contract (unchanged from today — the app depends on these)

The app renders and reacts to these exact codes; keep them stable across the move.

| `st` | Meaning | App reaction |
|---|---|---|
| 0 | No PPG signal | "seat the sensor", contact = bad |
| 1 | Good finger signal | contact = good, ready |
| 2 | **Point complete** | commit the point, advance |
| 3, 16, 19 | Weak PPG | warn, contact stays as-is |
| 4 | Too much motion | warn |
| 6 | **Calibration failed** | offer retry, keep earlier points |
| 23, 24 | No finger contact | contact = bad |

The two **terminal** codes for a running point are **2 (complete)** and **6
(failed)** — the app moves the point out of the "measuring" state only on these.

## 7. `rc` / error semantics

Follow the group's existing convention (`rc == 0` ⇒ ok; non-zero ⇒ `SmpException`
on the app side):

- `-EBUSY` — a point measurement is already running (reject a second
  `BPT_CAL_POINT`).
- `-EINVAL` — bad `idx` (out of range/order) or missing `sys`/`dia`.
- unknown-command `rc` on firmware that predates this — this **is** the capability
  signal; see §8.

## 8. Capability gating & coexistence

- **Version bump.** Increment the HPI_HS **group version** (the field `HELLO`
  returns) when these commands land, so the app can detect support without
  probing each command. (Schema version is for the sample/registry wire; group
  version is the right axis for "the group learned new commands".)
- **App probe.** The app already reads `HELLO` on connect. It will use the HPI_HS
  BPT path when the group version advertises it, and otherwise fall back to the
  **existing custom `0x60`/`0x61`/`0x62`** path — which must keep working until
  the fleet has moved. No hard cutover.
- **No silent divergence.** Both paths drive the *same* firmware BPT engine and
  the *same* status codes; only the framing differs.

## 9. Firmware implementation notes

- New handlers alongside the existing HPI_HS ones in `hpi_hs_mgmt.c`
  (e.g. `hs_h_bpt_enter` / `hs_h_bpt_point` / `hs_h_bpt_status` / `hs_h_bpt_end`),
  registered in the group's command table at the chosen ids.
- These handlers should call into the **same** BPT calibration engine the current
  `0x60`/`0x61`/`0x62` custom-command handler calls — this is a transport change,
  not a re-implementation of the calibration math.
- For option (B), the engine needs to expose a cheap "current status" snapshot
  (`st`, `prog`, `idx`, `run`) that `hs_h_bpt_status` can read without disturbing a
  running measurement.
- Keep the notify characteristic for option (A); it already streams `[status,
  progress]` and needs no change.

## 10. App-side readiness (already done — this is an adapter swap)

The app's BPT logic was extracted into a transport-agnostic state machine
(`lib/ble/bpt_calibrator.dart`) behind a `BptCalTransport` interface:

```dart
abstract class BptCalTransport {
  Stream<Uint8List> get statusStream;      // [status, progress] feedback
  Future<void> sendCommand(List<int> bytes);
  bool get isConnected;
}
```

Today a `_ConnCmdBptTransport` adapter binds this to the custom CMD GATT service.
When firmware ships the commands above, the app adds an **`HpiHsBptTransport`**
adapter that:

- maps `enter` / `startPoint(sys,dia,idx)` / `end` onto the new HPI_HS WRITEs
  (via the existing `HpiHs` client — same place `SET_TZ` lives), and
- feeds `statusStream` either from the notify characteristic (option A) or from a
  poll loop over `BPT_CAL_STATUS` (option B).

No change to the calibration screen or the state machine — the seam exists
specifically so this move is one new file. See `docs/DECISIONS.md` §13 and the
Roadmap Phase 8 entry.

## 11. Open questions for firmware

1. Feedback transport: A (keep notify) or B (poll `BPT_CAL_STATUS`)? (§5)
2. Final command ids and group (`0x1000` vs `0x1001`). (§4)
3. Does `BPT_CAL_ENTER` reset or error when already in calibration mode? (§5)
4. Is the point count fixed at 3 in firmware, or should the app read it (e.g. a
   field in a future `HELLO`/status)? Today it is hard-coded to 3 on both sides.
5. Any additional status codes the current firmware can emit that aren't in §6?
   The app tolerates unknown codes (renders a generic "sensor status N") but will
   not treat them as terminal.
