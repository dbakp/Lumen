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

Direct Apple Health ZIP imports and standalone export.xml are supported after Batch 6. Supported categories, sizes and aggregation heuristics are in IMPORT_FORMATS.md. Clinical-record extraction is text/PDF-based, not diagnostic interpretation or a complete FHIR/EHR integration.

## Final native review fixes

The reviewer scored supplied native core-flow fidelity 4/5. Final pass fixed distinct 44pt symptom action targets, saved-response links that open the existing plan/document instead of inviting duplicate saves, and full stroke clearance around the signal arc. Numbered plan actions take precedence over contextual evidence bullets. The complete smoke scenario passed again on this final source, zero failures. That pass verified the foundation before the follow-through batches below.

## Follow-through batches · 29 October 2026

Batch 1 adds consent-controlled personal context, dated editable checklist actions, plan lifecycle states and an agenda. Batch 2 adds persistent conversations with migration and safe reply routing. Batch 3 adds completed-day trend comparisons, source/coverage details and local appointment summaries, and removes silent historical-log truncation.

The actual Swift logic suite now passes **48 checks**, including legacy plan/conversation decoding, sharing consent, scheduling, cross-conversation replies, sparse-period handling, zero baselines and older unresolved symptoms in reports. All application targets build. The expanded native scenario passed with **zero failures in 168.984 seconds**, covering personal-context editing, a dated plan step, reopening the original conversation, insights, appointment-summary creation and the original daily/persistence flows. Result bundle: `/tmp/LumenBatchesFinal.xcresult`; native screenshots: `Design/native/batches`.

GitHub access was resolved by authenticating as `dbakp`. GitHub accepted all four queued commits individually on 29 October 2026, advancing remote `main` to `54578fb`. The publishing script rejects a dirty tree or divergent remote and never force-pushes.

The final native review fixed block-level document rendering, repeated empty metric cards, duplicated plan instructions, link affordances and singular/plural copy. Editor and agenda screenshots are now included. The final expanded scenario passed again after these changes; this is the source being committed in Batch 3.


## Batch 4 · backup and restore

The standalone suite passes **68 checks**, including versioned backup round-trip, photo bytes, conflict merging, repeated-restore idempotency, consent reset, future versions, corrupt payloads, unsafe names, duplicate IDs, numeric/birth-year overflow, failed staging and interrupted-install recovery. All native targets build. The final reviewed iPhone scenario passed with **zero failures in 224.047 seconds**, including create → preview → restore → relaunch with a single retained plan. Result: `/tmp/LumenBackupReviewed.xcresult`; captures: `Design/native/backup`. Final source includes bounded JPEG dimensions and indexed day merging. Actual Files/iCloud transfer and restoration on a second signed device remain unverified.

## Batch 5 · cancellable health imports

The standalone suite passes **74 checks**. New checks cover actual reviewed-record counts and deterministic cancellation during XML, CSV and JSON parsing, pre-cancelled operations and CSV tokenization. All native targets build. The final native Files-picker scenario passed with **zero failures in 85.097 seconds** (`/tmp/LumenImportsReviewed.xcresult`): cancelled a 37 MB synthetic XML import, verified empty import history, dismissed a second picker without an alert, imported a small synthetic CSV after preview, and verified the receipt after relaunch. Captures: `Design/native/imports`.

The independent design review found Cancel obscured by the tab bar and singular/plural errors. Cancel now stays in the navigation toolbar, progress is compact, and preview/history say “1 day.” The final reviewer confirmed both fixes and scored progress/cancel usability, preview clarity and native fidelity 4/5, with no remaining high-impact visible findings. Earlier integration attempts corrected cold Files-service timing, icon selection and an offscreen assertion in the test. The file-backed test skips when simulator fixtures are absent; the parser suite always runs. No physical-device, iCloud-transfer or 500 MB performance claim is inferred from this scenario.

## Batch 6 · direct Apple Health ZIP imports

The actual Swift package checks pass **106 checks**, including ZIP/XML parity, retained sources, stored/Deflate and standard ZIP64 layouts, corrupt payload CRCs, unsupported/encrypted/ambiguous/unsafe archives, declared and actual expansion bounds, directory/count/offset bounds, original-file immutability, cancellation, temporary cleanup and interrupted-session cleanup. The check executable compiles the same import and model source used by the iPhone app and pins ZIPFoundation 0.9.20.

The final combined native suite passed **3 scenarios, zero failures, zero skips, 483.552 seconds**. ZIP: 120.220 seconds; cancellable XML/CSV: 125.104 seconds; full daily flow with backups: 238.229 seconds. Result bundle: `/tmp/LumenZIPFinal.xcresult`. It covers selecting a corrupt ZIP and recovering, valid ZIP preview with visible scope disclosure, discarding before commit, confirmed import, receipt persistence after relaunch, bundled license rendering, cancellation and picker reopening, and the existing journal/chat/plan/backup paths. Captures: `Design/native/zip`.

An earlier run exposed an import reopen failure. Cancellation now keeps file selection disabled until the reader releases its stream and security scope. A later receipt assertion stopped on Today before reaching Connections; the recording showed it had not inspected persisted history. The final combined run passed the actual persistence checks after navigation. No earlier failed or skipped run is used as passing evidence.

The independent App Designer Pro reviewer requested a disclosure next to the ZIP import button because zero skipped measurements could otherwise imply every archived file was processed. The final screenshot clearly excludes clinical documents and workout routes and directs PDF/text records to Library. Final preview/error/native/license clarity: 4/5, with no remaining high-impact visible findings. Physical-device/iCloud transfer, accessibility scaling and 500 MB performance validation remain outstanding.

## Batch 7 · workouts and additional health signals

The production Swift logic executable passes **140 checks**. New coverage includes workout-only exports, paused/reported duration, legacy totals and direct workout statistics, explicit unit conversions, nested-statistic exclusion, missing/invalid energy, conflicting repeated statistics, additional activity types, impossible dates/durations, stable IDs, source reconciliation, manual-entry preservation, backup/local priority, optional-model migration, backup round trips, cancellation during workout parsing, six new discrete signals, XML versus portable percentage semantics and unitless BMI display.

All native targets build for the simulator (`/tmp/lumen-workout-final-build.log`). The final native suite passed **2 scenarios, zero failures, zero skips, 339.440 seconds**: daily journey with journal/chat/plans/backup restoration **227.123 seconds**, workout/vital ZIP import **112.317 seconds**. Result bundle: `/tmp/LumenWorkoutsFinal.xcresult`. The import scenario uses the real Files picker, reviews a synthetic workout plus six signals, imports twice, verifies one matching workout, opens source/duration/missing-energy details, relaunches and verifies filename provenance, then opens oxygen evidence with exact value/date and its recorded-day list. The fixture generator uses yesterday for this coverage scenario so it remains inside the selected comparison window. Earlier round-1 import run also passed; only final captures support the final copy/affordance claims.

Final captures: `Design/native/workouts/r2`. The first design review requested removal of dead chevrons, exact evidence value/date and a readable record list, plus unitless BMI. All changes were implemented before the final native run. The same critic reviewed all five final captures, confirmed the fixes and scored the affected lines 4/5, with no remaining high-impact visual defects. Large-history performance, signed physical iPhone behavior, additional source permission combinations and accessibility scaling remain device/release validation gates. Imported workout summaries do not replace whole-day activity measurements or write back to HealthKit. Live workout energy now remains unknown when HealthKit provides no energy statistic; real-device behavior of that source path is not inferred from simulator fixtures.

## Batch 8 · reviewable conversational logging

The complete production-logic executable passes **173 checks**. New checks cover explicit local water/workout/symptom/check-in drafts; negation, plans, questions and examples; unrelated amounts/durations; blank missing fields; invalid quantities/future times; literal AI evidence and supported kinds; rejected malformed/ungrounded output; explicit unit conversions; cleared invented volumes/diagnoses/locations/ratings; bounded deduplicated source context with confirmed-value priority; provenance backup round trips and legacy hydration decoding.

All native targets and simulator architectures build with the final implementation (`/tmp/lumen-chatlog-verified-build.log`). The final conversational scenario passed with **zero failures in 144.131 seconds** (`/tmp/LumenChatLogsContinuity.xcresult`): cancel initial drafts without logging, edit 250 ml to exactly 500 ml, attempt swipe dismissal of an edited draft and keep reviewing, attempt Close and keep reviewing, confirm water/workout/symptom/check-in individually, relaunch and inspect all four saved records, open original-message provenance, then ask the assistant about symptoms and verify it references the saved headache in the head at 5/10. This last response is explicitly labelled Built-in guide; external/on-device model inference is not implied.

The broader existing daily/Library/conversation/backup journey also passed separately in **252.272 seconds**. An intermediate combined run had one failing logging assertion: the iOS confirmation popover omitted its cancel-role button. Its captured screen showed only the discard action. Replaced it with an explicit two-choice alert; the revised dedicated logging scenario passed in 209.463 seconds, then its final continuity extension passed as above. No failed intermediate run is counted as a passing combined suite.

The same independent App Designer Pro reviewer scored the final eight review/edit/saved/provenance/dismissal captures at 4/5 on all affected lines, confirming persistent units, upfront saved/pending and closing behavior, protected edited drafts, empty optional notes and separate source provenance. No remaining high-impact visible findings. Reviewed captures: Design/native/chat-logs/r3; final test captures including assistant continuity: Design/native/chat-logs/r4. No product design changed between those captures.

Each save writes one local domain atomically before updating memory and checks the proposal's record ID before writing. Confirmed entries retain source text, source conversation/message IDs, preparation label and confirmation time. This logging flow does not write to HealthKit. Provider inference/cancellation, physical-device performance, denied source permissions and accessibility sizes remain separate gates. See CONVERSATIONAL_LOGGING.md for interaction, privacy and format details.
