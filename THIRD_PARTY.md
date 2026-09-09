# Third-Party Components

Components in this repository that are **not** original ProtoCentral work, or that
carry a licence other than MIT.

The app itself is MIT — see [`LICENSE`](LICENSE). **Every third-party component listed
below is OSI-approved free software; there are no proprietary dependencies, and no
analytics, advertising or tracking SDKs of any kind.**

For the firmware side of the project, see
[`THIRD_PARTY.md` in healthypi-move-fw](https://github.com/Protocentral/healthypi-move-fw/blob/main/THIRD_PARTY.md).

---

## Bundled fonts — SIL Open Font License 1.1

Redistributed in this repository under [`assets/fonts/`](assets/fonts/). Licence text:
[`assets/fonts/OFL.txt`](assets/fonts/OFL.txt).

| Typeface | Copyright | Upstream |
|---|---|---|
| JetBrains Mono | 2020 The JetBrains Mono Project Authors | https://github.com/JetBrains/JetBrainsMono |
| Manrope | 2019 The Manrope Project Authors | https://github.com/sharanda/manrope |
| Rubik | 2015 The Rubik Project Authors | https://github.com/googlefonts/rubik |
| Saira | 2020 The Saira Project Authors | https://github.com/Omnibus-Type/Saira |

Copyright lines are taken from each font's own `name` table (nameID 0), and each font
declares OFL 1.1 in nameID 13/14.

## Icon font — Apache-2.0

| Component | Copyright | Notes |
|---|---|---|
| Material Symbols Outlined | © Google LLC | Pulled in via the `material_symbols_icons` package, not vendored here |

## Dart and Flutter packages

Fetched from pub.dev at build time and not redistributed in this repository. Licences
verified against each package's own `LICENSE` file.

| Package | Licence |
|---|---|
| `path_provider`, `shared_preferences`, `file_selector`, `share_plus`, `package_info_plus` | BSD-3-Clause |
| `intl`, `http`, `json_annotation` | BSD-3-Clause |
| `universal_ble`, `flutter_archive` | BSD-3-Clause |
| `sqflite` | BSD-2-Clause |
| `csv`, `mcumgr_dart`, `upgrader` | MIT |
| `material_symbols_icons` | Apache-2.0 |

`healthypi_healthy_store` is ProtoCentral's own HPI_HS protocol client, MIT, maintained
at [Protocentral/healthy_store_dart](https://github.com/Protocentral/healthy_store_dart)
and pinned here to a tag.

## Watch firmware — downloaded, not distributed

The app can download and flash watch firmware from the
[healthypi-move-fw](https://github.com/Protocentral/healthypi-move-fw) releases. Those
images are **not** contained in this repository or in the app binary.

That firmware is MIT overall, but it is not wholly OSI-approved: it includes four
`LicenseRef-Nordic-5-Clause` files and, on the nRF5340, a Nordic-supplied net-core BLE
controller binary. Nordic's licence permits redistribution only for use with Nordic
Semiconductor devices — which is what the watch is. See that repository's
`THIRD_PARTY.md` for the file-by-file breakdown.

The proprietary Analog Devices MAX32664C/D sensor-hub images (`.msbl`) are **not**
distributed by either repository, and this app contains no code that handles them.
