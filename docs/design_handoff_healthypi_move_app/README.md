# Handoff: HealthyPi Move Companion App Redesign (Flutter)

## Overview
A complete redesign of the **HealthyPi Move Flutter app** (`github.com/Protocentral/healthypi_move_flutter`) — the BLE companion for ProtoCentral's HealthyPi Move watch. The redesign is **dark-first, strict Material 3**, matched to the recently redesigned on-watch UI: AMOLED-dark surfaces with **per-metric identity colors** (amber HR/ECG, blue SpO₂, teal EDA/GSR, indigo stress, green activity, coral temp) and a rewritten data-presentation model (hourly min/max trend bins, 30-day baselines, derived stress/recovery scores, percentile rollups).

It covers 18 screens: 4 home-dashboard explorations, trend details (HR + HRV with Poincaré plot, Steps, SpO₂ night focus, Wrist temp deviation, Stress & EDA incl. zero-state), live ECG streaming, onboarding/pairing, device management (sync/DFU/wipe), settings with developer mode, a BLE developer console, a long-recordings library (PPG · GSR · IMU), and a recording preview with CSV export.

## About the Design Files
The file `HealthyPi Move App Redesign.dc.html` is a **design reference created in HTML** — open it in a browser to see all screens on one pan/zoom canvas, each inside an Android (Pixel) frame. `support.js` is the prototype runtime and `android-frame.jsx` is the device bezel — both are viewer chrome, **not** production code.

**Your task is to recreate these screens in the existing Flutter codebase** (`move/` in the repo) using Flutter's Material 3 widgets and the app's established patterns (flutter_blue_plus / BLE service layer, existing routing). Do not port the HTML. Chart geometry in the prototype is procedurally generated — reimplement charts with `CustomPainter` or `fl_chart`.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, and copy are final. Recreate pixel-perfectly at 412 × 892 logical px reference size (values below are logical px = Flutter dp).

## Which options were approved
The canvas contains explorations grouped in two turns. **Build these:**

| Screen | Canvas id | Status |
|---|---|---|
| Home (combined hero + signal list) | **2a** | ✅ approved primary home. `1a` (tiles/grid) is the alternate layout the header switcher toggles to — persist as user preference |
| HR trend detail | **1d** | ✅ approved |
| Stress & EDA detail (with data) | **1e** | ✅ approved |
| Stress & EDA zero-state (no spot checks today) | **2b** | ✅ approved |
| Live ECG streaming | **1f** | ✅ approved |
| Onboarding scan & pair | **1g** | ✅ approved |
| Device page | **1h** | ✅ approved |
| Settings + developer mode | **1i** | ✅ approved |
| BLE developer console | **1j** | ✅ approved |
| Recordings library | **2c** | ✅ approved (PPG · GSR · IMU only — see note) |
| Recording preview + CSV export | **2d** | ✅ approved (IMU example) |
| HR detail v2 with HRV / Poincaré | **3a** | ✅ approved — supersedes 1d's layout; add the HRV card, keep 1d's stat chips + baseline card below (screen scrolls) |
| Steps & activity detail | **3b** | ✅ approved |
| SpO₂ detail (night focus) | **3c** | ✅ approved |
| Wrist temp detail (deviation focus) | **3d** | ✅ approved |
| Home tiles variant | 1a | build as the "grid" layout of the home switcher |
| Home "Scores" (recovery ring) | 1b | exploration only — do not build unless asked |
| Home "Signal list" | 1c | superseded by 2a |

## Design tokens

### Colors (dark theme — the only theme for v1)
Surfaces (warm-dark ramp, matches watch):
| Token | Hex | Use |
|---|---|---|
| `background` | `#0E1114` | Scaffold background |
| `surfaceContainer` | `#161B20` | All cards |
| `navBar` | `#12161A` | Bottom navigation bar |
| `waveformBg` | `#080B0D` | Live/preview waveform cards (near-black, with `rgba(255,255,255,.07)` 1px border) |
| `onSurface` | `#ECF0F2` | Primary text |
| `onSurfaceBright` | `#C6CDD1` | Icon buttons, secondary emphasis |
| `onSurfaceVariant` | `#9AA4A9` | Labels, section headers |
| `muted` | `#6B7478` | Captions, units, timestamps |
| `faint` | `#5B646A` | Chart axis labels |
| `disabled` | `#4A5359` | Trailing chevrons |
| divider | `rgba(255,255,255,.05)` | List row separators (also `.06`, `.07` for stronger borders) |
| chip bg | `rgba(255,255,255,.06)` | Neutral pills/chips (`.07`, `.08` for buttons) |

Per-metric identity colors (identical to the watch UI):
| Metric | Color | Tint container (14% alpha) |
|---|---|---|
| Heart rate / ECG / primary accent (Signal Amber) | `#F59E0B` | `rgba(245,158,11,.14)`; active states `.16–.20` |
| On-amber text (filled buttons) | `#1F1300` | — |
| SpO₂ / PPG / battery | `#6FB3CC` | `rgba(111,179,204,.14)` |
| EDA / GSR | `#2FBDA8` | `rgba(47,189,168,.13)`; dim variant `#5B8781`, bars dim `#1E6B60` |
| Stress / HRV | `#8B84F0` | `rgba(139,132,240,.14)` |
| Steps / activity / success | `#2EB865` | `rgba(46,184,101,.13)` |
| Wrist temp | `#F0845C` | `rgba(240,132,92,.14)` |
| Error / warnings | `#F87171` | — |

Flutter: define as a `ThemeExtension<HpiMetricColors>`; seed `ColorScheme.fromSeed(seedColor: Color(0xFFF59E0B), brightness: Brightness.dark)` then override surfaces with the exact values above.

### Typography
Three families, all on Google Fonts (`google_fonts` package):
- **Rubik 500** — every numeral/value (hero numbers, stats, battery %). Hero 42/40sp, card values 24–26sp, stat chips 17–19sp, small values 12–15sp. Letter-spacing −1 on heroes.
- **Manrope** — all UI text. Screen titles 22sp w800 (−0.3 ls), app-bar titles 18sp w800, card titles 13–14.5sp w800, body/supporting 11–13sp w500–700, section labels **10–11sp w800 uppercase + 1–1.4 letter-spacing**, nav labels 11sp (w800 active / w600 inactive).
- **JetBrains Mono** — developer surfaces: MACs, UUIDs, sample rates, packet log (10sp, line-height 1.9), file metadata (9.5–10.5sp), version footer.
- **Saira 700** — brand wordmark "PROTOCENTRAL" on onboarding only (12sp, +2.5 ls).
- Icons: **Material Symbols Outlined** (rounded/outlined, FILL 0, wght 400). Flutter: `material_symbols_icons` package. Sizes 13–22 as specified per screen.

### Shape, spacing, elevation
- Radii: cards **20** (some 18/22/24), tiles/inner chips **12–16**, pills/buttons **999 (full)**, mini stat cards 14–16.
- Spacing: 4-px grid. Screen side padding **16**; card padding 14–16; card gap 11–12; list row padding 11–12 × 12–14.
- No shadows anywhere (flat AMOLED); separation is via surface steps and hairline dividers.
- Motion: M3 standard easing `cubic-bezier(0.2,0,0,1)`, 150/300/500 ms. No bounces.

## Shared components

### Bottom navigation bar (M3 NavigationBar, customized)
4 destinations: **Home** (`home`) · **Trends** (`monitoring`) · **Live** (`ecg_heart`) · **Device** (`watch`). Bar: `#12161A`, top hairline `rgba(255,255,255,.06)`, padding 10×8. Active: 56×30 pill `rgba(245,158,11,.18)`, icon 22 `#F59E0B`, label w800 `#ECF0F2`. Inactive: icon/label `#9AA4A9`. Settings and dev console are pushed routes (back arrow, no nav bar); onboarding has no nav bar.

### Cards & list rows
Card = `#161B20`, radius 20, no border (exception: waveform cards and highlighted cards). Grouped list = one card, rows separated by `rgba(255,255,255,.05)` hairlines. Row anatomy: 34–38 icon square (radius 12, metric-tint bg, 18–19 icon) · title 13sp w800 + supporting 10.5sp `#6B7478` w600 · trailing value/chip · `chevron_right` 16–17 `#4A5359`.

### Buttons
- Filled primary: height 52, radius 26, bg `#F59E0B`, content `#1F1300` (icon 19 + 14sp w800).
- Tonal: height 38–40, radius full, bg = metric tint at .16, text 12sp w800 in metric color.
- Neutral: bg `rgba(255,255,255,.07)`, text `#C6CDD1`.
- Switch (M3): 44×26 track radius 13; ON = amber track, `#1F1300` thumb with 13 amber `check` icon.

### Segmented control
Full-width pill container `rgba(255,255,255,.06)` padding 3; segments radius full; active = `rgba(245,158,11,.2)` bg, 12sp w800 `#F59E0B`; inactive 12sp w700 `#9AA4A9`. Used for Day/Week/Month/6M and filter chips.

## Screens (approved set)

### 2a — Home
- Header row (padding 14 16 10): greeting "Good afternoon, {name}" 19sp w800 + date 12sp `#9AA4A9`; **layout switcher** — pill container with `grid_view` / `view_list` icon toggles (34×28 each; active = amber tint pill). Persists user choice: list = this screen, grid = the 1a tile layout; sync pill (watch icon 15 green + battery % Rubik 11.5).
- **Hero HR card**: header row `favorite` 17 amber + "HEART RATE" label + "RESTING 58" amber tint pill; value row 42sp Rubik "72" + "bpm" + "range 52–146"; 24-h median sparkline (56 high, amber 2px line over 12% amber area fill); x-axis 12A/6A/12P/6P/NOW (NOW in amber).
- **Signal list card** (rows per shared anatomy): Steps (hourly bars mini-chart, value 8,432) · SpO₂ (spark, 98 %) · Wrist temp (spark, 97.9°F, supporting "+0.3° vs baseline" in coral) · Stress (spark, 34, supporting "from HRV · continuous") · EDA·GSR (zero-state: dimmed icon `#5B8781`, title `#9AA4A9`, supporting "no spot check today", trailing teal-tint pill "MEASURE ON WATCH"). Each row navigates to its trend detail.
- Footer status line: `watch` 15 + "Synced 2 m ago · 1,440 trend bins" + "Sync now" amber w800 text button.
- Mini charts: 92×30 viewport, 1.6–2px strokes.

### 1a — Home, grid layout (switcher alternate)
Same header + hero HR card; below, **2-column grid** (gap 12) of metric tiles (radius 20, padding 14): icon 16 + uppercase label 10.5sp; value 24sp Rubik; per-tile extra — Steps: 6px progress bar (green, track `rgba(255,255,255,.08)`) + "goal 10,000"; SpO₂/Temp: 108×30 sparkline; Stress: 40 ring (stroke 5, 34% arc) + "Balanced"; EDA: "3 SCR" + timestamp; ECG: "Lead I · 30 s" + "Recorded 9:14 AM" + chevron.

### 1d — Heart-rate trend detail
- App bar: back (40 circle) · "Heart rate" 18sp w800 · `calendar_month`, `ios_share`.
- Segmented Day/Week/Month/6M (Day active).
- Hero: "72" 40sp Rubik + "bpm now" + right-aligned "Thu, Jul 10 · updated 2 m ago" 11.5sp.
- **Candlestick chart card** (plot 336×150): hourly min–max bars = vertical rounded strokes, width 8, round caps, amber at 92% opacity, x = 10 + hour×14; y maps 40–150 bpm onto plot height (padding 6 top/bottom). Overlays: sleep-window rect first 6 h `rgba(255,255,255,.03)`; **30-day resting baseline band** 56–61 bpm as `rgba(111,179,204,.14)` full-width rounded rect; hairline gridlines at 60/90/120 with right-side Rubik 9sp labels; x labels 12A/6A/12P/6P/11P. Legend row beneath: "Hourly min–max" (amber swatch) · "30-day resting band 56–61" (blue swatch) · "Sleep".
- Stat chips row (4 equal cards, radius 16): RESTING 58 (blue) / AVG 74 / MIN 52 / MAX 146 (amber) — value 19sp Rubik, label 9sp w800 +1 ls.
- **Baseline deviation card**: title "RESTING HR VS 30-DAY BASELINE" + right "−2.4 bpm this week" green; chart 336×76 — dashed midline, 7 daily lollipop bars (stroke 10, round caps, 5.5 px per bpm) — below baseline = green, above = amber; day labels FRI–THU.
- Data model: hourly bins `{hour, min, max, median}`; baseline = 30-day rolling resting-HR band (p25–p75); Week/Month/6M swap to daily/weekly candles (same painter).

### 1e — Stress & EDA detail (has data today)
- App bar: back · "Stress & EDA" · `ios_share`.
- Hero card: 104 ring (r 43, stroke 10, indigo arc = score%) with "34" 28sp centered; right column "Balanced" 16sp w800 indigo, "HRV 42 ms · updated 12:40 PM", teal tint pill `water_drop` + "3 SCR EVENTS TODAY".
- **Day chart card** "TODAY · STRESS INDEX + SCR EVENTS": 336×140 — stress index curve (indigo 2.2px + 16% area fill, 0–100 scale, gridlines at 50/100), **SCR events as 7px teal dots on a bottom event track** (y = 126) at their time-of-day x positions. Legend: line = "Stress index", dot = "SCR event (EDA)".
- **Weekly card** "THIS WEEK · P25–P75 VS MEDIAN": 336×96 percentile band (indigo 15% area between p25 and p75 polygons) + median polyline 2.2px; right "median 41"; day labels.
- Spot-check list card: rows "EDA spot check / Today 10:42 AM / `3 SCR · 6.2 µS`(mono)" etc.
- Data model: stress index = continuous, computed from HRV (+SCR rate when available), 0–100; EDA = discrete 30-s spot checks `{timestamp, scrCount, tonicUs, interpretation}` (interpretation thresholds from firmware `get_scr_context()`: 0 NONE, ≤2 LOW, ≤5 MODERATE, ≤8 ACTIVE, else VERY ACTIVE).

### 2b — Stress & EDA zero-state (no spot checks today) ⚠ important
Same app bar/hero geometry as 1e, but:
- Hero right column: "Continuous · from HRV · updated 12:40 PM" + explainer 11sp `#6B7478`: "Stress index runs all day from heart-rate variability. EDA adds skin-response detail when you take a spot check." (Stress ring still shows a value — it never depends on EDA.)
- Day chart: header right shows "0 SCR EVENTS" muted; stress curve renders normally; the SCR event track renders as an **empty dashed teal line** (`rgba(47,189,168,.25)`, dash 2 5) with legend "SCR event track — empty today".
- **Empty-state card**: dashed border `rgba(47,189,168,.35)` radius 20, centered — 48 teal-tint circle with `water_drop` 24; "No EDA spot checks today" 14sp w800; body 11.5sp: "EDA is a 30-second measurement taken on the watch. Swipe to the EDA screen and touch the electrodes to record one."; tonal teal button `help` + "How to measure".
- "RECENT SPOT CHECKS" card with right-aligned "2 THIS WEEK"; rows show relative day + interpretation.
- Rule: **never fabricate a daily EDA aggregate** — when count = 0 show this state; when count is low (1–2) show the same layout as 1e with the literal count.

### 1f — Live ECG streaming
- Header: "Live signals" 22sp + green pill (7 dot + "CONNECTED · 78%").
- Signal chips: ECG (active, amber, with 16 icon) / PPG / GSR / ACCEL.
- **Waveform card**: bg `#080B0D`, border `rgba(255,255,255,.07)`, radius 20; plot 348×168 with faint amber grid (17.4×16.8 cells, `rgba(245,158,11,.08)`); ECG trace amber 2.2px round joins; **monitor-style sweep**: write head = 1.6px amber vertical line at 55% opacity with a 16px erase gap ahead (repaint only the head column region per frame — same technique as the watch). Footer: "LEAD I" + mono "25 mm/s · 128 SPS · 12-bit".
- Live stat cards: HR 72 (heart icon) · RR-INT 833 MS · LEADS ON (green dot).
- Filled amber button "Record 30 s to device" (`fiber_manual_record`); caption "Recordings are stored in device flash and sync automatically".
- "RECENT RECORDINGS" card: short (≤30 s) recordings with mono time/size + download icons. (Long recordings live in 2c.)

### 1g — Onboarding scan & pair
- No app/nav bars. "PROTOCENTRAL" Saira 12sp +2.5 ls `#6B7478`; "Set up your HealthyPi Move" 24sp w800; helper 13sp.
- Radar: 216 SVG — concentric circles r 104/78/52 in blue at .10/.16/.24 + 30 filled `rgba(111,179,204,.10)` center disc, `watch` 34 blue centered; found-device dots (amber 5, blue 4). Animate ring opacity pulse.
- Found device card: **amber border** `rgba(245,158,11,.35)`; 42 amber-tint circle `watch`; "HealthyPi Move" 14.5 w800 + mono "A4:C1:38:9F:2E:11 · −58 dBm" 10.5; filled amber "Pair" pill (h 38).
- DFU-mode device card at 55% opacity: `system_update` icon, "healthypi_dfu", mono "bootloader mode · −71 dBm", trailing "DFU".
- Footer: 3-step page indicator (active 20×6 amber bar) + "Can't find your device?" amber text button.

### 1h — Device page
- Header "Device" 22sp + settings icon button.
- Hero card: 76 watch mock (black circle, 5px `#2A333B` bezel, "2:14" Rubik 21 + "72 BPM" 7sp amber) · name 16sp w800 + "CONNECTED" green pill · mono "FW 1.4.2 · Zephyr · A4:C1:38:9F" · battery bar (blue, `battery_5_bar` icon, 78%) · storage bar (grey, `database`, 62%). Bars: 6 high, radius 3, track `rgba(255,255,255,.08)`.
- Sync card: `sync` amber, "Last synced 2 min ago" + "1,440 trend bins · 2 recordings"; tonal "Sync now"; divider; "Auto-sync trends hourly" + switch ON.
- Actions card: Firmware update (current 1.4.2, "v1.5.0 AVAILABLE" amber pill) · Set device time (Auto) · Watch preferences (Face · AOD · Units).
- Danger card: Erase device data (`delete`, `#F87171`) · Unpair watch (`link_off`).

### 1i — Settings + developer mode
- Pushed route (back arrow, no nav bar). Profile card (44 amber-tint avatar "AK", name + email).
- Section labels 10sp w800 +1.4 ls `#6B7478`: PREFERENCES (Units °F·mi / Theme Dark / Health alerts "High HR · Low SpO₂") · DATA (Export data "CSV · EDF" / Cloud sync "Off — local only") · DEVELOPER.
- **Developer card has a 1px amber border** (`rgba(245,158,11,.22)`): Developer mode toggle (amber switch, `code` icon amber); when ON, reveals rows: BLE console (trailing mono "GATT · LOG" amber) · Raw packet log (mono "12.4 kB/s") · Sample-rate config (mono "ECG 128 SPS"). When OFF, hide the three rows.
- Footer centered mono 10sp `#4A5359`: "App 2.1.0+87 · FW 1.4.2 · MIT licensed".

### 1j — BLE developer console
- Pushed route. App bar: back · "BLE console" · mono MAC chip.
- Link stats: 4 mini cards — MTU 247 / PHY 2M / RSSI −58 / B/S IN 12.4k (green) — mono 13sp values, 8.5sp labels.
- GATT card "GATT · HPI MOVE SERVICE": rows = mono char name in metric color (ECG_STREAM amber, PPG_STREAM blue, GSR_STREAM teal, TREND_SYNC grey) + mono UUID `#6B7478` + status chip (NOTIFY green tint / IDLE neutral / R/W).
- **Live log**: `#080B0D` bordered card, mono 10sp, line-height 1.9 — `[timestamp] TX/RX/OK/WARN message`; TX amber, RX blue, OK green, WARN `#F87171`, body `#6B7478`; blinking 7×13 amber block cursor. Autoscroll, ring buffer.
- Action row: "Dump flash" / "Export CSV" (neutral) · "Simulate" (amber tint) — 40 pills.

### ⚠ Long-term recordings — signal availability
**ECG has no long-term recording mode.** ECG is captured only as 30 s spot recordings from the Live tab (1f). Long-term sessions (30 min – 8 h) exist for **PPG, GSR, and IMU (6-axis accel + gyro)**. IMU sessions exist specifically for research correlation studies — exports share the `t_ms` timebase so accel/gyro can be aligned column-wise against PPG/GSR exports.

### 2c — Recordings library (long sessions, 30+ min)
- Header "Recordings" 22sp + search icon. Filter chips: "All · 5" (active) / PPG / GSR / IMU.
- **Active transfer card**: `downloading` amber, "Downloading 2 recordings from watch", "ECG Jul 9 · 14.2 of 20.8 MB · 41 s left", right "68%" Rubik amber, 6px amber progress bar.
- Session list card, rows: 38 metric-tint icon square · title 13.5 w800 · mono meta · status: **ON PHONE** (green tint pill + check → row opens 2d), **ON WATCH** (neutral pill + `download` action icon), or in-flight (% + `downloading`). Example sessions: IMU · 42 min (104 SPS · 6-axis, downloading), IMU · 2 h 05 min, PPG · 6 h 12 min (overnight, 64 SPS), PPG · 38 min, GSR · 45 min (32 SPS). IMU icon = `3d_rotation` on green tint.
- Footer note includes "ECG = 30 s spot recordings, see Live".
- Footer: `database` + "Watch flash 62% used · 2 recordings not yet downloaded" + "Download all" amber text button.
- Behavior: downloads resume on reconnect; deleting from watch prompts only after verified on-phone copy.

### 2d — Recording preview + CSV export (IMU example)
- App bar: back · "IMU · 42 min" 16sp + mono meta "Jul 9 · 9:14 PM · 104 SPS · accel ±8 g + gyro ±500 dps · 20.8 MB" · `delete`.
- **Full-session minimap** card: amplitude envelope (amber 30% fill polygon, 336×44) + **zoom-window rect** (amber 1.4px stroke, 12% fill, radius 6) draggable across the session; mono time ruler 0:00→42:00; header right "9:14 PM → 9:56 PM".
- **Detail waveform** card (no sweep — static pan/zoom): renders the windowed segment. For IMU: three overlaid axis traces — AX amber `#F59E0B`, AY blue `#6FB3CC`, AZ teal `#2FBDA8`, 1.8px, with mono axis legend; neutral grid `rgba(255,255,255,.05)`. For PPG/GSR previews: single trace in the metric color. Footer mono time range + `zoom_out`/`zoom_in` 30 circle buttons. Pinch-zoom + horizontal drag; window rect stays in sync with the minimap.
- Session stat cards (per signal type; IMU shown): PEAK G 2.4 (amber) · CADENCE 112 SPM · GYRO 214 °/S · PKT LOSS 0.2% (green).
- **Filled amber "Export CSV · 20.8 MB"** (download icon); secondary 40-pill row: EDF · Share · Raw hex.
- Caption: "CSV: t_ms, ax_g, ay_g, az_g, gx_dps, gy_dps, gz_dps · align by t_ms with PPG/GSR exports for correlation". Per-signal CSV schemas: IMU `t_ms, ax_g, ay_g, az_g, gx_dps, gy_dps, gz_dps`; PPG `t_ms, ppg_ir, ppg_red, spo2_pct`; GSR `t_ms, gsr_uS, contact`; ECG spot recordings `t_ms, ecg_uV, lead_state`. All share the `t_ms` timebase for cross-signal correlation. Export runs in an isolate with a progress snackbar; share via `share_plus`.

### 3a — Heart rate detail v2 (adds HRV to 1d)
Same app bar, segmented control, hero, and candlestick chart as 1d (hero at 34sp). Insert an **HRV · TODAY card** after the chart (screen scrolls; 1d's stat chips + baseline card follow below):
- Header: "HRV · TODAY" label + right "RMSSD 42 MS" 11sp w800 indigo `#8B84F0`.
- **Poincaré plot** 150×150: bg `rgba(255,255,255,.03)` radius 10; identity diagonal dashed `rgba(255,255,255,.14)`; scatter of RR(n) vs RR(n+1) points — 4.5px round dots, indigo at 85% opacity (~50 beat pairs, axis range 700–960 ms); **SD1/SD2 ellipse** rotated −45°, stroke `rgba(139,132,240,.45)` 1.4px (rx=SD2 scaled, ry=SD1 scaled); mono corner labels "700"/"960"/"RRn+1" 8sp.
- Right column of 3 metric chips (`rgba(255,255,255,.05)` radius 14): SDNN 51 MS (indigo), PNN50 18% (indigo), NIGHT AVG 46 MS.
- Footer row: green tint pill `trending_up` "+4 MS VS 30-DAY" + caption "Poincaré: RRn vs RRn+1 · SD1 17 · SD2 44 · from tonight's beat-to-beat intervals".
- Data: RR intervals come from overnight PPG beat detection; RMSSD/SDNN/pNN50 computed on-phone; night avg vs 30-day HRV baseline.

### 3b — Steps & activity detail
- Segmented Day/Week/Month/6M (active segment uses **green** tint `rgba(46,184,101,.2)` / `#2EB865`).
- Hero: "8,432" 34sp Rubik green + "steps" + right "84% of 10,000 goal".
- "TODAY · STEPS PER HOUR" card: 24 hourly bars (stroke 8 round caps, green .9, same x-geometry as 1d candles), baseline hairline, x labels 12A/12P/11P.
- Stat chips: MILES 3.9 / KCAL 412 / ACTIVE MIN 38 (green) / DAYS AT GOAL 5.
- "THIS WEEK" card: 7 thick bars (stroke 22 round caps, green .85) + **dashed goal line at 10k** with "10k" label; right header "avg 8,790 / day"; day labels FRI/MON/THU.

### 3c — SpO₂ detail (night focus)
- No segmented control — SpO₂ is nightly. Hero: "98%" 34sp Rubik blue + "avg last night" + right "measured during sleep · 6:38 AM".
- "LAST NIGHT · 10:52 PM – 6:38 AM" card, right header "2 dips" in `#F87171`: curve (blue 2.2px, y-scale 90–100% with gridlines/labels at 100/95/90), dashed blue baseline at 97, **dip events < 95% as 7px `#F87171` dots on the curve**; x labels 11PM/3AM/6AM. Legend: SpO₂ / Dip below 95% / Baseline 97. Chart svg is 366 wide with plot 336 + right-side labels (x=342).
- Stat chips: MIN 94 (red) / AVG 98 (blue) / MAX 100 / BELOW 90% 0 min (green).
- "LAST 7 NIGHTS · AVG" card: line + 7px dots, blue; right header "steady" green.
- Footer caption: "SpO₂ is sampled every 5 min while you sleep · single readings on the watch anytime".

### 3d — Wrist temperature detail (deviation focus)
- Hero: "97.9°F" 34sp + coral tint pill `trending_up` "+0.3° VS BASELINE" + right "last night".
- "NIGHTLY DEVIATION VS 30-DAY BASELINE" card (the primary chart — absolute wrist temp is less meaningful than deviation): 7 lollipop bars (stroke 10 round caps) around a dashed 0° midline — above baseline **coral** `#F0845C`, below **blue** `#6FB3CC`; scale 88px/°F; right header "3 nights elevated" coral. Legend: Above/Below baseline.
- Stat chips: TONIGHT 97.9 (coral) / BASELINE 97.6 / TYPICAL ±0.2.
- "LAST 30 NIGHTS" card: coral trend polyline over a neutral **typical-range band** (97.4–97.8°F, `rgba(255,255,255,.05)` rect); right header "trending up this week" coral; caption explains the band + "measured during sleep only".
- Baseline = 30-day rolling median of nightly averages; units follow the °F/°C setting.

## Interactions & behavior
- Navigation: `NavigationBar` with 4 tabs; trend details, settings, console, and recording preview are pushed routes with back arrows. Trends tab hosts a hub listing all metrics (not mocked — reuse 2a's list rows).
- Home layout switcher animates between list (2a) and grid (1a) layouts; persist in shared prefs.
- Charts animate in once (ring fills / bar grow, 1 s, standard easing); no continuous animation except the live ECG sweep and pulsing scan rings.
- Sync: pull-to-refresh on Home triggers trend-bin sync; footer line always shows last-sync age and bin count.
- All timestamps relative under 24 h ("2 m ago"), absolute after.
- Empty/zero states: EDA per 2b; first-run home shows placeholders with "Sync your watch" CTA (not mocked).
- Touch targets ≥ 44; text on `#0E1114`/`#161B20` uses the ramp above (all pairs ≥ 4.5:1 except decorative captions).

## Adaptive layout — tablet / expanded widths (turn 4: 4a, 4b)
The phone screens are the compact layout. On M3 window-size classes **medium/expanded (≥840 dp)** — iPads, large tablets, desktop — the same widgets reflow (reference frame: iPad landscape **1194×834**):
- **NavigationRail replaces NavigationBar**: 84 dp rail on the left, bg `#12161A`, right hairline; round amber-tint watch avatar at top; same 4 destinations stacked (52×30 active pill, 10.5sp labels); battery status pinned at the bottom. Switch on width class: `NavigationBar` <600 dp, `NavigationRail` ≥840 dp.
- **Home = list-detail two-pane (4a)**: left pane 432 dp (hero HR card at 38sp + the 2a signal list; selected row highlighted with `rgba(245,158,11,.08)` bg, radius 14, supporting text "selected"); right pane shows the selected metric's full trend detail in place (no pushed route) — header row = metric icon + title + Day/Week/Month/6M segmented control + share. Charts widen: candlesticks respan ~540 units (bar stroke 10), deviation chart respans with the same geometry rules.
- **Live = dual-signal research view (4b)**: two channels streamed simultaneously on a shared timebase — ECG card (amber grid + trace, sweep write-head) stacked above IMU accel card (AX/AY/AZ overlaid, green sweep), both full width (~1030 units); per-channel toggle chips in the header (ECG + ACCEL active simultaneously); stat cards + Record button in one bottom row; caption notes t_ms alignment for correlation.
- Trends hub, Recordings, and Dev console follow the same list-detail pattern (library left / preview right; GATT table left / log right). Device and Settings stay single-column, max-width ~640, centered.
- Screenshots: `4a-tablet-home-two-pane.png`, `4b-tablet-live-dual-signal.png` (captured at 68% scale).

## State management & data pipeline (rewrite assumptions)
- Watch stores **hourly trend bins** `{metric, hour, min, max, median, samples}`; app syncs bins over BLE (TREND_SYNC char) and persists locally (drift/sqflite).
- Derived on-phone after each sync: **30-day baselines** (rolling p25–p75 per metric), **stress index** (0–100, continuous, from HRV + SCR rate), **recovery score** (HRV + sleeping HR + temp deviation — exploration 1b only), **weekly rollups** (p25/p75/median).
- EDA spot checks and BP readings are discrete events, listed with timestamps — never averaged into a fake daily value.
- Long recordings: metadata index synced first; payloads downloaded on demand or via "Download all"; state per session = onWatch / downloading(pct) / onPhone.
- Developer mode flag gates the DEVELOPER settings section and console route.

## Assets
- **No image assets required.** All icons are Material Symbols Outlined glyphs (`material_symbols_icons` Flutter package). Icon names used: home, monitoring, ecg_heart, watch, favorite, steps, spo2, device_thermostat, self_improvement, water_drop, insights, chevron_right, arrow_back, calendar_month, ios_share, sync, system_update, schedule, tune, delete, link_off, settings, search, download, downloading, database, battery_5_bar, check, code, terminal, receipt_long, straighten, dark_mode, notifications, cloud_off, fiber_manual_record, play_arrow, grid_view, view_list, zoom_in, zoom_out, help, description, trending_up, 3d_rotation.
- Fonts via `google_fonts`: **Rubik** (w500), **Manrope** (w400–800), **JetBrains Mono** (w400–600), **Saira** (w700, onboarding wordmark only).
- ProtoCentral round logo (onboarding/about, optional): `assets/logo-round.png` in the ProtoCentral design-system project.

## Screenshots
`screenshots/` contains a reference PNG per screen, named `<id>-<name>.png` (e.g. `3a-trend-hr-hrv-poincare.png`, `2c-recordings-library.png`). They are captured from the HTML canvas at 1× and include the presentation bezel — use them for visual reference; measurements come from this README.

## Files
- `HealthyPi Move App Redesign.dc.html` — the full canvas; open in a browser. Turn 3 (top) = trend details HR+HRV/Steps/SpO₂/Temp; Turn 2 = combined home, EDA zero-state, recordings library + preview (IMU); Turn 1 = home explorations and all other approved screens. Option ids (1a…3d) appear as badges next to each phone.
- `support.js` — prototype runtime (ignore).
- `android-frame.jsx` — Pixel bezel used for presentation (ignore; not part of the app UI).
