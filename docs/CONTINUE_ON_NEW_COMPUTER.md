# Continue Lumen on a new computer

Original handoff date: 29 October 2026. The development goal was paused on the previous computer at the user's request. At that checkpoint Batch 9 had not started, and the latest application batch was published on `main` as `86bc68f8c529adfeac8671b7c465f9f3ff117d80`. See the continuation checkpoint below for resumed work.

Clone this repository on the new computer, then give the new assistant the prompt below. Attach **app-designer-pro (1).zip** to carry over the original design skill; that attachment is not bundled in this repository. Personal health history and credentials need separate transfer: GitHub contains the application code and synthetic design/test artifacts. Use the app's backup/restore controls for health history where applicable; configure accounts and permissions on the new device separately.

## Continuation checkpoint · 29 October 2026

Development has resumed on the new computer. Batch 9a was published as `a1b7cd1`, Batch 9 as `5cb1fc7`, and Batch 10 as `d54c2e2` on 29 October 2026. Batch 9 adds current source/date evidence, guarded assistant context and confirmed local water/workout corrections. Batch 10 carries missing/zero and estimate semantics into Food, Sleep, Watch and widgets, with actual coverage, snapshot dates and guarded quick undo. App Designer Pro has been supplied and used here; the same continuing independent critic signed off each scoped addition after three rounds. See [data-confidence behavior](DATA_CONFIDENCE.md), [Roadmap](ROADMAP.md), [Verification](VERIFICATION.md) and [Design critique](../Design/CRITIQUE.md) for exact scope, native timings and remaining gates.

The original prompt below remains the product brief. The full goal remains active. The retained Food/Sleep and companion availability audit is implemented. Continue larger/encrypted backups, ingestion/background delivery, richer retrieval, voice, provider and release work in coherent separately verified batches. Watch water relay identity/acknowledgement, physical-device behavior and unseen widget/complication layouts remain open gates. Physical-device/provider gates are not satisfied by the simulator. The skill archive is intentionally outside Git; attach it again for a future computer/chat. Personal data and credentials still transfer separately.

## Continuation prompt

/goal Continue developing Lumen into a world-class, primarily iOS, AI health assistant.

Repository: https://github.com/dbakp/Lumen  
Latest published application commit: `d54c2e27eff65c9a065ce59070d92296151f4337`

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

### Completed and published through batch 10

- Contextual Today, symptoms/check-ins, personal context and quiet reminders.
- Persistent conversations with cancellation and reply ownership.
- Editable dated plans, agenda and Library documents.
- Coverage-aware historical Insights and appointment summaries.
- Validated backup/restore, including meal photos.
- Cancellable imports with progress.
- Direct Apple Health ZIP imports with validation, extraction integrity and cleanup.
- Historical workouts and additional health signals, provenance and duplicate reconciliation.
- Reviewable conversational logging for symptoms, check-ins, water and workouts. Each entry requires explicit confirmation. Optional AI suggestions use the selected user message; missing or unsupported measurements remain blank. Original messages are separate from optional notes. Edited drafts have Close/swipe protection.
- Per-metric current readings with source/date/query evidence, explicit recorded zeros, guarded current assistant context, and local confirmed water/workout corrections/deletion with stable identity and retained provenance. External-source workouts remain separate.

### Latest validation

- 288 production-logic checks passed, covering prior imports/backups/corrections plus retained-view coverage, packet presence/expiry/order and withholding unsupported readiness.
- All five native targets build with Xcode 27.0. Shared-container simulator checks use local ad-hoc signing; physical signing/distribution remains unverified.
- The three-scenario current-reading/retained/daily-and-backup regression suite passed with zero failures/skips in 512.750 seconds. The final focused presentation run passed in 190.632 seconds.
- A real installed medium widget reads the iPhone app cache. The paired Watch received a newer actual five-zero packet with no readiness field. Failed Watch Health saves display an error and leave the Watch-local total unchanged. This does not establish all offline/reconnect/permission paths.
- The same independent critic approved all 21 final captures after three rounds: 10/11 lines at 4, richness at 3, no concrete visible defects. Final captures: `Design/native/retained/r5` and `Design/native/retained/companion-r2`.
- These are simulator and pure-logic results. Live providers, physical Health behavior, every widget/complication family, VoiceOver, clinical reliability and release readiness remain open. See VERIFICATION.md for exact source points, timings, diagnostics and limitations. Re-run machine-local result bundles/checks on a new computer.

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

Continue the remaining roadmap afterward. Background HealthKit delivery, broader ingestion/OCR, richer retrieval, voice, larger/encrypted backups, provider integrations and release/device validation remain unfinished. Audit current files rather than assuming this list is exhaustive.

### Engineering and delivery

- Native SwiftUI Xcode project: `Lumen.xcodeproj`, scheme `Lumen`.
- Logic checks: `scripts/test-imports.sh`.
- Native tests: `LumenUITests/LumenSmokeTests.swift`.
- Discover this computer's Xcode installation and simulator IDs; previous-machine paths and IDs are not portable. The previous environment used Xcode 27.1 and an iOS 27 simulator.
- Do not run concurrent Xcode builds against the same DerivedData directory.
- `scripts/publish-batches.sh` publishes committed batches individually and rejects dirty/divergent state. Configure GitHub authentication with write access to `dbakp/Lumen` on this computer; previous-machine authentication is not transferred by cloning.
- Preserve old local-data decoding and backup compatibility.
- Do not push personal health data, credentials or real-user screenshots.
- Do not fabricate integrations, measurements, diagnoses or verification.
- Keep the full goal active until its requirements are actually implemented and verified; report external device/account/release dependencies honestly.
