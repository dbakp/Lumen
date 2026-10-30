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
Batches 9a/9 established per-metric presence, evidence and local corrections. Batch 10 carries availability and honest estimates into Food, Sleep and companion snapshots. Batch 11 implements encrypted streamed backups and version-1 compatibility. Batch 12 adds incremental Health observation/replay while retaining the physical-device gate. Delivery evidence is recorded below; the full product goal remains active.

1. Physical-device/iCloud transfer, worst-case resource pressure and release review for backups and readable recovery. Encrypted streamed backups, progress/cancellation and version-1 compatibility are implemented in Batch 11; separate reviewed readable-export conversion is implemented in Batch 15. Preserve their distinct formats and explicit confirmation.
2. Signed-physical-iPhone validation of background HealthKit delivery, permission changes, lock/unlock, cold launch and interruptions. Batch 12 implements opt-in observation, durable anchored sleep/workout replay, deletion handling and delivery diagnostics. The implementation and simulator/unsigned-device builds do not satisfy this device gate; the app is not continuous monitoring.
3. Additional export categories beyond the completed workout/common-vital coverage, bounded-memory ingestion for very large histories, richer provenance and reviewable structured lab records. On-device OCR/reference-text review is implemented in Batch 13; structured interpretation remains separate. Keep unsupported formats explicit.
4. Direct provider connections only where official OAuth/API access is configured and tested. Existing HealthKit and Strava are not a substitute for pretending every device is connected.
5. Reviewed conversational logging is implemented in Batch 8, and on-device voice drafts with explicit text review/unsent insertion are implemented in Batch 16. Reviewed multiweek plans are implemented in Batch 18. Signed-device voice validation, live-model planning quality and additional explicit tool confirmations remain. The assistant does not silently modify every health log.
6. More complete data editing and reconciliation: HealthKit write failures, deletion confirmation/retry, source priority, import rollback, configurable retention and export units/timezones. The Food/Sleep and companion presence audit is implemented in Batch 10. Broader heuristic/clinical review and acknowledged identity-preserving Watch water reconciliation remain open.
7. Device release validation: denied/partial HealthKit access, real model inference, notifications in the background, camera, Face ID, Watch offline/reconnect and widgets, accessibility text sizes, localization and energy/performance profiling.
8. Clinical/product governance before any diagnostic feature, medications guidance, lab interpretation or regulated claims. Keep wellness guidance distinct from medical assessment.
9. Distribution: signed builds, CI on a configured macOS runner, TestFlight, privacy/store disclosures and crash reporting with explicit data-minimization choices. No credentials or paid services are assumed.

## Completion log
Pending batch entries will record commit, validation and push outcome below.

### Batch 9a — recorded-zero reconciliation foundation

Today's Health snapshot now preserves whether each cumulative query returned a reading, independently of its value. A recorded zero for steps, exercise, active energy or water takes priority over an overlapping import. Missing queries can still use imported coverage. Manual workouts are added only where the corresponding live metric exists or no imported total overlaps; an unknown workout energy value never establishes a recorded zero. Legacy positive totals remain readable; legacy zero defaults remain ambiguous until refreshed. Optional presence metadata preserves existing snapshot decoding.

Profile weight remains an input to estimated targets, but no longer fills a missing current measurement. Today's HealthKit weight and VO₂ max queries use today's sample window, while onboarding characteristics can still use the latest available profile values. A local weight entry resets an expired snapshot before adding today's measurement.

This is the data-layer part of Batch 9. Today/Activity missing-state labels, assistant context, per-metric source/freshness evidence and correction/deletion of confirmed local water/workout entries are still pending. Legacy cached discrete values lack sample dates; their freshness/migration treatment also remains part of that work. The App Designer Pro attachment required by the handoff was unavailable on this computer; no new UI design or independent design-review result is claimed for this delivery. Validation is recorded in VERIFICATION.md.

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
Historical XML/ZIP workout summaries and six additional signals are implemented. Workouts retain source, duration provenance, field warnings and explicit missing energy. Repeat imports reconcile with live records and backup restoration preserves local copies. Activity and Journal open workout details; Insights shows recorded-day evidence with metric explanations. 140 logic checks pass, including old records, backup round trips, units, malformed fields, cancellation and reconciliation. Final native regression suite passes two scenarios with zero failures/no skips in 339.440 seconds, including import/reimport/persistence/exact evidence and the full daily/backup journey. Final visual review is recorded in Design/CRITIQUE.md; published as `86fefba` on 29 October 2026.

## Batch 8 — reviewable conversational logging
Let a user turn an assistant conversation into a proposed health log, review and edit every field, then explicitly confirm it. Start with symptoms/check-ins and water/workout entries using existing storage and forms. Preserve user wording and record source/time, reject unsupported claims or inferred measurements, and keep provider availability visible. Logging must never silently change medication, erase records or write fabricated observations. Verify cancellation, duplicate confirmation, conversation changes and persistence. Voice capture, background HealthKit delivery, scanned-record OCR, broader source connections and signed-device release checks remain separate batches.

### Batch 8 completion evidence
Reviewable conversational logging is implemented for symptoms, check-ins, water and workouts. Only user messages can be selected. Local extraction is conservative; optional AI proposals use the selected message with literal evidence and explicit-unit checks. Entries require individual confirmation, checked atomic storage, valid fields and stable proposal IDs. Saved/pending counts, edited-draft Close/swipe protection, empty optional notes and retained source/provider/time provenance are implemented. Old records and backups remain compatible. 173 logic checks pass; all native targets build. The revised native logging scenario passes in 209.463 seconds and the daily/backup flow passes separately in 252.272 seconds. The final continuity extension passes in 144.131 seconds, verifying the assistant uses the newly saved symptom after relaunch. The design reviewer confirmed all requested fixes at 4/5; detailed evidence is in VERIFICATION.md and Design/CRITIQUE.md. Published as `86bc68f` on 29 October 2026.

## Batch 9 — data confidence and corrections
Expose the distinction between missing readings and recorded zero values, with per-metric source/freshness evidence and clear partial-access language. Add practical date/value correction and deletion for locally confirmed water/workout entries while preserving provenance and avoiding edits to external-source records. Verify corrections update Today, Journal, Insights and assistant context; preserve actual recorded zeros and leave unavailable data unknown. Broader HealthKit write-back reconciliation and physical-device delivery remain explicit subsequent gates.


### Batch 9 implementation and verification

The current-reading resolver now preserves per-metric presence, selected source, reported period, sample-time precision, estimate status and Health check outcome. Today, Activity, current evidence in Insights and assistant context share it. Undated legacy discrete readings no longer become today's observations, profile defaults remain target inputs, and unknown workout energy stays unknown in current and historical totals. Stand/roll hours count qualifying clock hours rather than standing duration. Historical totals rebuild from current local records, retaining independent external readings after local deletion.

Confirmed conversational water/workout records can be corrected, moved to a different date or deleted after a keep/delete prompt. Stable record IDs, original messages, preparation source and original confirmation time remain; edit time is separate. Checked storage completes before publishing a change. External workouts remain source-managed; these controls never write to HealthKit. Existing quick-water/meal/weight write paths are separate and documented.

The 255-check production-logic suite covers the resolver, calendar/source/zero semantics, actual 14-night estimate selection, correction and deletion, context, legacy decoding and backup compatibility. All five native targets build. Five native scenarios pass: the three-case confidence/correction/accessibility suite in 434.883 seconds, the external-source import flow in 148.771 seconds, and the full daily/Library/backup journey in 250.531 seconds, all with zero failures/skips. The independent design critic signed off round 3 at 10/11 applicable lines at 4 and richness at 3. Detailed build/flow/review evidence is in [Verification](VERIFICATION.md) and [Design critique](../Design/CRITIQUE.md). App Designer Pro is now supplied on this computer and is used for the native work. Signed-device/provider/release gates and the remaining roadmap remain open; completing this batch does not complete the full product goal.

## Next delivery focus

The retained Food/Sleep and companion availability audit is implemented in Batch 10, and encrypted streaming backups in Batch 11. Incremental Health observation/replay is implemented in Batch 12, and scanned-record review in Batch 13; signed-device delivery remains a gate. Continue additional ingestion/structured records, semantic retrieval quality, voice, provider and release work above in separately verified batches. Readable-export conversion is implemented in Batch 15. Backup/recovery device, iCloud and resource-pressure validation remain open. Do not infer clinical reliability, denied/read access or background delivery from the simulator results.


### Batch 9 publishing checkpoint

GitHub accepted `5cb1fc7e4c76ef86ecc21d016eb1df6f5749d331` on `main` on 29 October 2026, after the 255-check suite, native builds, all five simulator flows and round-3 design sign-off. The remote branch was read back and matched the source commit. Batch 9a had previously been published as `a1b7cd1`. The handoff now points to the completed application batch; the full product goal and remaining roadmap stay active.

## Batch 10 — retained Food/Sleep and companion evidence

Food preserves independent missing/zero energy, macros and water, with rounded estimated targets and source routes. Quick undo excludes confirmed entries, uses checked local removal and separately reports its Health removal outcome. Sleep selects usable dated episodes, identifies manual time in bed, states the actual seven-day entry denominator, requires complete coverage for debt and enough distinct days for timing models, and excludes manual time-in-bed logs from measured-source target learning. Source-managed sleep stays read-only. Readiness is withheld when none of its contributing evidence exists.

A shared dated presence packet feeds Watch/widgets without inferring measurements from old numeric defaults. Snapshots expire across days and an older context cannot overwrite a newer cache. Watch activity keeps empty queries unknown; successful Watch water saves and iPhone totals stay separate, and failed saves visibly leave the local total unchanged. This is not complete offline/idempotent water reconciliation.

288 logic checks and all five target builds pass. The three-case regression suite passed in 512.750 seconds; the final focused presentation scenario passed in 190.632 seconds. Actual installed medium widget and newly delivered Watch context are verified in the simulator. The same critic approved 21 final captures after three rounds at 10/11 lines at 4, richness at 3, with no remaining concrete visible defects. See VERIFICATION.md for exact source points, timings, limitations and final capture paths. Device/background/provider, larger/encrypted backup, voice, retrieval, accessibility and release work remain active.

### Batch 10 publishing checkpoint

GitHub accepted application batch `d54c2e27eff65c9a065ce59070d92296151f4337` on `main` on 29 October 2026. A read-back of `refs/heads/main` matched the source commit. The continuation handoff now points to Batch 10 and the remaining roadmap; the full product goal remains active.

### Batch 11 — encrypted streamed backups · 30 October 2026

Implemented password-protected version-2 archives with file-backed meal photos, 2 GiB file/expanded-data bounds, progress and persistent cancellation, version-1 JSON compatibility, private retryable input, explicit review/confirmation and staged restoration. Current-copy, source and fresh-consent policies remain. A local revision/write barrier prevents a staged restore from replacing concurrent edits. Native filenames use the device's local date.

343 production-logic checks and all five target builds pass. Actual native validation covers a 1,241,513,984-byte archive with 100,000 water logs/429 valid JPEGs, cancellation/retry/restore/relaunch, then a fresh iPhone export/reopen with 100,001 logs and 430 photos. The final large case passes in 204.870 seconds. Password, full daily/backup, dark/XXXL and external Files-save/reopen scenarios also pass individually; see VERIFICATION.md for exact result-bundle and intermediate-failure accounting. The same critic signs off after three rounds, 10/11 lines at 4, Richness 3, with no remaining concrete pixel/copy defects.

General readable-export conversion, physical-device/iCloud/resource-pressure/crypto/release review and the rest of the product roadmap remain open. The full goal remains active.

### Batch 11 publishing checkpoint

GitHub accepted application batch `9361b0a34325bf4d557e1dd51f301fee77055aa4` on `main` on 30 October 2026. A read-back of `refs/heads/main` matched that source commit. The continuation handoff now records the completed backup batch and its verification limits; this subsequent documentation checkpoint does not change application/test source.

## Batch 12 — incremental Health updates between visits

Implemented opt-in Health observers installed at application launch, paged anchored sleep/workout replay with durable cursor-plus-record writes, known-deletion reconciliation, coalesced refreshes and permission-review rescans. Current statistical readings retain their separate source/query evidence. The initial onboarding connection now uses the bounded path. Domain stores wait for protected data before loading; disconnect/erase invalidates in-flight work and clears the new local preference/check metadata. The device-only cache is excluded from exports/backups. Initial history is 730 calendar days, with explicit cache/page limits and retained older local records.

The UI separates connection, requested background delivery and actual checks. Empty reads do not establish permission or new measurements. Largest text stacks the switch and status, and onboarding benefits/privacy text avoid unsupported automatic-data and recovery promises. See [Health synchronization](HEALTH_SYNC.md) for contracts and physical-device gates.

373 logic checks pass. All five targets build for the simulator and unsigned generic iOS device. Three final native Health scenarios pass with zero failures/skips in 247.928 seconds; the full daily/backup regression passes separately in 233.169 seconds. Actual SDK empty-query cursors and relaunch persistence are verified; real sample/background delivery is not. The continuing critic approves round 4 at 10/11 applicable lines at 4, Richness 3, with no remaining concrete visible defect. Native captures/review history are in Design/CRITIQUE.md and detailed evidence in VERIFICATION.md. GitHub accepted `b2ed046ba18bdd6ffe50a0838c4a33abb6167e00` on `main` on 30 October 2026; a read-back of `refs/heads/main` matched that application commit. The subsequent documentation checkpoint does not change application/test source. Signed-device delivery, broader ingestion/retrieval/voice/providers, data reconciliation and release work remain open; the full goal stays active.

## Batch 13 · on-device record reading

Library gains scanned-PDF/still-image recognition and selectable/UTF-8 reading with cancellable processing, private page previews, original comparison, editable page versions and explicit page exclusion/review. Sharing starts off, duplicate-file saves require a decision, checked storage precedes success, and saved text carries optional page/source review provenance compatible with older documents and backups. The source file remains a separate user-held copy. This extends ingestion into unstructured reference records; structured laboratory interpretation, clinical accuracy, every language/layout and physical-device performance remain outside the implemented contract. See [Record import](RECORD_IMPORT.md) and the final verification/critique evidence.

Batch 13 publication: `0ba58bd84e00756c30cef52cf279a2b712efb00f`, verified against GitHub's main ref on 30 October 2026. Final evidence: 399 production checks; all native targets plus unsigned device build; passing native save/cleanup, source/presentation, recovery and daily/backup cases; three-round visual sign-off. Exact scopes, timings, hashes and remaining gates are in VERIFICATION.md. This completes the record-review batch, not the full product goal.

## Batch 14 · question-based Library references

Replaced fixed recent-record prefixes with bounded, cancellable in-memory SQLite FTS5 search across opted-in Library text, including current plan checklists. Each question has distinct citable source IDs; replies and independently saved notes/plans retain exact versioned excerpt snapshots. Source sheets identify current, changed, sharing-off and deleted records. Citation validation prevents stale/fabricated source markers from linking to another record. Built-in fallback returns literal text rather than an AI interpretation.

Provider history reuses source-bearing replies only when consent, exact content and newly selected passages still match; older replies without source maps stay visible and support explicit quoting into an editable new question. Backups and readable sharing retain optional reference metadata with clear independent-copy behavior. See LIBRARY_RETRIEVAL.md for limits and policy. 439 production-logic checks pass. All five simulator targets and an unsigned generic-device build pass. The final three-case native suite passes in 531.988 s; the daily/encrypted-backup plus reference regression passes separately in 334.267 s. The same critic approves round 3 at 10/11 applicable lines at 4, Richness 3, with no remaining concrete defect. Exact evidence, source hashes and limitations are in VERIFICATION.md and Design/CRITIQUE.md; publication is recorded in the following checkpoint. The full roadmap remains active; this is lexical retrieval, not a clinical grounding guarantee or live provider validation.

Batch 14 publication: `1f8923825c9e8638c8ca1100eb12af9cb768f70f`, verified against GitHub main on 30 October 2026. The following documentation checkpoint records this delivery without changing app/test source. The full product goal remains active.

## Batch 15 · readable exports and reviewed recovery

Export my data now creates a checked, cancellable plain JSON file with explicit creation and sharing, a private temporary workspace and no photo bytes. A separate recovery route converts historical Lumen exports, shows actual file/category values and read-only record/settings pages, and requires selected-category confirmation before using the guarded staged merge. Setting replacements start off, absent sections cannot create selected defaults, current matching data wins, and new sharing permissions start off. Missing photos, demo records, active-chat mirrors/continuations, unknown sections and excluded temporary totals are explicit. Long lists/messages/text use bounded native pages; text pages retain every character and prefer natural breaks. Recovery makes no Health writes. See [Readable exports](READABLE_EXPORT.md) for limits and historical date/time-zone policy.

The delivery evidence and exact native case/source boundaries are recorded in VERIFICATION.md and Design/CRITIQUE.md. The full product goal remains active: structured reference data, retrieval quality, voice, providers, signed-device Health delivery, Watch water acknowledgement, physical performance/accessibility and release work remain separate.

Batch 15 delivery: 482 logic checks; all five simulator targets and an unsigned device build; fully passing focused cases for sharing, encrypted backups, large review, recovery, error/cancellation, dark/XXXL and role-specific metadata. The final reader/recovery suite passes in 502.117 s, followed by the targeted metadata case in 89.523 s; exact prior case and mixed-suite boundaries are explicit in VERIFICATION.md. The same critic signs off round 3 at 10/11 lines at 4, Richness 3, with all concrete findings closed. Publication is recorded in the following checkpoint.

Batch 15 publication: GitHub accepted application commit `a9866259b7e48722216ec1024f0d8dede6eae567` on `main` on 30 October 2026, and a read-back of `refs/heads/main` matched it. This following documentation checkpoint changes no app/test source. The full product goal remains active.

## Batch 16 — on-device reviewed voice drafts

Assistant adds a microphone route on supported iOS 26+ devices using Apple's local analyzer/transcriber modules, with an explicit language choice and separate model-download decision. Opening never starts a microphone/download. Bounded owned PCM buffers, actual sample-rate/channel conversion, provisional/final replacement, immediate Stop, three-minute/finalization limits and foreground/audio interruption handling feed a temporary review. No audio file or remote transcription fallback is added. iOS manages shared language assets and their deletion timing.

A focused editor protects unsaved changes. Names/numbers/units acknowledgement starts off and resets on edits; Use text appends only to the unchanged target conversation/unsent draft. Send and each health-entry confirmation stay separate. Programmatic multiline voice/quote insertion cannot invoke the keyboard Return send path. Typed Return remains supported. Synthetic native fixtures are visibly labelled and excluded from Release builds.

503 production-logic checks pass, including the actual PCM copy/resampler/drain and transcript/target/composer policy. Final app/companion builds and native light/dark/XXXL, edit/discard/background, unsent/send/individual-confirm/relaunch evidence are scoped in VERIFICATION.md and Design/CRITIQUE.md. Real microphone/acoustic/language/route/energy, VoiceOver, model-download resource-pressure and release/privacy gates remain open. This is not a clinical transcription benchmark. The full product goal stays active.

Batch 16 publication: GitHub accepted `c54df787051db1f513b949129a0db1a8ff5b425c` on `main`; remote read-back matched. The handoff now points to this batch. After preserving code/captures/compact evidence on GitHub, scoped cleanup increased available space by about **2.27 GB**. The full goal remains active.

## Batch 17 · health-entry keyboard and notes integrity

Health-entry review and saved local water/workout corrections now use distinct text focus and a native Done inset above the keyboard, replacing the keyboard-toolbar path that reproduced an invalid-frame diagnostic. Optional notes have a full-size editor and explicit full-note route; local editing state and atomic draft updates preserve exact typed characters. Done, entry confirmation, correction Save and keep/discard remain separate. Source statements and confirmation metadata are retained.

503 production-logic checks pass; all five simulator targets and an unsigned device Release build pass. The final all-kind review/correction/relaunch/deletion case passes in 365.997 s with zero recorded runtime warnings; complete source disclosure passes in 68.624 s. Actual XXXL notes/end-caret and full-note-route evidence passes separately. Exact earlier-source/mixed-result boundaries are in VERIFICATION.md. The same critic signs off round 2 at 10/11 lines at 4, Richness 3; supplementary source visibility is approved without an app change. No physical-device/VoiceOver claim follows.

Batch 17 publication: GitHub accepted `f8efaa8b5195d1692363a9a2ac330050288e6c55` on `main`, and remote read-back matched. Scoped cleanup after publication increased available space by **2,201,997,312 bytes (about 2.20 GB)**. The handoff points to this application batch; this documentation/cleanup checkpoint changes no app/test source. The full product goal remains active.

## Batch 18 · reviewed multiweek plans

Assistant and Library offer a reviewed 1/2/4/8-week plan with a chosen start date. Actual selected-provider generation uses a typed/strictly validated proposal; the separately chosen local planning template is visibly nonpersonalized. Every dated step stays editable, week navigation reaches the full schedule, and fresh acknowledgement precedes checked saving. Completion leads to the saved Library plan; unfinished steps appear in the agenda with matching calendar days. Assistant sharing starts off. Existing daily chat plans and legacy absolute dates remain compatible.

Calendar-day provenance, backup/readable recovery, current retrieval text and limits are documented in [Scheduled plans](SCHEDULED_PLANS.md). Synthetic model/UI fixtures establish structural and interaction behavior only; live provider quality, clinical suitability, physical-device behavior, VoiceOver and broader release gates remain open.

Published as `a0426827fcacedfc4026445e649ee2984fc91a50` after 548 production checks, final-source normal/software-key/date persistence cases, a separate 142.320s passing presentation case and the same critic's R3 sign-off (10/11 lines at 4+, all concrete issues closed). Exact mixed-bundle boundaries remain in VERIFICATION.md. After GitHub confirmation, scoped cleanup recovered a measured 3,669,028,864 available bytes; raw results/build caches are historical, compact evidence/final native captures remain.


## Batch 19 · optional local related-topic Library search

Adds off-by-default English topic ranking beside keyword search, using a pinned 45 MB Core ML model with explicit download/enable, actual byte progress, cancellation, disabled retention and checked deletion. Source sheets distinguish keyword/topic/carried selection and actual comparison coverage; literal lookup keeps all four bounded selected excerpts. Source consent/current-content/settings changes remain guarded. Backups, readable recovery and referenced Markdown retain compatible method provenance. See [Local related-topic search](SEMANTIC_SEARCH.md).

The storage audit caught about901 MB of accumulated CPU program caches after managed-model erasure. Cleanup now targets only bounded current-app packages matching eight pinned weight fingerprints, after workers/encoders stop. Final disk read-back retains unrelated Metal files at496,648 bytes and finds no managed model directory or CPU programs. The layout check is scoped to the measured runtime; physical-device/cache-format gates remain.

585 default checks,21 actual-model/compatibility checks,14 actual installation checks and2 isolated low-space checks pass. All five simulator targets and unsigned generic-iOS Release build pass. Final-source native Library/four-reference/retained-source regression passes279.672s and actual remote model/erase passes240.356s; earlier passing presentation/lifecycle/XXXL cases keep their precise source boundaries. The continuing critic accepts the scoped work at10/11 lines at4, Richness3, no remaining concrete defects. Publication is recorded in the following checkpoint.

The small synthetic diagnostic improves expected-context retrieval from six to eight of nine cases while retaining the iron-stores miss and extra selections. This is not a clinical benchmark or live-provider validation. Structured reference data, comprehensive relevance/multilingual quality, physical devices/VoiceOver, Health/Watch/voice delivery and release governance remain open. The full product goal stays active.
