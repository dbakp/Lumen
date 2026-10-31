# Lumen

Continuing on another computer? Start with the [continuation handoff](docs/CONTINUE_ON_NEW_COMPUTER.md).

A native, local-first health companion for iPhone, with Apple Watch and widgets. Lumen combines what your devices record with how you actually feel, so your daily perspective, conversations and plans have context.

## The daily loop

**Today → Journal → Assistant → Library.** Today leads with a contextual explanation and its evidence, rather than a synthetic score. Sleep, Activity and Food remain a tap away. The default appearance is light, with cool white surfaces, deep teal actions and system typography. Settings supports Light, Dark and System.

- **Today:** guidance responds to recent sleep, ongoing symptoms, energy/stress check-ins, workouts, meals and water. Expand “Why this perspective” to inspect the evidence. Three labelled arcs show recorded/missing signals, not goal completion. Quick water and symptom logging are in reach.
- **Food, Sleep and companions:** missing values stay unknown, recorded zeros stay zero, and estimated targets are separate. Manual nights are time in bed; sleep averages name their recorded coverage. Watch/widgets use dated snapshots, and a failed Watch water save leaves its total unchanged.
- **Data confidence:** today’s per-metric overview marks missing readings unknown, preserves recorded zeros, and exposes source and date evidence. Locally confirmed water/workout entries can be corrected or deleted with provenance retained. See [readings and correction rules](docs/DATA_CONFIDENCE.md).
- **Reviewed lab records:** add literal lab results, units, reported references/flags and optional dates to saved records, with source excerpts and explicit review. Changed source text marks earlier transcriptions for re-review. Backups retain the fields; no unit conversion or clinical interpretation is inferred. See [lab records](docs/LAB_RECORDS.md).
- **Lab-file import:** bring in bounded CSV, TSV or flat JSON tables, match columns, select the intended person, then review/correct included results before saving. Literal mapped source cells and an original-file receipt stay separate from corrections; sharing starts off. The receipt and exact-file duplicate identity survive removal of every transcription. Full text editors provide Select all, protected Cancel and a separate Done. See [lab-file import](docs/LAB_IMPORT.md).
- **Lab history:** choose reviewed records and confirm the intended person, inspect collection-date points and complete literal results, then review two source reports before saving an independent comparison. Exact recorded contexts and explicit decimal punctuation govern neutral arithmetic; changed or removed originals remain visible beside saved facts. Sharing starts off. See [lab history and comparisons](docs/LAB_HISTORY.md).
- **Conversational logging:** review your own message as editable symptom, check-in, water or workout drafts. Confirm entries individually; original wording, preparation source and confirmation time stay with the saved record. Optional AI suggestions use only the selected message. See [review and privacy behavior](docs/CONVERSATIONAL_LOGGING.md).
- **Journal:** symptom name, body location, severity, onset, duration, description, possible triggers and resolution. Edit or delete logs, including resolved symptoms, from the timeline. Energy, mood and stress check-ins can also be edited or deleted. Sleep, meals, water, workouts and subjective logs appear together chronologically.
- **Assistant:** the existing Apple Intelligence / optional OpenAI provider receives current measurements, personal goals, recent symptom history, check-ins, imported history and opted-in record excerpts. Every new response identifies the provider that actually answered; failures use a labelled built-in guide or literal Library lookup. Plans requested in chat are saved automatically as editable drafts. Save any other answer manually. Urgent symptom phrases take priority over plan requests. Question-based local search selects opted-in Library excerpts, with saved source snapshots and consent/version checks before history reuse. See [Library retrieval](docs/LIBRARY_RETRIEVAL.md).
- **Personal context:** goals, food preferences, allergies, limitations and schedule, with explicit opt-in before the assistant uses these notes.
- **Conversations:** searchable chat history, reopen/rename/share/delete, safe routing of replies to the originating conversation and stop-response support. Existing chat migrates without losing messages.
- **Plans:** prepare a routine for 1, 2, 4 or 8 weeks, review/edit every dated step and explicitly save it to Library and your agenda. An available AI provider proposes a draft; a separate local template remains clearly labelled. Planned calendar dates stay stable during travel. Existing action editing, completion/status and conversational drafts remain. See [scheduled plan behavior](docs/SCHEDULED_PLANS.md).
- **Insights:** compare completed 7/30-day periods with actual coverage and sources; no inferred zero days or claims of causation. Create an editable appointment summary from your symptom descriptions, check-ins and activity.
- **Voice drafts:** on supported iOS 26+ devices, speak on device, review and correct the text, then add it to an unsent Assistant message. Language downloads are a separate choice; sending and confirmed health logging remain separate. See [voice behavior and limits](docs/VOICE_DRAFTS.md).
- **Readable export recovery:** create unencrypted JSON, save it through Files, or review an earlier Lumen export before adding selected records. Setting replacements start off; missing photos and omitted cached sections are explicit. See [readable export behavior](docs/READABLE_EXPORT.md).
- **Backup & restore:** password-protected, streamed archives with meal photos, progress/cancellation and a review before merging. New files support up to 2 GB; older JSON backups remain readable. Current copies win, profile restore is optional, and newly recovered documents require fresh assistant-sharing consent.
- **Library:** searchable plans, reviews, notes and records with type filters. Edit text, complete checklist steps, share document text, delete documents and choose whether each record is included in assistant context. A local weekly review summarizes coverage and logged events without claiming causation.

## Connections and imports

- **Apple Health:** live sleep/stages, activity, workouts, vitals, water, energy and macros. Refresh on launch, foreground and pull-to-refresh, with optional observer-driven background updates. Sleep/workout changes use durable paged cursors and explicit deletion evidence; scheduling and locked-device behavior still require signed-device verification. See [Health synchronization](docs/HEALTH_SYNC.md). Read permissions are private to Apple: “access requested” does not prove every type is readable. Fresh heart signals are limited to today; recovery comparisons need at least seven previous days of personal data.
- **Strava:** existing OAuth setup under Settings. Other devices can share through Apple Health or a compatible export; no direct Oura/Garmin connection is simulated.
- **Health history:** locally read Apple Health export ZIPs or `export.xml`, plus portable CSV/JSON. ZIP imports validate metadata, extract only the health XML, and check its integrity before parsing. See actual reviewed-record counts and cancel parsing without adding partial data. Preview dates, sources, sample values and skipped records before committing. Reimports replace metric/day values. Workout summaries retain source, duration and missing-field provenance; repeated imports reconcile with live copies. Tap workouts in Activity for details. Historical imports populate Insights and assistant context; today's values fill missing live readings. Additional exported signals include heart rate, breathing rate, oxygen saturation, VO₂ max, body fat and BMI.
- **Records:** read PDFs, scans, still images, UTF-8 text and Markdown on device. Compare page images and text, correct or exclude pages, then explicitly review before saving. Assistant sharing starts off; keep the original separately. See [record import](docs/RECORD_IMPORT.md).

See [supported formats, units and aggregation rules](docs/IMPORT_FORMATS.md). ZIP files and expanded health XML support up to 500 MB each; portable files up to 25 MB; documents up to 20 MB / 200,000 extracted characters. Unsupported measurement categories and units are counted as skipped, never guessed. ZIP route and clinical-document files are not imported. This is not a complete clinical-record ingestion system.

## Contextual notifications

Notifications are off by default. Connections contains opt-in, quiet hours and lock-screen detail controls. Lumen replaces the old repeating habit notifications with at most one non-repeating contextual check-in per day. Logging or syncing rebuilds the pending check-in. Ongoing symptoms, low energy or high stress suppress exercise pressure. Sensitive details are hidden by default. Lumen must run to refresh context; a scheduled notification cannot continuously observe changes made in other apps.

## Privacy and data

Profile, health logs, symptoms, check-ins, imported daily history, documents and chat are JSON in the App Group container, with file protection. Secrets stay in Keychain. Face ID lock, readable JSON export and erase-all are retained. Settings also provides encrypted restorable backups, including meal photos. Keep the backup password separately; Lumen cannot recover it. Older JSON backups and readable data exports remain unencrypted. Credentials and device permissions are excluded. See [backup behavior and recovery](docs/BACKUPS.md).

Cloud models receive the current health summary and any record excerpts you explicitly included when you send a question. The provider is shown before sending. Choose the built-in guide or available on-device model for local processing. No backend, developer API key or account is bundled. Imported records are treated as untrusted reference text, never instructions.

## Retained features

Sleep need/debt and rhythm estimates, sleep sounds and rituals; manual and connected workouts; calorie/macronutrient tracking with meal photos and user-reviewed estimates; hydration and weight logging; metric trends; Apple Watch pages, water logging and habits; readiness/bedtime complications and iPhone widgets. Readiness remains an approximate wellness heuristic, not a clinical measure or a guarantee that exercise is appropriate.

## Build and verify

Open `Lumen.xcodeproj` in Xcode 27.0 or later; select **Lumen**. Deployment remains iOS 18+, with model and iOS 26/27 APIs availability-checked. Set your development team to run on a physical device. Bundle IDs use `com.dbakp.lumen` and App Group `group.com.dbakp.lumen`.

```sh
xcodebuild -project Lumen.xcodeproj -scheme Lumen -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
scripts/test-imports.sh
xcodebuild test -project Lumen.xcodeproj -scheme Lumen -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

The smoke test covers onboarding, water/symptom/check-in logging, contextual Today, assistant plans, Library notes and checklists, retained feature destinations and persistence after relaunch. It attaches screenshots. The standalone Swift package checks (ZIPFoundation pinned to 0.9.20) exercise import parsing/cancellation, conversions, duplicate/source handling, sleep overlap, invalid inputs, model coding, backups and quiet-hour boundaries. For the separate native file-picker import scenario, seed its synthetic fixtures with `python3 scripts/seed-import-ui-fixtures.py <simulator-UUID>`; that scenario skips when fixtures are absent.

The backup file-picker scenarios require separate synthetic archives. Use a new output folder each time; this opt-in generator makes a large local fixture (over 1 GB with 100,000 water records and valid JPEG photos), plus small encrypted, older JSON and damaged copies. No health data is read:

```sh
swift run --scratch-path /tmp/LumenLogicBuild LumenLogicChecks --backup-ui-fixtures /tmp/LumenSyntheticBackups
python3 scripts/seed-import-ui-fixtures.py <simulator-UUID> --backup-fixtures /tmp/LumenSyntheticBackups
```

The synthetic fixture password is `Synthetic backup passphrase 42`. Keep these generated files outside Git. The backup scenarios fail if their required files are absent; they do not claim a skipped file-picker scenario as verification.

Scanned-record scenarios use separate, explicitly synthetic PDFs/images/text. Generate and seed them outside Git:

```sh
swift run --scratch-path /tmp/LumenLogicBuild LumenLogicChecks --record-ui-fixtures /tmp/LumenSyntheticRecords
python3 scripts/seed-import-ui-fixtures.py <simulator-UUID> --record-fixtures /tmp/LumenSyntheticRecords
```

These cases fail when their required fixtures are missing. Recognition checks call the actual on-device Vision API on macOS; they are not a clinical accuracy benchmark.

Simulator widget/shared-container checks use local ad-hoc signing (`CODE_SIGN_IDENTITY=-`); an unsigned build does not establish App Group behavior. Add a Lumen widget to the dedicated simulator Home Screen for the optional retained-flow widget capture.

Real-device validation is still needed for Health permissions and writes, camera, Strava redirects, model availability/responses, notification delivery, Face ID, haptics, Watch communication and widgets.

## Design and implementation notes

[Verification](docs/VERIFICATION.md) · [Plan and market research](docs/IMPLEMENTATION_PLAN.md) · [Design direction](Design/DIRECTION.md) · [Design studies](Design/mockup.html). Studies use explicitly labelled sample data; production never seeds fictional health measurements. App Designer Pro from the user's attachment guided the three concepts, scans and independent critique. These local design studies are not claims of clinical or App Store validation.

Lumen supports wellness reflection. It does not diagnose, prescribe or replace clinical care.

## Incremental delivery

See [the missing-feature audit and batch roadmap](docs/ROADMAP.md). The foundation and first five feature batches were published individually on 29 October 2026 after account access was resolved. Each new verified batch is committed and pushed separately. `scripts/publish-batches.sh` publishes each commit separately and refuses to overwrite divergent history.

ZIPFoundation is used under its MIT license. Its notice is included in the app under Settings → Open-source licenses. Both the Xcode project and logic-check package pin the same release and revision.
