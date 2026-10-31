# Continue Lumen on a new computer

Original handoff date: 29 October 2026. The development goal was paused on the previous computer at the user's request. At that checkpoint Batch 9 had not started, and the latest application batch was published on `main` as `86bc68f8c529adfeac8671b7c465f9f3ff117d80`. See the continuation checkpoint below for resumed work.

Clone this repository on the new computer, then give the new assistant the prompt below. Attach the **App Designer Pro skill archive** to carry over the design skill; that attachment is not bundled in this repository. Personal health history and credentials need separate transfer: GitHub contains the application code and synthetic design/test artifacts. Use the app's backup/restore controls for health history where applicable; configure accounts and permissions on the new device separately.

## Continuation checkpoint · 31 October 2026

Development has resumed on the new computer. Batch 9a was published as `a1b7cd1`, Batch 9 as `5cb1fc7`, and Batch 10 as `d54c2e2` on 29 October 2026. Batch 9 adds current source/date evidence, guarded assistant context and confirmed local water/workout corrections. Batch 10 carries missing/zero and estimate semantics into Food, Sleep, Watch and widgets, with actual coverage, snapshot dates and guarded quick undo. App Designer Pro has been supplied and used here; the same continuing independent critic signed off each scoped addition after three rounds. See [data-confidence behavior](DATA_CONFIDENCE.md), [Roadmap](ROADMAP.md), [Verification](VERIFICATION.md) and [Design critique](../Design/CRITIQUE.md) for exact scope, native timings and remaining gates.

Batch 11 was published as `9361b0a34325bf4d557e1dd51f301fee77055aa4` on 30 October 2026. It adds password-protected streamed backups, large file-backed photo archives, progress/cancellation and guarded staged restoration while preserving older JSON backups. GitHub's `refs/heads/main` was read back and matched that application commit. See [Backup behavior](BACKUPS.md) for limits and password recovery expectations.

Batch 12 was published as `b2ed046ba18bdd6ffe50a0838c4a33abb6167e00` on 30 October 2026. It adds optional Health observation, durable paged sleep/workout replay and deletion handling, permission-review rescans, protected-data startup guards and factual check/connection states. GitHub accepted the push and `refs/heads/main` matched that application commit. Actual background/sample delivery still needs signed-device verification; see [Health synchronization](HEALTH_SYNC.md).

Batch 13 was published as `0ba58bd84e00756c30cef52cf279a2b712efb00f` on 30 October 2026. It adds on-device PDF/scan/still-image/UTF-8 reading, page/source comparison and correction, explicit review/exclusion and assistant consent, duplicate decisions, checked Library saves and compatible provenance. Private source/preview files are explicitly removed when the import sheet dismisses; the original file remains the user's separate copy. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Record import](RECORD_IMPORT.md) for exact scope and limits.

Batch 14 was published as `1f8923825c9e8638c8ca1100eb12af9cb768f70f` on 30 October 2026. It replaces fixed recent-record prefixes with bounded in-memory question-based Library search, fresh citable source IDs, saved reference snapshots, consent/content-aware history, literal on-device fallback and compatible backup/export provenance. Native flows cover sharing withdrawal, edit/delete, independently saved copies, an unsent quote draft and actual XXXL source text. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Library retrieval](LIBRARY_RETRIEVAL.md) for exact limits, history transition and retained-copy semantics.

Batch 15 was published as `a9866259b7e48722216ec1024f0d8dede6eae567` on 30 October 2026. It adds checked plain-JSON creation/sharing and separate reviewed conversion of historical readable exports, independent category/settings selection, read-only paged records/messages/text, explicit photo/demo/cache omissions, guarded merging, cancellation/cleanup and a clear completed state. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Readable export behavior](READABLE_EXPORT.md) for exact bounds, source/date limits and the distinction from encrypted backups.

Batch 16 was published as `c54df787051db1f513b949129a0db1a8ff5b425c` on 30 October 2026. It adds supported iOS 26+ on-device voice drafts, explicit language-download choice, bounded audio/transcript processing, focused editing/acknowledgement, guarded unsent insertion and separately confirmed health logging. Keyboard Return now submits after text-input binding updates and clears the submitted draft without erasing new typing. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Voice drafts](VOICE_DRAFTS.md) for scope and signed-device gates. That batch retained a water-editor invalid-frame diagnostic, subsequently resolved in the tested review/correction paths by Batch 17.

Batch 17 was published as `f8efaa8b5195d1692363a9a2ac330050288e6c55` on 30 October 2026. It removes the reproduced keyboard-layout diagnostic from the tested review and confirmed-correction forms, keeps native Done above the keyboard and moves optional notes into a full-size editor with exact text preservation. Native checks cover all four entry kinds, single-key edits, notes before/after confirmation and relaunch, corrections, deletion, actual XXXL/dark appearance and the complete original-message disclosure. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Conversational logging](CONVERSATIONAL_LOGGING.md) and the scoped evidence below.

Batch 18 was published as `a0426827fcacedfc4026445e649ee2984fc91a50` on 30 October 2026. It adds reviewed 1/2/4/8-week plans, selected-provider typed/validated proposals or an explicitly chosen local template, full wording/date review, fresh acknowledgement, checked saving and matching Library/agenda calendar days. Assistant sharing starts off, and legacy dates/backups remain compatible. GitHub accepted the push and `refs/heads/main` matched the application commit. See [Scheduled plans](SCHEDULED_PLANS.md) and the scoped validation below.

Batch 19 was published as `f957f1bec644e8da8e55da0b2feee390c78839d8` on 31 October 2026. It adds optional English on-device related-topic Library search, explicit model download/enable/off/delete, exact selection/coverage disclosures and four-excerpt local lookup. GitHub accepted the push through the batch publisher and `refs/heads/main` read-back matched before redundant artifacts were removed. See [Local related-topic search](SEMANTIC_SEARCH.md) for known relevance misses and remaining device/provider gates.

Batch 20 was published as `4e455c67560d9e5a46dad0ad63cf547fbcb431b6` on 31 October 2026 through `scripts/publish-batches.sh`; GitHub main read-back matched before disposable artifacts were removed. It adds reviewed lab transcriptions with literal values/units/reference wording and retained source excerpts. The full goal remains active.

The original prompt below remains the product brief. The full goal remains active. The retained Food/Sleep and companion availability audit, large/encrypted backups, incremental Health observation/replay and scanned-record review, question-based lexical Library retrieval and reviewed readable-export recovery are implemented within their documented scope. Continue additional ingestion/structured records, semantic retrieval quality, signed-device voice validation, provider and release work in coherent separately verified batches. Signed-iPhone background delivery, Watch water relay identity/acknowledgement, physical-device behavior and unseen widget/complication layouts remain open gates. Physical-device/provider gates are not satisfied by the simulator. The skill archive is intentionally outside Git; attach it again for a future computer/chat. Personal data and credentials still transfer separately.

## Continuation prompt

/goal Continue developing Lumen into a world-class, primarily iOS, AI health assistant.

Repository: https://github.com/dbakp/Lumen  
Latest published application commit: `4e455c67560d9e5a46dad0ad63cf547fbcb431b6`

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
- [Library retrieval and retained references](LIBRARY_RETRIEVAL.md)
- [Reviewed lab results and source excerpts](LAB_RECORDS.md)
- [Readable export and reviewed recovery](READABLE_EXPORT.md)
- [Conversational logging](CONVERSATIONAL_LOGGING.md)
- [Reviewed voice drafts](VOICE_DRAFTS.md)
- [Design direction](../Design/DIRECTION.md)
- [Design critiques](../Design/CRITIQUE.md)

Use the attached App Designer Pro skill. Preserve the established design direction. Use one independent design critic for native UI changes, address substantive findings, and capture actual simulator screens. `Design/native-preview.html` presents captured screens; it is not the application.

### Completed and published through batch 20

- Contextual Today, symptoms/check-ins, personal context and quiet reminders.
- Persistent conversations with cancellation and reply ownership.
- Supported iOS 26+ on-device voice drafts with explicit language download, native correction/acknowledgement, bounded temporary audio/text, immediate Stop and guarded unsent insertion. Sending/individual health-entry confirmation remain separate. Typed Return clears submitted text and preserves a subsequent unsent question.
- Editable dated plans, agenda and Library documents.
- Coverage-aware historical Insights and appointment summaries.
- Validated backup/restore, including meal photos, password-protected streamed archives, progress/cancellation, legacy JSON compatibility and guarded staged restoration.
- Checked readable JSON creation/share and separately reviewed recovery of historical Lumen exports. Category selection and independent setting replacements precede confirmation; setting replacements start off. Read-only paging, explicit photo/demo/cache omissions, current-copy merge policy and private cleanup remain distinct from encrypted backups.
- On-device scanned-PDF/still-image and selectable/UTF-8 record reading, private original/page comparison, source-version editing with keep/replace protection, explicit review/exclusion, assistant sharing off by default, duplicate-file decisions, checked Library mutations and compatible page/source provenance. Original files remain separate user-held copies.
- Reviewed lab transcriptions on saved records, with literal reported fields, source-before-save comparison, checked saving, stale-source handling and compatible backup/readable sharing. This is a manual review foundation; automatic ingestion/comparison remain open.
- Optional, explicit-download English on-device topic ranking supplements keyword search, with exact selection/coverage and four-excerpt local lookup; known relevance and device gates remain.
- Question-based in-memory search over explicitly shared Library text, current plan/checklist state, immutable reply references, source validation and visible current/changed/sharing-off/deleted states. Earlier replies without saved references remain visible and support quoting into an editable unsent question. Backups and readable sharing preserve compatible reference provenance.
- Optional Health observation with durable paged sleep/workout replay, explicit deletion evidence, permission-review rescans, checked application and guarded startup before protected data is readable. Background/sample delivery remains a signed-device gate.
- Cancellable imports with progress.
- Direct Apple Health ZIP imports with validation, extraction integrity and cleanup.
- Historical workouts and additional health signals, provenance and duplicate reconciliation.
- Reviewable conversational logging for symptoms, check-ins, water and workouts, with focus-bound keyboard dismissal, full-size optional notes editing and exact multiline text preservation. Each entry requires explicit confirmation. Optional AI suggestions use the selected user message; missing or unsupported measurements remain blank. Original messages are separate from optional notes. Edited drafts have Close/swipe protection.
- Per-metric current readings with source/date/query evidence, explicit recorded zeros, guarded current assistant context, and local confirmed water/workout corrections/deletion with stable identity and retained provenance. External-source workouts remain separate.

- Reviewed1/2/4/8-week plans with selected-provider proposals or an explicit local template, full wording/date review, fresh acknowledgement, checked saving, matching Library/agenda calendar days and sharing off by default.

### Latest validation · Batch 20 · 31 October 2026

Batch 20 is implemented, locally verified and published; GitHub main read-back matched the application commit above. It adds reviewed lab transcriptions to saved records, preserving literal result signs/decimals/units/reference/flags, optional dates/report details and exact source excerpts. Wrapped sources can include adjacent full lines. Checked saves preserve current consent and reject concurrent source/review changes. Later source edits mark old transcriptions as needing review and withhold their structured values from future assistant retrieval. Removing transcriptions preserves the record. See [Reviewed lab records](LAB_RECORDS.md).

- **633 production checks pass**, including actual encrypted/readable backup compatibility and stale/consent/source guards.
- All five simulator targets build; unsigned generic-iOS Release passes, minimum iOS 18. Current app source equals ReleaseR3; only test gestures/selectors change afterward. Final equality covers 172 native/project/UI-test files and 25 package/test/script files. Native SHA-256: `27dd27f077eaf7aefbe57639f1e189f1c83715560964cb34b6baea86297124f9`.
- NativeR3 fully passes presentation **221.019s** and reviewed lifecycle **224.023s**, zero failures/skips/recorded runtime warnings. Real Files recovery, source/typing/review/save/relaunch/correction/changed-source/removal and light/dark/XXXL keyboard/date/source paths are scoped in `Design/native/labs/verification.json`. Earlier failures remain failed.
- The same critic completes two rounds at **10/11 lines at 4+, Richness 3**, Finish 4, no concrete defects. All 22 final originals remain. No app UI change follows sign-off.

The full goal remains active. Portable/automatic lab ingestion, broader clinical/FHIR records, longitudinal comparison, comprehensive relevance/multilingual quality, live providers, signed-device Health/Watch/voice, physical accessibility/performance and release governance remain open. After GitHub confirmation, cleanup removed 66 task-owned roots and increased available space from 35,774,255,104 to 38,765,797,376 bytes: **2,991,542,272 bytes (about 2.99 GB)**. Both reused platform build directories, package scratch, obsolete mirror, raw bundles/exports/logs, one exact harness crash report and 22 redundant PNG working copies are gone. All 22 final originals, four useful R1 defects, compact outcomes, source/provenance maps, supplied skill, pinned model source and small current Library inputs remain. Full earlier pixels are recoverable in the application commit. Global caches, older/unrelated DerivedData, projects and simulators remain untouched; no links were followed or app build rerun for this cleanup checkpoint. See `Design/native/labs/storage-cleanup.json`.

### Batch 19 validation retained

Batch 19 is implemented, locally verified and published; GitHub read-back matched the application commit above. It adds optional English on-device related-topic Library ranking, explicit 45 MB model download/enable/cancel/off/delete, exact source method/coverage, and a complete four-excerpt literal packet. Sharing/source/settings guards remain; generic model files are separate from exported health data. Runtime-cache cleanup is bounded to packages matching eight fingerprints from the pinned weights and runs only after encoders/workers stop. Unknown layouts/unrelated caches remain untouched.

- **585 production-logic checks**, **21 actual-model/compatibility checks**, **14 actual installation checks**, plus **two isolated low-space checks** pass. The nine-case synthetic quality diagnostic retains the iron-stores miss and unexpected selections; it is not clinical validation.
- All five simulator targets build for testing; unsigned generic-iOS Release passes, minimum OS18. The build mirror matches **169 native files** and **20 package/test files**. Native SHA-256: `941298de4cd7de78ef0708bf470f0390c870dd1c1cf0507881d5842c6ad5fff0`. No test flags/labels or model packages remain in Release; the vocabulary hash matches its pin.
- Final-source native Library/four-reference/save/relaunch/withdrawal/edit/delete passes **279.672s** and remote download/cancel/retry/compile/inference/cold load/withdrawal/delete/erase passes **240.356s**, together with zero failures/skips/recorded runtime warnings. Cache-fixed earlier lifecycle **204.435s**, presentation **232.935s** and targeted XXXL coverage **145.770s** pass in a separate bundle; their one-result UI is unchanged by final backend-only refinements. Failed earlier bundles remain explicitly failed.
- The first on-disk erase audit exposed about901 MB of stale Core ML CPU programs. Final read-back finds no managed model directory, temporary compiled model or CPU caches; unrelated Metal files remain at **496,648 bytes**. This is the dedicated simulator, not every physical-device cache format.
- The same critic accepts R2 and cache-state/XXXL/final four-reference supplements at **10/11 applicable lines at 4, Richness 3**, no concrete defects. Original reviewed pixels, source boundaries, failed history and compact evidence are in `Design/native/semantic-search`; see [the contract](SEMANTIC_SEARCH.md).

The full goal remains active: structured labs/broader ingestion, comprehensive English/multilingual relevance, live providers, signed-device Health/Watch/voice, physical performance/accessibility and release/privacy governance remain open. After GitHub confirmation, scoped cleanup removed 139 task-owned roots and increased available space from 36,182,786,048 to 39,240,560,640 bytes: **3,057,774,592 bytes (about 3.06 GB)**. The repository, reviewed native PNGs, compact evidence, supplied skill and current model/Library inputs remain. The exact verification-executable cache namespace was removed only after its workers stopped; global/system/browser/unrelated application caches remain untouched. See `Design/native/semantic-search/storage-cleanup.json`. Temporary result paths are historical, and no application build was run for this documentation/cleanup checkpoint.

### Batch18 validation retained

- **548 production-logic checks pass**, including strict multiweek proposals, stable identities, calendar days, planned/current retrieval state and actual backup/readable round trips. Existing checks remain.
- All five simulator targets and an unsigned generic-iOS-device **Release** build pass. Final equality covers **159 native/project/UI-test files** and **17 package/test/check-script files**. Native SHA-256: `9dd0fe45624033eaef743b9f6413153696b99ddf0c1d66558bb099a9f8b52720`. Release min OS stays18.0; simulated plan/speech labels and the temporary numeric probe are absent. Later changes affect UI-test gestures/captures only; app source matches the Release build.
- Final-source normal delivery passes **113.743s** and actual XXXL software-key/date/save/relaunch/agenda passes **184.381s**, each inside its explicitly failed mixed bundle. Separate dark/eight-week/XXXL presentation passes **142.320s**. These have zero recorded runtime warnings. Earlier cancellation/failure **145.032s** and broad four-case daily/Library/backup **473.695s** results retain their precise source boundaries in VERIFICATION.md. No failed suite is relabelled.
- The final wording editor follows the existing full-notes pattern: a short literal step preview plus **Edit full step**, with date editing on the step form. Real visible keys prove an end insertion and two adjacent middle insertions; the exact text and moved calendar day survive Save and relaunch. Native Before saving navigation and the complete final Week8 action/date are captured.
- Temporary diagnostic/custom text bridges are removed. The original numeric selection was at the string end while the displayed caret/layout disagreed; exact-value and AX-keyboard-presence assertions alone were insufficient. Keep the stronger actual-key, geometry, exact text/date and acknowledgement checks. Compact failing and passing history stays in Git; temporary paths are historical after cleanup.
- The same App Designer Pro critic signs off R3 at **10/11 lines at 4+, Richness 3**, all concrete requests closed. The34 final native originals are in `Design/native/plans/r3`; no app UI source changes follow sign-off.
- Live-provider quality, clinical suitability, physical devices, VoiceOver and broader release gates remain open. The full product goal remains active. See [Scheduled plans](SCHEDULED_PLANS.md) and `Design/native/plans` for the contract and evidence.

- After code/evidence were confirmed on GitHub, cleanup removed **90 task-owned artifact roots**, **46 superseded PNG working copies** (15,676,137 logical bytes), and the obsolete 876-byte numeric-only simulator trace. Available bytes increased from **35,488,272,384 to 39,157,301,248** during the main cleanup, a measured **3,669,028,864-byte increase (about 3.67 GB)**. Both reused build directories, package scratch, obsolete mirror and raw test bundles/exports/logs are gone. The repository, all 34 final PNGs, useful defect/copy frames, compact evidence, supplied skill/archive and small synthetic simulator state remain. No unrelated cache, project, runtime or simulator was erased. Exact scope/measurements are in `Design/native/plans/storage-cleanup.json`; temporary paths in reports are historical. No build was run for this documentation/cleanup checkpoint.

### Batch17 validation retained

- **503 production-logic checks pass**, retaining the actual backup/import/retrieval/voice/PCM/Vision checks. Batch 17 changes native editing; model/schema, provider consent, source messages and explicit entry confirmation remain unchanged.
- All five simulator targets and a separate unsigned generic-iOS-device **Release** build pass with Xcode 27.0. Final source equality covers **155 native files** and **16 package/test/check-script files**. Native SHA-256: `4f1ba98245e5d80ca2e3ad30d8d9a3a3aee75335401253fc2bafe093d53a7866`. The supplementary source-disclosure UI test was added after the Release build; app source is unchanged. The Release executable excludes simulated speech text and minimum deployment remains iOS 18. Exact definitions/boundaries are in VERIFICATION.md and `Design/native/health-editor/source-verification.json`.
- The final all-kind review/correction case passes **365.997 s**, zero failures/skips/recorded runtime warnings: native first-key250→5/reopen5, replacement500, exact note, four individual confirmations, relaunch, water750/workout35-minute and note corrections, another relaunch, light/dark/XXXL corrections and guarded deletion. The full large-note route passes separately **103.118 s**, before only correction-editor alignment. The supplementary complete original-message view passes **68.624 s** against final app source, zero failures/skips/runtime warnings.
- The earlier individually passing Layout **47.124 s** and voice review/delivery **106.237 s** cases precede only the correction-form alignment and belong to an explicitly failed mixed-result bundle. They are not a combined passing suite. Native diagnosis/failing intermediate results remain in the compact report. Batch 16's **37.478 s** Return and **245.952 s** daily/backup results retain their earlier source boundaries in VERIFICATION.md.
- The previously retained water-editor invalid-frame warning is resolved in the tested review and correction paths; no diagnostic is suppressed. Exact text assertions also caught and fixed dropped note letters before confirmation. Notes remain optional with the existing 8,000-character limit; Done returns to the temporary draft and confirmation/Save remains separate. All-kind post-deletion storage read-back retains original messages, no chat water/workout identities and no app audio file. Supplementary disclosure later creates its own separate synthetic750 entry.
- The same App Designer Pro critic signs off round 2 at **10/11 applicable lines at 4, Richness 3**, all concrete requests closed. Final captures are `Design/native/health-editor/r2` (**20 PNGs**). Supplementary348 closes transitional131's complete-source visibility limitation with the same scores. R1 retains the useful hidden-caret defect plus all capture hashes/provenance. No app UI source changed after sign-off; the gallery makes no browser-DOM scan claim.
- After code/evidence were confirmed on GitHub, **91 task-owned artifact roots** were removed, including both reused build directories, package scratch, raw results/exports/logs and the obsolete mirror. Available bytes increased from **37,625,647,104 to 39,827,644,416**, a measured **2,201,997,312-byte increase (about 2.20 GB)**. Earlier superseded renders removed another 2,397,744 logical bytes. The repository, supplied skill, reusable tiny snapshot helper and small simulator state remain. Temporary report paths are historical; durable compact evidence is in Git.
- Signed-iPhone Health/Watch delivery, live microphone/language/number/negation/route/energy/model-download validation, live providers/citation quality, semantic/multilingual retrieval, structured records, VoiceOver, other keyboards/devices and release/privacy review remain open. Simulator results do not satisfy these gates. The full product goal stays active.

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

Continue the remaining roadmap afterward. Signed-device Health background delivery, additional ingestion/structured records, semantic retrieval quality, voice, provider integrations and release/device validation remain unfinished. Audit current files rather than assuming this list is exhaustive.

### Completed batch 14: question-based Library references

Each question builds a cancellable in-memory SQLite FTS5 index over explicitly shared documents. It selects at most four bounded non-overlapping passages (two per document), includes current plan status/checklists and retains saved-page locations where applicable. Document, character, byte and passage limits are explicit; search is lexical and no match does not establish absence. No persistent duplicate index or embedding service is added.

Successful model replies keep their selected packet; literal built-in lookups keep the excerpts they return. Fresh request-specific source IDs are validated before becoming human reference numbers; stale/unknown/bare markers cannot link to another record, and model-supplied destinations on source markers are stripped. Source sheets distinguish snapshot text from the current Library version. Saving notes/plans, backup/restore and readable sharing preserve optional provenance. A fallback label identifies the answer's source; an unsuccessful provider attempt may already have received the question/context.

Future history replays a source-bearing reply only while all of its selected content, sharing permissions and newly selected passages match. Old replies without saved references remain visible but are omitted from provider history; Quote in new question prepares an editable draft ending with a question cue, without sending it. User messages remain context. Turning sharing off or removing an original does not erase earlier conversations, independently saved copies, backups, exports or earlier provider requests. Keep these consent/version/copy boundaries and checked Library saves intact. See LIBRARY_RETRIEVAL.md.

### Completed batch 15: readable export and reviewed recovery

Export my data creates cancellable plain JSON with explicit sharing and private temporary-file ownership. A separate recovery route accepts historical/new readable Lumen roots, strictly rejects ambiguous/malformed known sections, and previews actual file dates, category counts and saved values before confirmation. Missing sections cannot replace settings with defaults. Name/sleep, body/activity goals, routines and personal notes are independent replacement choices, all off by default. Current matching records win, new document/personal-note sharing starts off, profile replacement preserves local lock/subscription/onboarding, and no samples are written to Apple Health.

The reader explicitly accounts for absent photo files, excluded demo meals/workouts, mirrored/recovered active chat and omitted temporary/unknown sections. Incoming meal photo references are removed; matching local meal photos remain. Daily saved timestamps retain the existing record precision; the original civil time zone was not stored and isn't reconstructed. Native readers page lists/messages/text and preserve all saved text, preferring natural breaks. User messages show their recorded date/time, assistant replies retain provider provenance, and completion leads with its saved result and Done.

Preserve the 100 MiB plain-file/combined-metadata bounds, per-section/aggregate limits, cancellable duplicate-key/typed validation, guarded staged storage revision barrier and explicit cleanup after workers stop. JSON is editable and cannot prove authorship. Large/password/photo transfers remain on the encrypted path. Keep READABLE_EXPORT.md and the exact native source/result boundaries in VERIFICATION.md as the contract while continuing the broader roadmap.

### Completed batch 16: reviewed voice drafts

Assistant opens a temporary local speech draft on supported iOS 26+ devices. Availability/language selection never starts a microphone or download; Download language and Start recording are separate decisions. Apple analyzer modules process bounded owned PCM streams, with actual format conversion and no recording file/server fallback. Stop ends microphone capture immediately, capture/finalization are time-bounded and foreground/audio changes stop rather than restart recording. Shared model storage and deferred asset cleanup remain iOS-managed.

Literal stopped text leads with Check your words. Edit text has a focused native editor with keep/discard protection; acknowledgement starts off and resets after edits. Use text only appends to the unchanged target conversation/current unsent draft. Send and every health-entry confirmation remain separate. Both typed submit callbacks queue their request outside binding updates, check the current conversation/text and clear the submitted composer without clearing new typing. Preserve these boundaries, the 8,000-character/32,000-byte/2,048-segment limits and the Debug-simulator-only fixture boundary. Signed-device speech remains open; the tested review/correction keyboard diagnostic was resolved in Batch 17. See VOICE_DRAFTS.md.

### Storage policy on every run

The user has limited local storage. Follow the repository's `AGENTS.md`: check available space, reuse active build output, and delete task-owned disposable artifacts after needed code/evidence is backed up on GitHub. Keep the working source, committed native screenshots/compact verification, the supplied skill and anything still in use. Clear obsolete raw test bundles, duplicate captures, temporary mirrors, large synthetic fixtures and project build caches; leave unrelated caches, simulators and personal files alone. Temporary paths referenced above may have been cleaned and must be regenerated when needed. Cleanup itself does not require rebuilding the app.

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
