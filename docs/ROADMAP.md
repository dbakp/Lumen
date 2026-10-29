# Lumen product gaps and delivery batches

Audit date: 29 October 2026. Scope: the actual native repository, not the screenshot preview.

## Delivery rules
Each batch is a separate conventional commit pushed to GitHub after relevant logic checks and a native build. Native integration tests cover the final combined flow. No fabricated integrations, clinical claims or app-store readiness claims. Existing local data must continue to decode.

## Batch 0 — publish the verified foundation
Contextual Today; symptoms and check-ins; local imports; AI/provider provenance; Library and plans; quiet reminders; light-first design and Watch/widgets. Previous work is local and must be committed before further changes.

## Batch 1 — personal context and plans
Missing: explicit long-term preferences/constraints, user control over assistant memory, editable checklist actions, dates, active/completed/archived plan states and a practical view of upcoming steps.
Deliver: local personal context editor (goals, food preferences, allergies, injuries/limitations and schedule), per-profile sharing consent; dated editable plan steps, progress/status and an upcoming-actions view. Context is supplied only when opted in. User-entered medical constraints are reference notes, not diagnoses. Completed/archived plans do not generate overdue pressure.

## Batch 2 — conversation continuity
Missing: conversation history, reopening/renaming/deleting past chats, and robust handling of a reply finishing after navigation or a new conversation.
Deliver: persisted conversations with migration of legacy chat; search/history/rename/delete; replies and saved plans tied to the originating conversation; one in-flight send with clear cancellation behavior; no lost or misattributed replies. External model availability still requires real-device/provider verification.

## Batch 3 — useful longitudinal insights and appointments
Missing: meaningful period comparisons using actual recorded coverage, a browsable insights destination, and appointment summaries with symptom details and relevant timeline context.
Deliver: current-versus-previous 7/30-day comparisons, source/coverage labels, clear minimum-data rules; local appointment summary document with symptoms, check-ins, activity and questions; save summaries to Library and share through existing document controls. Associations are not diagnoses or causal claims. Missing days are never treated as zero.

## Batch 4 — recoverable local history
Deliver versioned, restorable backups including meal photos; checksum and schema validation; preview with counts and conflicts; idempotent merges that preserve current records; optional profile/preferences restore with fresh sharing consent; staged installation and interrupted-write recovery. Retain readable exports as a separate format. No credentials, permissions or HealthKit write-back.

## Batch 5 — imports that stay responsive
Deliver real reviewed-record counts and cancellation for streamed XML and portable CSV/JSON; cancellation while tokenizing CSV and preparing the preview; discard partial results; prevent late previews after navigation/cancellation; distinguish portable-file size limits from XML limits. Validate parser behavior plus the actual native Files picker and Cancel control with synthetic data.

## Batch 6 — Apple Health ZIP import
Accept Apple's exported ZIP directly, locate and validate the health XML entry, extract only that entry to a temporary location with size limits, support cancellation, and reuse the existing source/date preview. Test corrupted archives, missing XML, path traversal, expansion limits and cancellation. No records are committed before review. This removes the current manual unzip step before progressing to device-dependent background synchronization.

## Batch 7 — broader export coverage
Add historical workout details and additional common vitals from Apple Health exports, with explicit unit rules, source/date provenance and preview counts. Preserve idempotent reimports and reconcile overlap with live sessions. Imported workouts must appear in the timeline and assistant history without being written back to HealthKit. Add coverage-based views for supported new signals without diagnostic interpretation. Verify optional-model migration and backup compatibility. Background synchronization and physical-device delivery remain subsequent gates.

## Remaining roadmap after these batches
1. Large-library backup improvements: encrypted archives, progress/cancellation, streaming or package format beyond the current 100 MB JSON limit; legacy-export conversion with a separate preview.
2. Background HealthKit observation/anchored synchronization, permission-aware freshness and delivery diagnostics, tested on a signed physical iPhone. Current refresh-on-open is not continuous monitoring.
3. Additional export categories beyond the completed workout/common-vital coverage, bounded-memory ingestion for very large histories, richer provenance, OCR for scanned records, and reviewable structured lab records. Keep unsupported formats explicit.
4. Direct provider connections only where official OAuth/API access is configured and tested. Existing HealthKit and Strava are not a substitute for pretending every device is connected.
5. User-reviewed conversational logging, voice input, structured AI-generated multiweek plans and explicit tool confirmations. The assistant currently advises; it does not silently modify every health log.
6. More complete data editing and reconciliation: HealthKit write failures, deletion confirmation/retry, source priority, import rollback, configurable retention and export units/timezones.
7. Device release validation: denied/partial HealthKit access, real model inference, notifications in the background, camera, Face ID, Watch offline/reconnect and widgets, accessibility text sizes, localization and energy/performance profiling.
8. Clinical/product governance before any diagnostic feature, medications guidance, lab interpretation or regulated claims. Keep wellness guidance distinct from medical assessment.
9. Distribution: signed builds, CI on a configured macOS runner, TestFlight, privacy/store disclosures and crash reporting with explicit data-minimization choices. No credentials or paid services are assumed.

## Completion log
Pending batch entries will record commit, validation and push outcome below.

### Batch 0
Commit `7737ebb` created. Foundation build passed and 28 logic checks passed. Push rejected by GitHub (403): active account `dbakp-askcody` lacks write permission on `dbakp/Lumen`. User notified; access was subsequently resolved and GitHub accepted this commit on 29 October 2026.

### Batch 1
Implemented personal context with explicit sharing consent, editable/datable checklist steps, plan states, and an agenda surfaced in Today and Library. Legacy step JSON still decodes. All targets build; 35 logic checks pass. Commit `f69f76e` published on 29 October 2026.

### Batch 2
Implemented persistent conversation history with legacy migration, search, reopening, rename, share and delete. Reply context is captured at send time; late replies stay in the originating conversation, and deleted conversations are not recreated. Sending is guarded immediately and can be stopped. All targets build; 39 logic checks pass. Commit `890af8d` published on 29 October 2026.

### Batch 3
Implemented completed-day 7/30-day evidence comparisons with coverage, source details and minimum-data rules; editable appointment summaries; native document headings/lists; clearer empty states and checklist-first plan details. Removed silent meal, water, workout and sleep-history truncation. All targets build, **48 logic checks pass**, and the final expanded iPhone flow passes with **zero failures in 168.984 seconds**. The independent native design reviewer found the requested fixes landed and no further high-impact visual defects in the captured screens. Physical-device/provider/accessibility-size validation remains outstanding.

### Batch 4
Implemented versioned backups with meal photos, integrity and schema validation, preview, local-copy conflict policy, opt-in preference restore, renewed sharing consent, and staged storage recovery. 68 logic checks pass; the final reviewed native scenario passes in 224.047 seconds with zero failures. See BACKUPS.md for format, merge rules and limits. The independent design review’s conflict-copy finding was addressed; published as `6abc670` on 29 October 2026.

### Batch 5
Implemented raw-record import progress and responsive cancellation across XML/CSV/JSON and preview preparation. Cancelled or abandoned operations cannot surface a late preview; no partial data is committed. Portable-file errors now state the 25 MB limit. 74 logic checks pass. A real Files-picker integration test cancels a 37 MB synthetic XML, verifies empty history, completes a previewed CSV import, and verifies its receipt after relaunch. Final screenshots and timing are in VERIFICATION.md.

### Batch 6
Direct ZIP import is implemented with bounded metadata preflight, a protected temporary snapshot, selected-entry extraction, integrity checks, cancellation and cleanup. Standard ZIP64 layouts are covered, including a private-copy compatibility fix that leaves original exports unchanged. The app bundles its dependency license. 106 logic checks pass. The final combined native suite passes all three scenarios with zero failures and no skips in 483.552 seconds. Design review confirmed the new ZIP scope disclosure; preview/error/native/license scores are 4/5. Cancellation waits for worker cleanup before enabling another file selection. Published as `2a9dc2b` on 29 October 2026.

### Publishing status
The verified foundation and three feature batches were each accepted by GitHub after authenticating as `dbakp`. The backup/restore batch was then accepted as `6abc670`, followed by responsive imports as `66b0655`, on 29 October 2026. `scripts/publish-batches.sh` publishes each new batch individually, in order. It checks branch state and refuses a dirty or divergent tree; it never force-pushes. Do not mark a batch published without GitHub accepting its push.

### Batch 7
Historical XML/ZIP workout summaries and six additional signals are implemented. Workouts retain source, duration provenance, field warnings and explicit missing energy. Repeat imports reconcile with live records and backup restoration preserves local copies. Activity and Journal open workout details; Insights shows recorded-day evidence with metric explanations. 140 logic checks pass, including old records, backup round trips, units, malformed fields, cancellation and reconciliation. Final native regression suite passes two scenarios with zero failures/no skips in 339.440 seconds, including import/reimport/persistence/exact evidence and the full daily/backup journey. Final visual review is recorded in Design/CRITIQUE.md; this batch awaits its separate GitHub push.

## Next delivery batch — reviewable conversational logging
Let a user turn an assistant conversation into a proposed health log, review and edit every field, then explicitly confirm it. Start with symptoms/check-ins and water/workout entries using existing storage and forms. Preserve user wording and record source/time, reject unsupported claims or inferred measurements, and keep provider availability visible. Logging must never silently change medication, erase records or write fabricated observations. Verify cancellation, duplicate confirmation, conversation changes and persistence. Voice capture, background HealthKit delivery, scanned-record OCR, broader source connections and signed-device release checks remain separate batches.
