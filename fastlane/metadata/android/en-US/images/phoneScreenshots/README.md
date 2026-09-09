Store screenshots, in display order. F-Droid and IzzyOnDroid both read this
directory and sort by filename, so the numbering *is* the running order.

| File | Screen |
|---|---|
| `1.png` | Home dashboard — HR sparkline plus the metric list |
| `2.png` | Trends hub — every metric with freshness, and the derived/spot grouping |
| `3.png` | Heart rate detail — Day, hourly min-max |
| `4.png` | Heart rate detail — Week |
| `5.png` | SpO₂ detail |
| `6.png` | Wrist temperature detail |
| `7.png` | Device — pairing, sync state, firmware, calibration |
| `8.png` | Firmware update |

All 828×1792 PNG, ~60-125 KB each. Deliberately not resized: F-Droid documents
no dimension or size limit and recompresses on ingest, so downscaling would
only lose fidelity. Verified to carry no embedded metadata.

Two things to know before regenerating them:

- **These were captured on iOS**, so the status bar and home indicator are
  Apple's. The app is the same on both platforms, but if a set is ever recaptured
  it should be from an Android device — this is an Android listing.
- Renumber the whole set when adding or removing one; a gap is harmless but a
  duplicate number is not.

Avoid showing real personal health data in anything captured here.
