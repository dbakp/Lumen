# Lumen

A native, local-first health companion for iPhone, with Apple Watch and widgets. Lumen combines what your devices record with how you actually feel, so your daily perspective, conversations and plans have context.

## The daily loop

**Today → Journal → Assistant → Library.** Today leads with a contextual explanation and its evidence, rather than a synthetic score. Sleep, Activity and Food remain a tap away. The default appearance is light, with cool white surfaces, deep teal actions and system typography. Settings supports Light, Dark and System.

- **Today:** guidance responds to recent sleep, ongoing symptoms, energy/stress check-ins, workouts, meals and water. Expand “Why this perspective” to inspect the evidence. Three labelled arcs show recorded/missing signals, not goal completion. Quick water and symptom logging are in reach.
- **Journal:** symptom name, body location, severity, onset, duration, description, possible triggers and resolution. Edit or delete logs, including resolved symptoms, from the timeline. Energy, mood and stress check-ins can also be edited or deleted. Sleep, meals, water, workouts and subjective logs appear together chronologically.
- **Assistant:** the existing Apple Intelligence / optional OpenAI provider receives current measurements, personal goals, recent symptom history, check-ins, imported history and opted-in record excerpts. Every new response identifies the provider that actually answered; failures use an explicitly labelled built-in guide. Plans requested in chat are saved automatically as editable drafts. Save any other answer manually. Urgent symptom phrases take priority over plan requests.
- **Personal context:** goals, food preferences, allergies, limitations and schedule, with explicit opt-in before the assistant uses these notes.
- **Conversations:** searchable chat history, reopen/rename/share/delete, safe routing of replies to the originating conversation and stop-response support. Existing chat migrates without losing messages.
- **Plans:** edit individual action items, assign dates, set active/completed/archived states and find pending steps in Today or the agenda.
- **Insights:** compare completed 7/30-day periods with actual coverage and sources; no inferred zero days or claims of causation. Create an editable appointment summary from your symptom descriptions, check-ins and activity.
- **Backup & restore:** versioned archives with meal photos, integrity checks, a record preview and a merge that keeps current copies. Profile restore is optional; recovered records require fresh assistant-sharing consent.
- **Library:** searchable plans, reviews, notes and records with type filters. Edit text, complete checklist steps, share document text, delete documents and choose whether each record is included in assistant context. A local weekly review summarizes coverage and logged events without claiming causation.

## Connections and imports

- **Apple Health:** live sleep/stages, activity, workouts, vitals, water, energy and macros. Refresh on launch, foreground and pull-to-refresh. Read permissions are private to Apple: “access requested” does not prove every type is readable. Fresh heart signals are limited to today; recovery comparisons need at least seven previous days of personal data.
- **Strava:** existing OAuth setup under Settings. Other devices can share through Apple Health or a compatible export; no direct Oura/Garmin connection is simulated.
- **Health history:** locally parse Apple Health `export.xml` (unzip Apple's export in Files first), or portable CSV/JSON. See actual reviewed-record counts and cancel parsing without adding partial data. Preview dates, sources, sample values and skipped records before committing. Reimports replace metric/day values. Historical imports populate Trends and assistant context; today's values fill missing live readings.
- **Records:** import text, Markdown or text-based PDFs. Extraction is local. Scanned PDFs need OCR first. Preview/edit before saving. Record text is excluded from assistant context until you enable it.

See [supported formats, units and aggregation rules](docs/IMPORT_FORMATS.md). XML supports up to 500 MB; portable files up to 25 MB; documents up to 20 MB / 200,000 extracted characters. Unsupported types and units are counted as skipped, never guessed. This is not a complete clinical-record ingestion system.

## Contextual notifications

Notifications are off by default. Connections contains opt-in, quiet hours and lock-screen detail controls. Lumen replaces the old repeating habit notifications with at most one non-repeating contextual check-in per day. Logging or syncing rebuilds the pending check-in. Ongoing symptoms, low energy or high stress suppress exercise pressure. Sensitive details are hidden by default. Lumen must run to refresh context; a scheduled notification cannot continuously observe changes made in other apps.

## Privacy and data

Profile, health logs, symptoms, check-ins, imported daily history, documents and chat are JSON in the App Group container, with file protection. Secrets stay in Keychain. Face ID lock, readable JSON export and erase-all are retained. Settings also provides restorable backups, including meal photos. Backups contain readable health data: save them privately. Credentials and device permissions are excluded. See [backup behavior and recovery](docs/BACKUPS.md).

Cloud models receive the current health summary and any record excerpts you explicitly included when you send a question. The provider is shown before sending. Choose the built-in guide or available on-device model for local processing. No backend, developer API key or account is bundled. Imported records are treated as untrusted reference text, never instructions.

## Retained features

Sleep need/debt and rhythm estimates, sleep sounds and rituals; manual and connected workouts; calorie/macronutrient tracking with meal photos and user-reviewed estimates; hydration and weight logging; metric trends; Apple Watch pages, water logging and habits; readiness/bedtime complications and iPhone widgets. Readiness remains an approximate wellness heuristic, not a clinical measure or a guarantee that exercise is appropriate.

## Build and verify

Open `Lumen.xcodeproj` in Xcode 27.1 or later; select **Lumen**. Deployment remains iOS 18+, with model and iOS 26/27 APIs availability-checked. Set your development team to run on a physical device. Bundle IDs use `com.dbakp.lumen` and App Group `group.com.dbakp.lumen`.

```sh
xcodebuild -project Lumen.xcodeproj -scheme Lumen -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
scripts/test-imports.sh
xcodebuild test -project Lumen.xcodeproj -scheme Lumen -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

The smoke test covers onboarding, water/symptom/check-in logging, contextual Today, assistant plans, Library notes and checklists, retained feature destinations and persistence after relaunch. It attaches screenshots. The standalone Swift tests exercise import parsing/cancellation, conversions, duplicate/source handling, sleep overlap, invalid inputs, model coding, backups and quiet-hour boundaries. For the separate native file-picker import scenario, seed its synthetic fixtures with `python3 scripts/seed-import-ui-fixtures.py <simulator-UUID>`; that scenario skips when fixtures are absent.

Real-device validation is still needed for Health permissions and writes, camera, Strava redirects, model availability/responses, notification delivery, Face ID, haptics, Watch communication and widgets.

## Design and implementation notes

[Verification](docs/VERIFICATION.md) · [Plan and market research](docs/IMPLEMENTATION_PLAN.md) · [Design direction](Design/DIRECTION.md) · [Design studies](Design/mockup.html). Studies use explicitly labelled sample data; production never seeds fictional health measurements. App Designer Pro from the user's attachment guided the three concepts, scans and independent critique. These local design studies are not claims of clinical or App Store validation.

Lumen supports wellness reflection. It does not diagnose, prescribe or replace clinical care.

## Incremental delivery

See [the missing-feature audit and batch roadmap](docs/ROADMAP.md). The foundation and first four feature batches were published individually on 29 October 2026 after account access was resolved. Each new verified batch is committed and pushed separately. `scripts/publish-batches.sh` publishes each commit separately and refuses to overwrite divergent history.
