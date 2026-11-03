# Keyboard and runtime-warning investigation · 3 November 2026

These diagnostics do not accept the complete connection UI or the product.

## Actual warning origin

The Lumen simulator's original unified-log records contain backtraces. Image UUIDs and offsets were mapped from an actual one-second process sample; `atos` resolves the leading calls to SwiftUICore `_FrameLayout.init(width:height:alignment:)` and SwiftUI `InputAccessoryBar.body`. The retained original log, image map and symbolication output establish this specific call path. R23 records at the current app UUID have the same first three framework UUID/offset pairs.

R23's authorized DEBUG-only no-Spacer variant still emits the warning. Its ordinary draft/save/reopen test passes, but that does not validate the hypothesis: removing the spacer did not remove the warning, and its keyboard capture also lacks drawn keys. R24 removes that experiment and restores application sources exactly to R17; R25 changes only tests. The actual R24/R25 application executable hashes match each other, but differ from the earlier observed R17 executable hash. Source identity is not relabelled binary identity.

## Independent native reference

`keyboard-reference-r1.swift` and `keyboard-reference.swift` compile as a separate small simulator app, outside the Lumen target. They use native SwiftUI sheet, NavigationStack, Form, input and keyboard-toolbar Done; no Lumen stores, credentials, network, theme or custom dimensions. The compiler reports a sysroot warning, retained in the complete build log; the actual linked binary reports IOSSIMULATOR/minimum18/SDK27 and passes strict signature verification.

R1 normal input reproduces one Invalid-frame warning. R2 uses the same executable for an ordinary input and a SecureField (`--secure-reference`), in separate processes74715/75518. Each reproduces one warning at exactly the same leading framework UUID/offset pairs. Parent opens all three original reference screenshots: literal text or secure bullets, caret, Done and actual drawn q/w/e/etc keys are visible. See the R1/R2 JSON receipts, source hashes, original PNGs and complete compressed logs. This proves the warning occurs in a small native reference without Lumen layout code. It does not establish the cause of Lumen's missing-key captures, an Apple-confirmed issue, or clean whole-product runtime behavior.

## Why the passing key-input test was not visual acceptance

R23's test passes native key hittability, actual touch, Done, six exact host-matched state checkpoints and checked fixture cleanup. But its1260 original is captured before the key touch and has no drawn keys. The native hierarchy contains a nonempty q key at a position inside the app and a216pt keyboard; that is insufficient visual evidence. Parent rejected the image and corrected the premature commentary claim. R24 moves capture after actual q/delete/q touches and adds keyboard bounds, but its1260 original still has no drawn keys. Preserve both original passing XCTest results and the separate negative pixel judgments. Do not call the visible-key gate passed.

R25 adds an ordinary model-field comparison using the same key-touch/Done/retained-record flow. Its outcome must be read from the actual result and pixels. Both reference input kinds draw keys outside XCTest, so secure fields alone do not explain the capture difference. An attempted direct Lumen comparison launches only the synthetic root; native control then reports the Mac locked again, before any field interaction. No direct-manual keyboard proof follows from that launch.

## Native edit-menu paging

R21/R22 scopes trials select a word but cannot reach Select All. R23's immediate fallback can disturb the client menu before it settles; R24 waits across native element types and reaches the client edit, then fails at scopes. The retained R24 hierarchy contains Cut, Copy, Replace, AutoFill and actual Previous Page/Next Page buttons. R25 reuses the existing conversation-title test's bounded native menu-page traversal, keeping complete exact replacement assertions. No partial replacement is saved or accepted. Earlier trials remain failed.

Keep full matrix, current-source regressions, continuing critic and Release/publication gates open. All inputs are synthetic, all provider traffic is fixed loopback, and reference diagnostics never contact a provider. Retain current raw evidence/caches for immediate work and required GitHub backup; no storage recovery is inferred from unrelated/APFS fluctuations.
