# Readings, sources and corrections

Open **Readings** in Today's toolbar, or **Review today's readings** in Today, Activity or Insights. The overview covers sleep, movement, heart/body signals, food and water. Each detail shows what is available and the evidence saved with that reading.

**Not recorded** means no usable current reading is available. An explicitly returned or imported zero stays zero. Empty query results, an absent log and an old ambiguous cached zero do not establish a recorded zero. Small positive values are shown with decimals rather than rounded to zero in the readings overview and details.

## What the dates mean

| Source | Evidence shown | Precision limit |
|---|---|---|
| Current Apple Health quantity | Returned source when available, today's query period and check outcome/time | Totals and averages do not have a proven latest sample time. A latest-value query retains its actual sample time. |
| Apple Health stand/roll category | Unique qualifying clock hours in today's returned records, query period and check time | Standing duration is a different measurement. Old duration-based cached values are discarded. |
| Health import | Source and reported calendar day | The current imported-day model does not retain individual sample timestamps. |
| Lumen water, meal or workout logs | Local source, contribution period, last log time and estimate status | Logs may cover only part of the day. Meal nutrients and calculated manual-workout energy can be estimates. |
| Saved sleep history | Saved source, actual episode start/wake time, measured asleep time or estimated time in bed | A saved episode does not establish a new Health query time. |
| Legacy daily cache | Dated daily total with source/check time explicitly unavailable | Undated discrete weight, heart and fitness readings are not reused as today's observations. |

Completing the Health access sheet does not establish permission to read every type. **Access requested** and per-type checks describe what happened without claiming blanket access. An empty read can mean no data or no access. A failed refresh can retain an already dated current reading while displaying the failed check; a successful empty refresh clears the old reading. A later explicit local weight reading is retained over an older or empty refresh.

Stand/roll hours use HealthKit's category records, counting each clock hour once. They are distinct from cumulative standing duration. See Apple's [stand-hour category](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifierapplestandhour) and [standing duration](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applestandtime). A real device is still needed to verify source coverage, permission changes and wheelchair behavior.

## Combining sources

The resolver works per metric. A live returned zero wins over an overlapping import. Missing live types can independently use a dated import. New Health food/water queries exclude Lumen's own writes, so local logs can be added once; older inclusive snapshots and imported totals use the larger available contribution when overlap is uncertain. The detail discloses this choice. Locally managed workouts are separate from external sessions. Their known energy contributes to activity; blank energy is not inferred from duration. An old workout with zero calories and no presence metadata remains ambiguous; positive legacy energy remains available.

Weekly energy charts plot only days containing known workout energy. A recorded zero remains a point; other days stay empty. Historical Insights is rebuilt from the current local records and independent source days. Moving a correction to another date moves its contribution. Deleting a local record does not delete an external reading. Seven-day workout counts are counts of available records, not proof of physical inactivity.

## Assistant context

Current observations use the same resolver as the readings screens. Missing intake is unknown, profile targets are separate estimates, and old measurements are not called current. Query and sample times stay separate. A sleep-debt estimate requires an unambiguous 14-night calendar window; missing nights are not filled with zero debt. Readiness remains an unvalidated wellness heuristic. Its missing sleep-debt input is omitted, rather than called “well rested”.

Original conversation statements are reference material. Corrected structured values take priority, and deleted observations must not be recreated from older wording. This is a prompt constraint and deterministic local behavior; it is not a guarantee about a live model's inference.

See [conversational logging](CONVERSATIONAL_LOGGING.md) for correction/deletion controls and [backup rules](BACKUPS.md) for restore behavior. Simulator evidence, pure production-logic checks and remaining signed-device/provider gates are recorded in [Verification](VERIFICATION.md).
