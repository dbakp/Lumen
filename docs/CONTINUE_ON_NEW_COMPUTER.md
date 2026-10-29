# Continue Lumen on a new computer

Original handoff date: 29 October 2026. The development goal was paused on the previous computer at the user's request. At that checkpoint Batch 9 had not started, and the latest application batch was published on `main` as `86bc68f8c529adfeac8671b7c465f9f3ff117d80`. See the continuation checkpoint below for resumed work.

Clone this repository on the new computer, then give the new assistant the prompt below. Attach **app-designer-pro (1).zip** to carry over the original design skill; that attachment is not bundled in this repository. Personal health history and credentials need separate transfer: GitHub contains the application code and synthetic design/test artifacts. Use the app's backup/restore controls for health history where applicable; configure accounts and permissions on the new device separately.

## Continuation checkpoint · 29 October 2026

Development has resumed on the new computer. Batch 9a was published as `a1b7cd1`; Batch 9 was then completed and published as `5cb1fc7` on 29 October 2026. It adds honest current readings and source/date evidence, guarded assistant context, and local confirmed water/workout corrections and deletion. App Designer Pro has been supplied and used here; one continuing independent critic signed off the final native additions after three rounds. See [data-confidence behavior](DATA_CONFIDENCE.md), [Roadmap](ROADMAP.md), [Verification](VERIFICATION.md) and [Design critique](../Design/CRITIQUE.md) for exact scope, native timings and remaining gates.

The original prompt below remains the product brief. The full goal remains active. Continue the retained Sleep/Food and companion availability/estimate audit, then the remaining ingestion, backup, voice, provider and release work in coherent separately verified batches. Physical-device/provider gates are not satisfied by the simulator. The skill archive is intentionally outside Git; attach it again for a future computer/chat. Personal data and credentials still transfer separately.

## Continuation prompt

/goal Continue developing Lumen into a world-class, primarily iOS, AI health assistant.

Repository: https://github.com/dbakp/Lumen  
Latest published application commit: `5cb1fc7e4c76ef86ecc21d016eb1df6f5749d331`  
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

### Completed and published through batch 9

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

- 255 production-logic checks passed, including canonical source/date/zero semantics, corrections, history/context, backup compatibility and actual 14-night estimate selection.
- All five native targets build with Xcode 27.0 on this computer.
- Final confidence/correction/accessibility suite: three scenarios, zero failures/skips, 434.883 seconds.
- Final external-source import/persistence/disclosure scenario: 148.771 seconds, zero failures/skips.
- Final full daily/Library/conversation/appointment/backup journey: 250.531 seconds, zero failures/skips.
- One continuing design critic completed three rounds; final scoped screens meet the skill stop rule at 10/11 applicable lines at 4, richness at 3, with no remaining concrete visual/copy defects. Actual final captures: `Design/native/confidence/r3`.
- These are simulator and pure-logic results. Live HealthKit/provider behavior, VoiceOver, signed devices, clinical reliability and release readiness are not established. Machine-local result bundles are not portable; re-run relevant checks on another computer. See VERIFICATION.md for exact scope, the pre-existing runtime warning and remaining gates.

### Completed batch 9: data confidence and corrections

1. Distinguish missing readings from genuinely recorded zeros throughout Today, Activity, Insights and assistant context.
2. Add per-metric source/freshness evidence. HealthKit access requests do not prove every data type is readable.
3. Preserve live recorded zeros when reconciling imports.
4. Avoid presenting profile defaults or stale measurements as current observations.
5. Allow correction/deletion of locally confirmed water and workout entries, preserving provenance and updating dependent views/context.
6. Keep external-source records separate from local edits and make HealthKit write-back behavior explicit.

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
