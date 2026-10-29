# Health imports

Use Connections → Import health data. The preview reports dates, sources, supported samples and skipped samples; nothing is committed until Import is tapped. Data is parsed locally. Reimporting replaces metric/day values, never adds to them. Clear imported history from Connections; exports include it.

Apple Health: Health → profile → Export All Health Data. Unzip export.zip in Files, then choose apple_health_export/export.xml. XML is streamed. Supported: steps, active energy, exercise, resting HR, SDNN HRV, weight, water, energy and macros, asleep categories. Unsupported clinical records, workouts and categories are counted as skipped; workouts still sync through live HealthKit/Strava. Asleep intervals are unioned per source and assigned to their end day. For multiple sources on one day, the source with most samples wins (alphabetical tie-break), not a sum of overlapping devices. This is a conservative import heuristic, not HealthKit's proprietary source priority. Review the preview and provenance.

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

XML limit 500 MB; CSV/JSON limit 25 MB. Unsupported units are skipped rather than guessed. Imported historical data is available to the assistant and weekly coverage review. Today's import fills missing live values; live HealthKit totals take precedence. Missing logs never mean zero consumption.

Text, Markdown and text-based PDFs can be added as Library records. PDF extraction uses PDFKit locally; scanned PDFs require OCR before importing. Records are excluded from assistant context by default. Turn on “Use in assistant” to share excerpts with the selected AI provider; documents themselves are never treated as instructions. No direct Oura/Garmin OAuth is claimed: connect those apps to Apple Health or use a portable export.


## Progress and cancellation
XML, CSV and JSON imports show the number of raw records reviewed, including unsupported or duplicate records. Counts are observations, not a percentage or an estimate of time remaining. CSV first prepares its quoted fields; a large file can show zero reviewed records during that stage. Parsing and preview generation run off the main screen. Cancel discards partial results; closing the Connections screen also cancels the operation. No history is added until you explicitly confirm the preview. Opening another import after cancellation cannot resurrect the old preview. CSV/JSON use a 25 MB limit, while streamed XML supports up to 500 MB. ZIP extraction remains a separate step.

For native cancellation testing on a booted simulator, run `python3 scripts/seed-import-ui-fixtures.py <simulator-UUID>` before `LumenSmokeTests/testImportCancellation`. It creates a 37 MB synthetic XML file and a tiny synthetic CSV in that simulator’s Files provider. The fixture contains repeated test measurements and must never be used as a personal health history. Remove `Lumen-import-cancellation.xml` and `Lumen-import-small.csv` from the simulator’s Files app after testing. The parser suite also exercises deterministic cancellation while XML, CSV and JSON are being read, including CSV tokenization.

The native file-backed scenario is skipped when its fixtures are absent; the standalone parser checks always run. The full daily-loop smoke test is independent of those fixtures.
