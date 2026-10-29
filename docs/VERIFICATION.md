# Verification · 29 October 2026

## Build

All five scheme targets compile with Xcode 27.1: iPhone, iPhone widget, Watch, Watch widget and UI tests. Generic simulator build and build-for-testing passed. Latest native flow run is tracked below. iOS 18 remains the deployment target; newer model APIs are availability-checked.

## Automated logic checks

`scripts/test-imports.sh`: **28 checks passed**, exercising the actual Swift sources, including:

- XML, CSV and JSON parsing, supported-unit conversions, quoted commas/newlines/quotes.
- Duplicate records, invalid/future dates, nonfinite/negative values and unsupported units.
- Overlapping asleep intervals unioned without in-bed double-counting.
- One-source-per-metric/day handling rather than summing two devices.
- Symptom model coding and preservation of description/severity.
- Overnight, daytime and all-day quiet-hour boundaries.
- External nutrition/water combined with local logs exactly once; legacy snapshots and imported totals reconciled conservatively.
- Historical averages report recorded-day coverage rather than treating gaps as zero.
- Explicit/negated/incidental planning intent and extraction of actual action items into checklist steps.

## Native integration

Device: iPhone 18 Pro, iOS 27.0 simulator. Tests use a fresh local profile and deliberately entered test logs; production never seeds fictional health data.

Earlier passes verified onboarding, water logging, symptom saving, reactive Today, Journal and check-in persistence, and the built-in assistant reply. They exposed two fixed defects: a preferences-store initialization cycle, and unsupported FoundationModels inference on the simulator despite reported availability. The simulator now selects the labelled built-in guide unless an external key was deliberately configured. Physical-device provider availability remains runtime-selected.

A subsequent run exposed a navigation/accessibility issue: the chat keyboard obscured the Library tab and the test relied on a static-text child inside a navigation link. Sending now dismisses the keyboard; document links have explicit accessible names and identifiers.

**Final end-to-end run: PASSED**, 1 smoke scenario, zero failures, 129.111 seconds. Result bundle: `/tmp/LumenReleaseReview.xcresult`. It covers onboarding, water/symptoms/check-ins, contextual Today, assistant-to-Library plan creation, completing a plan step, writing a note, resolving a symptom, retained Sleep/Activity/Food destinations, and persistence after app relaunch. Final screenshots are in Design/native/final. The run also compiled the final source and icon assets.

## Design verification

Three concepts rendered; daylight observatory selected. App Designer Pro scans on the final new-design set at standard and small-phone sizes: zero FAILs. Every remaining warning is addressed in Design/CRITIQUE.md. The reconstructed historical before screen is deliberately audited separately and is not an original native screenshot.

One independent critic performed three rounds and the final reel check: 11/13 applicable lines at 4 or above, none below 3. Richness and preview motion remain 3/5; no portfolio-level score is claimed. Hero text contrast was corrected and rechecked from a decoded video frame. MP4 previews decode to 8 seconds each. Frame endpoints match visually (living: exact; hero: one channel of one pixel difference). Previews are 12 fps and do not establish real-device motion quality.

## Physical-device and service checks still required

Health permissions and writes (including partial/denied reads), camera, real Apple/optional OpenAI inference, Strava OAuth, actual notification delivery, Face ID, haptics, Watch connectivity and Home Screen widgets. These depend on the user's device, selected providers and permissions; they cannot be established by a local simulator build. Notifications refresh when Lumen runs and cannot continuously re-evaluate changes made elsewhere while suspended.

Imports require unzipping Apple Health's export before selecting export.xml. Supported categories, sizes and aggregation heuristics are in IMPORT_FORMATS.md. Clinical-record extraction is text/PDF-based, not diagnostic interpretation or a complete FHIR/EHR integration.

## Final native review fixes

The reviewer scored supplied native core-flow fidelity 4/5. Final pass fixed distinct 44pt symptom action targets, saved-response links that open the existing plan/document instead of inviting duplicate saves, and full stroke clearance around the signal arc. Numbered plan actions take precedence over contextual evidence bullets. The complete smoke scenario passed again on this final source, zero failures. That pass verified the foundation before the follow-through batches below.

## Follow-through batches · 29 October 2026

Batch 1 adds consent-controlled personal context, dated editable checklist actions, plan lifecycle states and an agenda. Batch 2 adds persistent conversations with migration and safe reply routing. Batch 3 adds completed-day trend comparisons, source/coverage details and local appointment summaries, and removes silent historical-log truncation.

The actual Swift logic suite now passes **48 checks**, including legacy plan/conversation decoding, sharing consent, scheduling, cross-conversation replies, sparse-period handling, zero baselines and older unresolved symptoms in reports. All application targets build. The expanded native scenario passed with **zero failures in 168.984 seconds**, covering personal-context editing, a dated plan step, reopening the original conversation, insights, appointment-summary creation and the original daily/persistence flows. Result bundle: `/tmp/LumenBatchesFinal.xcresult`; native screenshots: `Design/native/batches`.

GitHub publishing is blocked by external repository permissions: the only configured GitHub account is `dbakp-askcody`, and GitHub reports `push:false` for `dbakp/Lumen`. The first push returned HTTP 403. No batch is claimed as published. Each batch is kept in its own local commit; `scripts/publish-batches.sh` can push them individually after access is corrected. It rejects a dirty tree or divergent remote and never force-pushes.

The final native review fixed block-level document rendering, repeated empty metric cards, duplicated plan instructions, link affordances and singular/plural copy. Editor and agenda screenshots are now included. The final expanded scenario passed again after these changes; this is the source being committed in Batch 3.
