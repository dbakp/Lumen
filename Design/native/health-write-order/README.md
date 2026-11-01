# Batch 35: order optional Health saves and deletions

Quick-water Undo and meal deletion could finish an Apple Health delete while the earlier save was still pending. That save could then complete and leave an external record behind the removed local entry. Both operations were separate unstructured tasks with no completion dependency. The controlled reproduction retains the exact sequence `save-start, delete, save-finish` and its remaining record for both water and meals.

`OrderedHealthWrites` now registers work synchronously with each local mutation. A record's deletion awaits its earlier save task, while unrelated records proceed independently. Meal/water namespaces remain separate even for identical IDs. Completion removes only the current queue tail, preserving a newer dependency chain. Cancelling a waiting consumer does not let its deletion bypass the previous task. Service failures remain handled by the existing callers; an operation must return before its successor starts.

Unstarted saves also check that their original local record is still present. Reset/restore invalidates pending saves while retaining the ordering chain for an already-started save and a requested deletion. An already-started Health operation cannot be recalled. Water writes use the original local log date for both sample endpoints, preserving its time when execution is delayed. This changes three application inputs: new ordering logic, HealthStore wiring and the HealthKit water timestamp argument. Persisted record/backup types, source ownership, local-only confirmed corrections, production views and copy remain unchanged.

## Verification

| Check | Result | Scope |
|---|---|---|
| Final focused ordering checks | 23 pass | Controlled asynchronous callbacks use the actual production ordering primitive |
| Complete Release logic suite | 1,488 pass | Original 1,465 plus 23 ordering/reproduction checks |
| Simulator BuildR2 | Pass | Lumen, widget, Watch, Watch widget and UI-test products |
| NativeR1 | Pass · 84.623s | One actual local water/meal lifecycle on the dedicated iPhone 18 Pro / iOS 27 simulator |
| Unsigned generic-iOS ReleaseR1 | Pass | Minimum iOS 18; 20 checked development markers absent; no bundled model packages |
| Final source equality | 235 inputs match | 192 application/build inputs plus selected logic/UI-test/package sources and fixtures |

The final ordering checks reproduce the old orphaned-record sequence, then verify save-before-delete, unrelated-record progress, separate domains, tail cleanup, three-operation chains, cancellation, handled save failure, invalidated unstarted saves, removed-record guards, fresh post-invalidation logs and an already-started save followed by deletion. Initial focused R1 covers 19 checks; final R2 adds four invalidation/currentness checks and matches the delivered logic.

NativeR1 performs two 250mL quick logs, Undo, relaunch with the remaining 250mL, second Undo to an absent reading, food selection, meal deletion and another relaunch. Health is unconnected: the actual guard returns **No Apple Health removal was attempted**. This proves the local lifecycle and current integration route; the delayed Health callback race itself is established by the controlled production-primitive tests, not actual HealthKit writes or signed-device timing. Native summary records one pass, zero failures/skips/runtime warnings. Five targeted original PNGs are retained and individually inspected; they are scrolled viewports. Capture 900 shows the amount with partially covered status, while 901/902/903 retain the full status. No full-page text/design-coverage claim or new design score is made.

BuildR1 fails only in the new test helper because `scrollAndTap` does not accept `towardsTop`. The helper is corrected to use the existing `reveal` API; BuildR2 passes. `source-r1.json` and `source-r2.json` differ only in that UI-test file. All final app/logic sources are identical to their passing verification inputs. BuildR2 records an AppIntents metadata-extraction warning because that framework is absent. ReleaseR1 records the existing orientation-policy warning from unchanged project configuration. Both remain in `producer-logs.json`; native runtime warnings are zero. These build warnings are not relabelled as an entirely warning-free release.

The previous actual MiniLM/CoreML 28-check run retains its earlier source/runtime boundary. No new model or retrieval-policy trial is claimed here. No application UI/copy file changes, so the accepted design direction and previous review remain; the new captures document behavior rather than a redesign.

## Evidence and reproduction

`ordering-final.json` retains focused traces, `verification.json` contains final outcomes/scopes, `native-summary.json` preserves the native result, `release-audit.json` records the exact unsigned binary/pin checks, and source maps/producer diagnostics keep the failed and passing boundaries. `captures.json` indexes all 13 attachments; the eight routine unchanged onboarding captures are redundant raw output, while the five targeted originals remain in Git.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --scratch-path /tmp/LumenLogicBuild LumenLogicChecks --health-write-order /tmp/ordering.json
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release --scratch-path /tmp/LumenLogicBuild LumenLogicChecks
```

Use a dedicated synthetic simulator for `testQuickWaterAndMealMutationLifecycle`; its setup intentionally resets Lumen's local test data. The original device ID and temporary paths are historical environment details, not portable requirements. Do not reset shared/personal devices or clear unrelated caches. Publication/read-back precedes removal of completed task-owned build/raw output.

The implementation follows [Swift's unstructured-task completion model](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/) and preserves Apple's [app-owned Health deletion boundary](https://developer.apple.com/documentation/healthkit/hkhealthstore/deleteobjects%28of%3Apredicate%3Awithcompletion%3A%29).

## Remaining work

This queue is process-local. Durable pending-save/deletion recovery, visible save failures/retries and actual permission/interruption/background behavior remain to be validated and implemented where needed. A missing or indefinitely delayed callback keeps the same-record successor waiting; a timeout must not falsely imply the underlying save finished. Local-only conversational corrections and independent source records keep their existing boundaries. Acknowledged identity-preserving Watch water reconciliation remains open.

The audit also identifies existing quick-log mutations using unchecked `LocalStore.save`, which can hide a local I/O failure, and meal photo deletion before the local removal is confirmed saved. Checked local commit/failure feedback is the next correction priority; it is not claimed fixed by this ordering batch. Broader claim support, live providers, clinical/language quality, physical Health/Watch/voice, VoiceOver, privacy governance and distribution remain open. The full product goal stays active.
