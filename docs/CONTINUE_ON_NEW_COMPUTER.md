# Continue Lumen on a new computer

Original handoff date: 29 October 2026. The development goal was paused on the previous computer at the user's request. At that checkpoint Batch 9 had not started, and the latest application batch was published on `main` as `86bc68f8c529adfeac8671b7c465f9f3ff117d80`. See the continuation checkpoint below for resumed work.

Clone this repository on the new computer, then give the new assistant the prompt below. Attach the **App Designer Pro skill archive** to carry over the design skill; that attachment is not bundled in this repository. Personal health history and credentials need separate transfer: GitHub contains the application code and synthetic design/test artifacts. Use the app's backup/restore controls for health history where applicable; configure accounts and permissions on the new device separately.

## Continuation checkpoint · 30 October 2026

Development has resumed on the new computer. Batch 9a was published as `a1b7cd1`, Batch 9 as `5cb1fc7`, and Batch 10 as `d54c2e2` on 29 October 2026. Batch 9 adds current source/date evidence, guarded assistant context and confirmed local water/workout corrections. Batch 10 carries missing/zero and estimate semantics into Food, Sleep, Watch and widgets, with actual coverage, snapshot dates and guarded quick undo. App Designer Pro has been supplied and used here; the same continuing independent critic signed off each scoped addition after three rounds. See [data-confidence behavior](DATA_CONFIDENCE.md), [Roadmap](ROADMAP.md), [Verification](VERIFICATION.md) and [Design critique](../Design/CRITIQUE.md) for exact scope, native timings and remaining gates.

Batch 11 was published as `9361b0a34325bf4d557e1dd51f301fee77055aa4` on 30 October 2026. It adds password-protected streamed backups, large file-backed photo archives, progress/cancellation and guarded staged restoration while preserving older JSON backups. GitHub's `refs/heads/main` was read back and matched that application commit. See [Backup behavior](BACKUPS.md) for limits and password recovery expectations.

Batch 12 was published as `b2ed046ba18bdd6ffe50a0838c4a33abb6167e00` on 30 October 2026. It adds optional Health observation, durable paged sleep/workout replay and deletion handling, permission-review rescans, protected-data startup guards and factual check/connection states. GitHub accepted the push and `refs/heads/main` matched that application commit. Actual background/sample delivery still needs signed-device verification; see [Health synchronization](HEALTH_SYNC.md).

Batch 13 was published as `0ba58bd84e00756c30cef52cf279a2b712efb00f` on 30 October 2026. It adds on-device PDF/scan/still-image/UTF-8 reading, page/source comparison and correction, explicit review/exclusion and assistant consent, duplicate decisions, checked Library saves and compatible provenance. Private source/preview files are explicitly removed when the import sheet dismisses; the original file remains the user's separate copy. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Record import](RECORD_IMPORT.md) for exact scope and limits.

The original prompt below remains the product brief. The full goal remains active. The retained Food/Sleep and companion availability audit, large/encrypted backups, incremental Health observation/replay and scanned-record review are implemented within their documented scope. Continue additional ingestion/structured records, richer retrieval, voice, provider and release work in coherent separately verified batches. Signed-iPhone background delivery, general readable-export conversion, Watch water relay identity/acknowledgement, physical-device behavior and unseen widget/complication layouts remain open gates. Physical-device/provider gates are not satisfied by the simulator. The skill archive is intentionally outside Git; attach it again for a future computer/chat. Personal data and credentials still transfer separately.

## Continuation prompt

/goal Continue developing Lumen into a world-class, primarily iOS, AI health assistant.

Repository: https://github.com/dbakp/Lumen  
Latest published application commit: `0ba58bd84e00756c30cef52cf279a2b712efb00f`

Branch: `main`

Clone the repository on this computer and inspect its current state before making changes. Continue implementation autonomously in coherent batches. Verify and push each completed batch separately to GitHub. Never force-push or overwrite unrelated changes.

### Product intent

- A premium, harmonious, beautiful, light-first native experience.
- Import and connect health data, especially Apple Health.
- Give useful insights grounded in actual sleep, food, hydration, exercise, symptoms and personal context.
- Replace generic notifications with restrained contextual reminders.
- Support detailed symptom and body-pain logs, ongoing health conversations, practical plans and saved documents.
- Research meaningful market gaps where useful and implement valuable missing functionality.

### Read first

- [README](../README.md)
- [Roadmap](ROADMAP.md)
- [Verification evidence](VERIFICATION.md)
- [Implementation plan](IMPLEMENTATION_PLAN.md)
- [Import formats](IMPORT_FORMATS.md)
- [Conversational logging](CONVERSATIONAL_LOGGING.md)
- [Design direction](../Design/DIRECTION.md)
- [Design critiques](../Design/CRITIQUE.md)

Use the attached App Designer Pro skill. Preserve the established design direction. Use one independent design critic for native UI changes, address substantive findings, and capture actual simulator screens. `Design/native-preview.html` presents captured screens; it is not the application.

### Completed and published through batch 13

- Contextual Today, symptoms/check-ins, personal context and quiet reminders.
- Persistent conversations with cancellation and reply ownership.
- Editable dated plans, agenda and Library documents.
- Coverage-aware historical Insights and appointment summaries.
- Validated backup/restore, including meal photos, password-protected streamed archives, progress/cancellation, legacy JSON compatibility and guarded staged restoration.
- On-device scanned-PDF/still-image and selectable/UTF-8 record reading, private original/page comparison, source-version editing with keep/replace protection, explicit review/exclusion, assistant sharing off by default, duplicate-file decisions, checked Library mutations and compatible page/source provenance. Original files remain separate user-held copies.
- Optional Health observation with durable paged sleep/workout replay, explicit deletion evidence, permission-review rescans, checked application and guarded startup before protected data is readable. Background/sample delivery remains a signed-device gate.
- Cancellable imports with progress.
- Direct Apple Health ZIP imports with validation, extraction integrity and cleanup.
- Historical workouts and additional health signals, provenance and duplicate reconciliation.
- Reviewable conversational logging for symptoms, check-ins, water and workouts. Each entry requires explicit confirmation. Optional AI suggestions use the selected user message; missing or unsupported measurements remain blank. Original messages are separate from optional notes. Edited drafts have Close/swipe protection.
- Per-metric current readings with source/date/query evidence, explicit recorded zeros, guarded current assistant context, and local confirmed water/workout corrections/deletion with stable identity and retained provenance. External-source workouts remain separate.

### Latest validation

- **399 production-logic checks pass**, including actual macOS Vision recognition of synthetic scans/hybrid pages/images, retained selectable/UTF-8/CSV reference behavior, bounds/errors/cancellation, review/exclusion, metadata/legacy/backup compatibility and explicit cleanup while a preview reference remains retained. These are not a clinical accuracy benchmark.
- All five native simulator targets build with Xcode 27.0. A separate unsigned generic-iOS-device build also passes; signing/distribution and physical behavior remain unverified. The final app/test/project/shared source matches its build mirror across 146 files; exact hashes/logs are in VERIFICATION.md.
- Final cleanup/save suite: **2 tests, zero failures/skips, 241.454 s** (source replacement/software keyboard/footer 93.764 s; corrected two-page save/relaunch/duplicate 147.689 s). Native storage read-back confirms one record, both edited/corrected page bodies, sharing off, a matching input fingerprint and zero remaining record working folders after close.
- The final presentation/source suite passes separately in **263.732 s**, including dark mode, actual XXXL full-label controls, source selection, original rendering and return, edited-draft swipe/close protection, all-pages-excluded gating and keyboard clearance. A real Files recovery/cancellation/hybrid case passes separately in 135.440 s. The full daily/Journal/Assistant/Library/appointment/encrypted-backup regression passes separately in **230.552 s**, before final record-only refinements. No failed combined suite is counted as passing.
- App Designer Pro's same continuing critic signs off record-review round 3 at **10/11 applicable lines at 4+, Richness 3**, no remaining concrete visible/copy defect. Captures: `Design/native/records/r3`; their source list distinguishes result bundles. Subsequent cleanup is nonvisual and verified separately.
- Batch 12's three Health cases pass in 247.928 s, with actual SDK empty queries and retained native anchors; no physical background/sample delivery is established. Batch 11's actual 1,241,513,984-byte restore/export/reopen remains prior large-archive evidence. Companion packet/widget checks remain prior scoped evidence.
- OCR can misread units: the synthetic native scan visibly reads mg/L as ma/L before manual correction. Review is mandatory but does not establish medical correctness. Physical-device OCR performance, more languages/layouts, handwriting/tables/rotations, iCloud transfer, original archival/structured labs, signed-device Health delivery, providers, VoiceOver and release readiness remain open. Keep originals separately. The full product goal remains active.

### Completed batch 9: data confidence and corrections

1. Distinguish missing readings from genuinely recorded zeros throughout Today, Activity, Insights and assistant context.
2. Add per-metric source/freshness evidence. HealthKit access requests do not prove every data type is readable.
3. Preserve live recorded zeros when reconciling imports.
4. Avoid presenting profile defaults or stale measurements as current observations.
5. Allow correction/deletion of locally confirmed water and workout entries, preserving provenance and updating dependent views/context.
6. Keep external-source records separate from local edits and make HealthKit write-back behavior explicit.

### Completed batch 10: retained Food/Sleep and companions

Food and water preserve independent missing/zero values and separate rounded estimated targets. Quick undo cannot remove a confirmed conversation entry and reports its actual local/Health removal outcome. Sleep selects usable current episodes, identifies manual time in bed, names saved-entry/day coverage and gates debt/timing estimates. Measured-source target learning excludes manual time-in-bed logs. Source-managed sleep stays read-only.

Dated companion packets preserve presence, expire across days and reject delayed older contexts. Watch labels keep unknown values identifiable, snapshots show actual dates/times, and water totals change only after successful Watch Health saves. The readiness starting score is withheld when none of its contributing evidence exists. Preserve these contracts while extending the product; do not turn legacy numeric defaults into observations.

### Completed batch 11: encrypted streamed backups

Version-2 backups use native AppleArchive password encryption and stream file-backed photos with bounded metadata/record processing. Private file selection supports wrong-password retry; authenticated validation and photo decoding finish before review. Progress and a persistent Cancel control cover processing. Restore preserves current matching records and source/consent policy, stages changes privately, and checks the local storage revision before committing. Version-1 JSON backups remain compatible. Passwords are not stored or recoverable by Lumen.

The format enforces 2 GiB file/expanded-data bounds. Native validation establishes incoming and outgoing 1.24 GB archives with valid JPEG photos; it does not establish full 2 GiB device behavior, an independent cryptographic audit, iCloud or second-physical-device transfer, or every interruption/storage-pressure path. General readable exports remain separate from restorable backups. Preserve these boundaries and the revision/write barrier when extending storage.

### Completed batch 12: incremental Health observation and replay

Health observers are installed in the application delegate at launch. Opt-in background registration starts off and requests hourly delivery; iOS decides actual timing. A private device cache stores each 500-object sleep/workout page together with its native query anchor. Known deletions affect only managed Health records; manual entries and separate imported records remain. Checks replay after interrupted application, and a storage revision guard prevents replacing concurrent local edits. Current quantities still use the statistical/query-evidence path. A reviewed Health sheet requests a cursor rescan for newly available history without treating empty reads as deletions. Use Review Health access & sync after changing sharing outside Lumen.

Initial onboarding uses the same paged path. Protected data must be readable before stores load; a cold launch while locked must not load defaults over unreadable history. Disconnect/erase invalidates pending work and clears the new preference/check metadata. The cache is excluded from exported/backed-up domains and persists on the current device through a staged restore. Preserve these contracts. The initial predicate starts 730 calendar days before cache creation; record/file limits and the loss of old HealthKit tombstones are explicit in HEALTH_SYNC.md. This is not a lifetime replica or continuous monitoring.

### Completed batch 13: scanned record review

Library reads PDFs (including scans), still JPEG/PNG/HEIC images and UTF-8 text/Markdown locally, retaining both PDF text versions where available. Review offers page images and a read-only original viewer, correction/source selection and explicit page exclusion. Every included page needs text, at least one page must remain, and saving requires acknowledgement of all included pages. Edited drafts and source replacement have explicit keep/discard choices. Assistant sharing starts off and duplicate input bytes require a separate-copy decision.

The source is limited to 20 MB, 100 pages and 200,000 text characters; images/raster previews have documented bounds. Locked PDFs need unlocked copies; PDF form widgets need flattening. Recognition uses accurate Vision requests with language correction disabled; it can still misread names, numbers, units and reading order. Saved body text has page headings plus optional source fingerprint/method/edit/exclusion/review metadata; old documents/backups remain readable. Later body edits mark the text as changed after review. The original and recognition alternatives aren't permanent Library attachments. Preserve checked storage, consent, provenance and explicit working-folder cleanup on sheet dismissal. No measurements or Health samples are created from these records.

Continue the remaining roadmap afterward. Signed-device Health background delivery, additional ingestion/structured records, richer retrieval, voice, general readable-export conversion, provider integrations and release/device validation remain unfinished. Audit current files rather than assuming this list is exhaustive.

### Engineering and delivery

- Native SwiftUI Xcode project: `Lumen.xcodeproj`, scheme `Lumen`.
- Logic checks: `scripts/test-imports.sh`.
- Native tests: `LumenUITests/LumenSmokeTests.swift`. Use a dedicated simulator with synthetic data; the Health scenarios interact with the system permission sheet and the test harness resets local Lumen data.
- Discover this computer's Xcode installation and simulator IDs; previous-machine paths and IDs are not portable. The previous environment used Xcode 27.1 and an iOS 27 simulator.
- Do not run concurrent Xcode builds against the same DerivedData directory.
- `scripts/publish-batches.sh` publishes committed batches individually and rejects dirty/divergent state. Configure GitHub authentication with write access to `dbakp/Lumen` on this computer; previous-machine authentication is not transferred by cloning.
- Preserve old local-data decoding and backup compatibility.
- Do not push personal health data, credentials or real-user screenshots.
- Do not fabricate integrations, measurements, diagnoses or verification.
- Keep the full goal active until its requirements are actually implemented and verified; report external device/account/release dependencies honestly.
