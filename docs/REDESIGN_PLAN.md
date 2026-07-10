# Redesign implementation plan

Tracks the implementation of the **HealthyPi Move app redesign** (Claude Design
handoff in [design_handoff_healthypi_move_app/](design_handoff_healthypi_move_app/)).
Dark-first, strict Material 3, per-metric identity colors, matched to the watch UI.
Read the handoff `README.md` for the final tokens and per-screen specs; this file
records **how** we build it against *this* codebase and **why** the sequence is what
it is.

## Ground truth that shapes the plan

Two facts dominate every decision:

1. **The design is specified against a data pipeline this repo hasn't built yet.**
   The handoff's "rewrite assumptions" describe roadmap Phases 2–5, not today's app.
   Only **HR, SpO₂, wrist temp, steps** exist end-to-end (as `health_trends`
   min/max/avg rows). HRV/RMSSD/SDNN, stress index, EDA/SCR, RR intervals, 30-day
   baselines, median bins, sleep/night windows — **no producing code**. ECG/HRV/GSR
   exist only as raw downloadable waveforms. `HsSummary`/`HealthStoreClient` would
   carry the richer metrics but are currently unreferenced dead code.

2. **The handoff was written against a stale checkout.** It says the app lives in
   `move/` (flattened) and to use `flutter_blue_plus` (removed — now `universal_ble`).
   Ignore both. `material_symbols_icons` and `fl_chart` are already deps.

### Decisions taken (with the user)

- **Unbacked metrics render honest zero-states**, never fabricated data. The
  handoff already mandates this for EDA ("never fabricate a daily EDA aggregate");
  we extend it to *every* metric with no producing code. Enforced at the **data
  layer** (`HealthRepository` returns a "no data" signal), not per-screen.
- **Fonts are bundled TTFs**, not the `google_fonts` runtime download. The four
  OFL variable fonts (Rubik, Manrope, JetBrains Mono, Saira) live in
  `assets/fonts/`. Works offline — this is a BLE app used away from wifi. ~1.2 MB.
- **Data store is redesigned per the Health Store API in this same pass** (user
  directive). The schema decides what charts can ask for, so it goes *first*; UI
  built on the old `min/max/avg` shape would need rewriting once `hs_samples` land.

## Adaptive layout (handoff turn 4: 4a, 4b) — structural, not cosmetic

M3 window-size classes. This forces the shell and several screens to be **built as
list-detail two-panes from the start** — retrofitting two-pane later is expensive.

- **Navigation**: `NavigationBar` for compact (< 600 dp) ↔ `NavigationRail` for
  expanded (≥ 840 dp; we treat the 600–840 medium band as rail too). Rail = 84 dp,
  bg `#12161A`, watch avatar top, 4 destinations, battery pinned bottom.
- **List-detail two-pane** on expanded for **Home (4a)**, **Trends hub**,
  **Recordings**, **Dev console**: detail renders *in place* (no pushed route);
  collapses to single-column + pushed routes on compact. Home left pane 432 dp
  (hero HR at 38sp + 2a signal list, selected row highlighted); right pane = the
  selected metric's full trend detail.
- **Device** and **Settings** stay single-column, centered, max-width ~640.
- **Live dual-signal (4b)** is a *new* screen: two synchronized sweep channels
  (ECG amber + IMU accel green) on a shared `t_ms` timebase — not a reflow.
- Charts are **width-parameterized** `CustomPainter`s driven by `LayoutBuilder`
  (candlesticks respan 336 → ~540 on tablet), so responsiveness is free once the
  painters take a size.

Implemented via a `Breakpoints` helper + reusable `AdaptiveScaffold` (nav switch)
and `AdaptiveListDetail` (two-pane ↔ pushed route) in `lib/ui/`.

## Screen inventory (20 approved)

Home 2a + 1a grid variant (persisted switcher) · Trends hub · HR 1d → **3a**
(HRV/Poincaré) · Steps 3b · SpO₂ 3c · Temp 3d · Stress&EDA 1e + **2b zero-state** ·
Live ECG 1f · Onboarding 1g · Device 1h · Settings 1i · BLE console 1j ·
Recordings 2c · Preview+CSV 2d · **Tablet two-pane home 4a** · **Tablet dual-signal
live 4b**. (1b scores + 1c list = exploration only, do not build.)

## Build sequence

Everything new lives **beside** the old screens so the app stays runnable; routes
switch at the end. Increments:

### This pass — foundation + data layer + home (proof of integration)

- **A0 — Data layer.** `database_helper.dart` → **v6**, additive per design doc §5:
  `hs_samples` (raw system-of-record), `hs_types` (registry), `hs_sync_state`
  (cursor/head). Add `value_median` to `health_trends`. `_onUpgrade` extended,
  nothing destructive. Trend derivation aggregates `hs_samples` → `health_trends`
  incl. median (watch the centi-degree temp trap, DECISIONS §3). **`HealthRepository`**
  — the single read API the redesigned screens consume; returns typed view models
  *or a no-data signal* per metric; reads derived trends + `SUMMARY` when present.
- **A — Theme + components.** `lib/theme/`: `ColorScheme.fromSeed(0xFFF59E0B, dark)`
  + exact surface overrides; `ThemeExtension<HpiMetricColors>` (6 identities + tint
  helpers); the 4 type ramps (Rubik/Manrope/JetBrains Mono/Saira). `lib/ui/`
  components: card, list row, segmented control, stat chip, pill, filled/tonal/
  neutral buttons, nav destinations. Old `hPi4Global` styles stay so the 21 legacy
  screens keep compiling.
- **B — Responsive shell.** `AdaptiveScaffold` (NavigationBar↔Rail) + 4 tabs;
  `AdaptiveListDetail`. Rework `main.dart` routes, keep old paths as aliases.
- **C — Chart library.** `lib/ui/charts/`, all `CustomPainter`, width-parameterized:
  sparkline, min–max candle, hourly bars, sparkbars. (Poincaré/ring/percentile/
  lollipop/dip-dot/minimap/ECG-sweep land with their screens in later passes.)
- **D(home) — 2a + 1a.** Home with persisted list/grid switcher, reading
  `HealthRepository`; honest zero-states for stress/EDA; tablet two-pane (4a).
- **Verify**: `flutter analyze` must not exceed the 445 baseline; `flutter build
  bundle` compiles.

### NOT in this pass (needs hardware / later increments)

- **Live `HealthStoreSyncManager`** device wiring. Roadmap Phase 2 requires the
  `TYPES`/`SUMMARY`/`RECORDS` wire shapes pinned against a **real Move** first
  (design doc §10). We build the schema, derivation, and repository *ready to
  receive* samples and structure the sync seams, but do **not** claim device-
  verified sync — this keeps the destructive-ack rule safe (never ack unpersisted
  data). The remaining screens (trend details, live, onboarding, device, settings,
  console, recordings, tablet variants) follow in subsequent passes.

## Relationship to ROADMAP.md

A0 implements roadmap **Phase 2** (schema) + **Phase 3** (derivation) at the data
level and **Phase 5**'s `SUMMARY` read, minus the device-driven sync loop. The UI
redesign is orthogonal to the sync-plumbing phases and proceeds in parallel behind
the `HELLO` feature gate.
