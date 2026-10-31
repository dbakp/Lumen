# Health imports

Use Connections → Import health data. The preview reports dates, sources, supported samples and skipped samples; nothing is committed until Import is tapped. Data is parsed locally. Reimporting replaces metric/day values, never adds to them. Clear imported history from Connections; exports include it.

Apple Health: Health → profile → Export All Health Data. Choose export.zip directly, or choose apple_health_export/export.xml if you already extracted it. ZIP import reads one regular export.xml entry, then streams its XML. Other archived files, including route GPX and clinical CDA files, are not imported. Supported: steps, active energy, exercise, resting HR, SDNN HRV, weight, water, energy and macros, asleep categories. Unsupported XML Record categories are counted as skipped. Workout summaries and six additional signals are supported as described below. Clinical documents and routes remain excluded. Asleep intervals are unioned per source and assigned to their end day. For multiple sources on one day, the source with most samples wins (alphabetical tie-break), not a sum of overlapping devices. This is a conservative import heuristic, not HealthKit's proprietary source priority. Review the preview and provenance.

Portable CSV (UTF-8, optional source column; quoted fields supported):

```csv
date,metric,value,unit,source
2026-10-28,steps,8421,count,Watch export
2026-10-28,sleep,7.4,h,Watch export
2026-10-28,hrv,48,ms,Watch export
```

JSON uses the same fields in an array:

```json
[{"date":"2026-10-28","metric":"water","value":1750,"unit":"ml","source":"My export"}]
```

Dates are YYYY-MM-DD or ISO 8601 with timezone. Canonical units: steps/count, activeEnergy/kcal, exercise/min, sleep/h, restingHR/bpm, hrv/ms, weight/kg, water/ml, calories/kcal, protein/g, carbs/g, fat/g. Conversions: water L; weight lb or g; HR count/min; HRV s; sleep min or s; energy kJ. Nonfinite/negative/future measurements and implausible bounds are skipped. Duplicate source/type/start/end/value records are ignored. CSV/JSON records are samples, so multiple distinct same-day values sum for cumulative metrics, average for heart signals, and take the latest weight. Export one daily row per metric if providing daily totals.

ZIP and expanded XML limits 500 MB each; CSV/JSON limit 25 MB. Unsupported units are skipped rather than guessed. Imported historical data is available to the assistant and weekly coverage review. Today's import fills missing live values; live HealthKit totals take precedence. Missing logs never mean zero consumption.

PDFs (including scans), still JPEG/PNG/HEIC images, UTF-8 text and Markdown can be added as Library records. On-device PDFKit/Vision reading retains page versions for comparison and correction before explicit review and saving. Bounds: 20 MB, 100 pages and 200,000 characters; locked PDFs need unlocking and forms need flattening. Save retains reviewed text and provenance, not the original file. Keep the original separately. Records are excluded from assistant context by default. Turn on “Use in assistant” to share excerpts with the selected AI provider; documents themselves are never treated as instructions. See [Record import](RECORD_IMPORT.md) for exact behavior and limits. No direct Oura/Garmin OAuth is claimed: connect those apps to Apple Health or use a portable export.


## Progress and cancellation
ZIP, XML, CSV and JSON imports show the number of raw records reviewed, including unsupported or duplicate records. Counts are observations, not a percentage or an estimate of time remaining. CSV first prepares its quoted fields; a large file can show zero reviewed records during that stage. Parsing and preview generation run off the main screen. Cancel discards partial results; closing the Connections screen also cancels the operation. No history is added until you explicitly confirm the preview. Opening another import after cancellation cannot resurrect the old preview. CSV/JSON use a 25 MB limit, while streamed XML supports up to 500 MB. ZIP imports first show opening/preparation progress in bytes, followed by reviewed-record counts. Cancel import stays available in the navigation bar throughout.

For native cancellation testing on a booted simulator, run `python3 scripts/seed-import-ui-fixtures.py <simulator-UUID>` before `LumenSmokeTests/testImportCancellation` or `LumenSmokeTests/testAppleHealthZIP`. It creates a 37 MB synthetic XML, a tiny synthetic CSV and valid/corrupt synthetic ZIPs in that simulator’s Files provider. The fixture contains repeated test measurements and must never be used as a personal health history. Remove `Lumen-import-cancellation.xml`, `Lumen-import-small.csv`, `Lumen-health-export.zip` and `Lumen-health-invalid.zip` from the simulator’s Files app after testing. The parser suite also exercises deterministic cancellation while XML, CSV and JSON are being read, including CSV tokenization.

The native file-backed scenario is skipped when its fixtures are absent; the standalone parser checks always run. The full daily-loop smoke test is independent of those fixtures.

## ZIP handling

Imports accept stored/Deflate entries and bounded standard ZIP64 metadata. A ZIP must contain exactly one regular file named export.xml (root or a folder). Encrypted, multipart, ambiguous, unsafe-path or symbolic-link archives are rejected. Directory metadata is limited to 32 MB and 100,000 entries. The selected XML has a declared and actual 500 MB ceiling, exact-size and CRC checks. Other entries are structurally checked but never extracted or given to the assistant; their payload CRCs are not checked. Unsupported archive layouts can still be imported by choosing export.xml directly.

The app copies the selected ZIP into a protected, bounded temporary snapshot, validates offsets before decompression, and extracts XML to a fixed filename. Validation/cancellation/parsing failures remove the temporary directory. Completed previews also remove it; process launch clears interrupted imports. Original exports are never modified. Valid ZIP64 zero-offset fields are normalized only in the private copy to preserve compatibility with the pinned library. CRC is an integrity check, not proof of who created the archive.

Implementation references: [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/0.9.20) and the [PKWARE ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT). Dependency and license details are in THIRD_PARTY.md.

## Workouts and additional signals

Apple XML/ZIP imports also read workout summaries. Duration uses the source’s reported active duration, preserving pauses; if absent, elapsed time is used and disclosed in the workout detail. Legacy energy/distance attributes and direct workout-level statistics are supported. Nested activity statistics are not added to parent totals. Energy accepts kcal/kJ; distance m/km/mi; average heart rate bpm/count/min. Unsupported optional fields stay unknown and generate review notes. Clinical documents and route files remain excluded.

Preview shows workout count, matching sessions, source and any unreadable fields. Confirmed sessions appear in Activity and the Journal timeline, and the assistant receives the recent workout history. Tap a workout in Activity to inspect its source, filename, duration provenance and missing fields. Import never writes workouts back to Apple Health. Workout summaries do not replace whole-day exercise, step or active-energy totals; import those measurements as well when available. Clearing imported history removes exported workout copies, preserving manual entries and copies replaced by live synchronization.

Stable export IDs use activity type, source, start and end. Repeat imports update that copy. Distinct external sources reconcile only when kind, start (within 60 seconds) and duration (within 60 seconds or 3%) agree. Unknown activity types need matching raw types; manual entries are preserved. Ambiguous sessions can remain separate. Live copies take priority; restoring backups keeps local copies. Backup version 1 supports the new optional metadata and still reads older workout records.

Additional portable metric keys are `heartRate` (bpm), `respiratoryRate` (breaths/min), `spo2` (%), `vo2max` (ml/kg/min), `bodyFat` (%) and `bmi` (count). XML maps the corresponding HealthKit identifiers. Heart rate, breathing rate, oxygen saturation, VO₂ max, body fat and BMI use the arithmetic mean of samples from the selected daily source. This is not a time-weighted continuous reading. Weight retains its latest daily reading. Insights exposes recorded-day comparisons, sources and explanatory notes; percentage differences use percentage points.

**Percentage units are format-specific:** HealthKit XML `%` values are fractions (0.98 → 98%). Portable CSV/JSON `%` values are display percentages (98 → 98%); use `fraction` for fractions (0.98 → 98%). XML fraction values outside 0–1 are skipped rather than guessed. Respiratory `count/s` converts to breaths/min; VO₂ max accepts explicit `ml/(kg*min)` and the documented portable unit. Unsupported units are skipped. No clinical meaning is inferred from a measurement or its change.

Primary references: [Apple percent unit](https://developer.apple.com/documentation/healthkit/hkunit/percent()), [oxygen saturation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/oxygensaturation), [body fat percentage](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodyfatpercentage), [workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration), and [workout statistics](https://developer.apple.com/videos/play/wwdc2022/10005/). The installed HealthKit SDK headers define compatible quantity units. These references describe units and data structures, not validation of any device reading.

## Earlier Lumen readable exports

Files made with **Export my data** use a different format from the portable metric arrays above. In Settings → Backup & restore, choose **Recover a readable export** for category/record review and explicit confirmation. Photo files and cached totals are not recovered. See [Readable exports](READABLE_EXPORT.md) for supported sections, optional setting replacement and limits.

## Reviewed FHIR lab files

Library's separate FHIR import accepts local FHIR R4 `.json` resources/Bundles and `.ndjson` files containing one complete resource per physical LF/CRLF line, with one top-level resource type per file. The whole input is limited to2MB,1,024 resources including contained resources,64 nesting levels and100,000 JSON nodes. NDJSON permits an initial UTF-8 BOM and a final line without a newline; blank/multiline/mixed-type/Bundle lines, bare carriage returns, duplicate keys and malformed lines reject the complete file. This is separate from the flat-table JSON and Apple Health routes; file extension selects the mode without fallback or format guessing.

Coverage, person selection, correction/exclusion, acknowledgement and checked saving precede a saved record. Original tokens, full-file byte ranges, exact-file SHA-256 and retained receipts remain separate from reviewed wording. NDJSON locations use `/line/N` with physical lines starting at1. Only the selected local file is read; companion files, manifest URLs, external references and attachments are not fetched. Sharing starts off. See [FHIR lab import](FHIR_LAB_IMPORT.md) and [NDJSON scope/current verification](FHIR_NDJSON_IMPORT.md). Batch25's scoped checks, source/build audit, current reader/compact flow and continuing design review pass at their documented boundaries; full bulk-export, profile and clinical validation remain open.
