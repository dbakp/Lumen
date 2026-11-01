# Batch 36: checked quick-log storage

Verified and independently reviewed; publication and scoped cleanup are recorded below after GitHub read-back. The full product goal remains active.

Quick water, meals, manual workouts and weight previously changed the visible in-memory store before unchecked disk writes. Some callers dismissed their draft or issued a success haptic regardless of the write result. Meal deletion also removed its photo before the metadata deletion was durable. Batch 35 repaired optional Health write ordering, not these local I/O boundaries.

The repair saves a domain's replacement records before publishing them or scheduling an optional Health write. Failed saves retain form input and show a native alert on the active sheet. Food search keeps its selection view open on failure. Meal-photo creation uses a fresh non-overwriting ID and checked JPEG creation; failed metadata saving removes only that newly owned photo. Meal deletion saves the remaining records first, and retains any photo still referenced by another meal. Manual and confirmed corrections preserve their source ownership and local-only semantics.

Weight spans goals and today's dated observation. Its replacement directory is prepared off-thread using the existing recoverable transaction, hard-linking unchanged regular files and atomically replacing the two staged JSON files. This avoids copying the photo library. The process-local storage revision rejects preparation invalidated by another local write. Active Health sync is checked before preparation and immediately before commit because sync can also change in-memory readings before its final disk write. The commit and in-memory installation run on the main actor. Cancellation before commit discards preparation; the active form prevents duplicate saves and dismissal while committing. No persisted schema changes are introduced.

Existing writers replace LocalStore file contents atomically; deletion unlinks files. Only this local change path links unchanged files; encrypted/readable restore keeps its independent-copy path. Symbolic links and nonregular input files are rejected. A failed install recovers the old complete directory using the existing `.previous` recovery. See Apple's [hard-link API](https://developer.apple.com/documentation/foundation/filemanager/linkitem%28at%3Ato%3A%29).

Weight copy describes an optional Health attempt, not a confirmed external save. The Watch fallback reports a local failure on the phone without changing totals or claiming delivery acknowledgement. That warning is process-local; durable Watch identity/retry remains separate work.

## Verification boundaries

The Release logic run passes 1,505 checks, including 17 new production-transaction checks with real Foundation disk operations: untouched originals during staging, unchanged-photo inode retention, paired commit, stale-revision rejection, actual failed installation/recovery, blocked destination, symbolic-link refusal, cancellation and stage disposal. All 97 selected logic inputs still match that passing run. This is a transaction/component result; the UIKit stores are verified separately below.

| Check | Result | Exact boundary |
|---|---|---|
| Simulator BuildR1–R5 | All five products pass | Source maps retain each app/test boundary; R5 changes only native tests after R4 |
| NativeR2 | Seven cases pass, no failures/skips/runtime warnings | `application-source-r2.json` / `source-r2.json`; water save/undo, meal photo and metadata failure, deletion, food search, workouts, weight and relaunch |
| NativeR3 | Large-text weight passes 83.995s; busy retry fails | `application-source-r3.json` / `source-r4.json`; ordinary scroll exposes full disclosure and retained draft; immediate retry sees another honest busy message |
| NativeR4 | Busy-sync lifecycle passes 70.716s | Final app r5 / test r5; wait for actual accessibility readiness, then retry and verify dated reading after relaunch |
| NativeR5 | Today/Log-sheet water passes 122.659s | Final app r5 / test r6; active-sheet failure, retained menu, unchanged missing reading, successful retry and relaunch |
| SmallR1 | Three cases pass 392.861s combined | Final app r5 / test r5; actual 375×667 normal/dark AccessibilityXXXL weight and photo lifecycle, including relaunch before retrying failed deletion |
| Unsigned ReleaseR3 | Pass | Final app r5; minimum iOS18, all27 checked development markers absent, no bundled model packages |
| Final equality | 195 app/build, 97 logic and 216 selected-source inputs match | Separate overlapping source maps, not an additive count |

NativeR1 passes six cases and fails only because its helper requests **Add another food** in an empty photo draft. The helper is repaired before NativeR2. NativeR3's second busy response is retained in its accessibility hierarchy: the test had assumed immediate readiness after releasing a controlled sync. NativeR4 waits the actual **Ready to save** value instead of bypassing the guard or adding a fixed sleep. This value also makes current save readiness available to accessibility. The first focused-command attempt uses an incorrect binary path and runs no checks; the corrected `swift run --skip-build` invocation passes all17. Failed attempts, raw log hashes, compressed logs and source hashes remain distinct.

R2 precedes the Debug-only suspended-sync fixture; R3 adds it and rewrites the equivalent preflight guard as an `if`. The final visible weight UI differs from R3 only by its accessibility value; final application inputs remain unchanged after r5. Earlier source maps are hash/provenance records, not a claim that every superseded source version has a separately retained checkout. The current delivered sources are the reproducible final state. The earlier actual MiniLM run retains its own previous source/runtime boundary; it was not rerun or relabelled here.

Round1 provisionally scores43/55 with10/11 lines4+ and requests more evidence, not a UI redesign. The same critic individually inspects all56 Round2 originals and closes every concrete request at43/55: **Done within scope**. No app/UI change follows acceptance. See [critique](CRITIQUE.md) and `round2-captures.json`. Screenshots establish their viewports; runtime assertions separately establish persistence. Native warnings are zero in the passing summaries; compiler/IDE diagnostics retain their separate boundaries in `producer-logs.json`.

Debug simulator fault controls require an explicit synthetic test launch. They temporarily occupy the actual write destination with a directory, execute the real production write, surface its I/O error and restore exact old bytes. They do not fabricate an error result or alter signed-device/Release behavior. The synthetic photo is a small generated image. Native tests must establish retained drafts, honest failure, retry and relaunch separately from pure transaction checks.

The busy fixture holds the actual sync queue until a weight attempt observes its busy state, then releases it. It does not exercise real HealthKit requests. All native cases use an unconnected Health setup and synthetic input. The connected-weight copy branch is source-reviewed, not claimed as a signed-device presentation or successful external save.

To replay the focused component check, use `swift run -c release --scratch-path /tmp/LumenLogicBuild LumenLogicChecks --local-commit /tmp/local-commit.json`; omit the trailing arguments for the full logic suite. Native cases are in `LumenSmokeTests`. Use a dedicated synthetic simulator: the test helper intentionally resets Lumen's local test data. Recorded simulator IDs and temporary roots are historical, not portable requirements.

No claim is made about actual low-space exhaustion, power-loss durability, physical Health permission/write delivery, clinical quality, providers or VoiceOver. Other historical unchecked persistence paths remain outside this quick-log repair; this is not a whole-app storage audit. The full product goal remains active.
