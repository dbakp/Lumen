# Reviewed FHIR lab import · Batch 23

The local FHIR R4 JSON flow is implemented and verified within [the import contract](../../../docs/FHIR_LAB_IMPORT.md). Publication/read-back and subsequent storage cleanup are recorded in the handoff and VERIFICATION.md. The broader product goal remains active.

## Verified behavior

Library imports standalone resources or Bundles with bounded literal JSON parsing, complete local resource/coverage accounting and explicit person review. Proposed Observation values/components retain declared forms, exact tokens and JSON pointers. Corrections stay separate from immutable original fields; included invalid rows require explicit exclusion. Reading original fields no longer discards the unsaved draft. Checked saving creates a stable sharing-off record; original-file duplicates require a separate-copy decision.

The record-owned receipt survives removal of every transcription. Backup/recovery, Markdown, retrieval and comparison snapshots preserve compatible typed provenance. History withholds scalar arithmetic for coded/string/qualified/structured forms, unproved manually added FHIR rows, changed captured-field layouts and repeated versions of a known Observation event. Effective timestamps never fill collection days. Legacy absent-metadata fingerprint/reference goldens remain unchanged.

## Logic, builds and exact source

- LogicR20: **996 passes**, 85 input hashes.
- BuildR15: all five simulator products pass. Unsigned generic-iOS ReleaseR1 passes.
- Production is unchanged from BuildR11 through R15. R12–R15 change native test positioning/captures only.
- Final audit: repository equals the build mirror for **189 native/project/test/fixture/asset inputs**; all 85 logic inputs match R20, all 151 recorded production inputs and both fixtures match R11, and the native harness matches R15.
- Every one of **114 retained original PNGs** matched its recorded SHA-256 before publication. `verification.json` retains source maps, compact terminal facts, screenshots and prior failures. Temporary paths become historical after scoped cleanup.

## Passing native cases on current production

| Run | Scope | Seconds | Source |
|---|---|---:|---|
| NativeR5 | Files, coverage/person/source, cancelled-row exclusion, correction13.25/original12.00, protected Cancel, save, receipt, relaunch, duplicate decline | 338.317 | BuildR11 |
| NativeR5 | Complete4,229-byte fixture, exact paged original method token, corrected overlong field, literal1.2300e-9 save | 164.988 | BuildR11 |
| NativeR5 | Remove every transcription, retain receipt, relaunch, exact-file duplicate decline | 275.691 | BuildR11 |
| NativeR6 | Dark and actual Accessibility XXXL source/person/review/editor/save/open/coded-result states | 410.804 | BuildR12 |
| SmallR2 | Complete actual375×667 lifecycle, native software-keyboard long-end/selection/correction/Done, save/relaunch/duplicate | 378.217 | BuildR14 |
| NativeR7 | Complete settled XXXL actions, final inclusion/acknowledgement/privacy, actual software-keyboard long-end/selection/Done/correction, dark/XXXL source/save/open | 494.838 | BuildR15 |

Each listed case passes with zero failures/skips. R5 is a mixed bundle: its separate presentation case fails. Later R6/R7 pass that appearance scope; no combined four-case pass is invented. No invalid-frame/nonfinite/constraint/fatal diagnostics were found by the scoped scan of R5/R6/SmallR2/R7 logs.

## Independent design review

The same continuing App Designer Pro critic scores Round1 **38/55**, Round2 **43/55**, then focused Round3 **43/55** and **Done**. Ten of eleven applicable lines are4+, Richness3; all required lines are4. All five concrete requests are closed: declared-form/original-versus-corrected hierarchy, visibly disabled gates, teal native source actions, singular/plain copy and essential editor-section ink. Round3 inspects all11 R7 originals plus four compact keyboard frames and compact605/607, closing the two remaining unchanged-UI evidence gaps. No new definite defect or subsequent UI change.

Exact judgments: [Round1](critique-round-1.md), [Round2](critique-round-2.md), [Round3](critique-round-3.md).

## Earlier failures remain failed

R1 searches original quantity fields on the wrong reader page. R2 exposes the real draft-lifetime bug when pushing a reader; explicit dismissal now clears input while ordinary disappearance only cancels workers. R3 fails an acknowledgement switch before reaching that fix. R4 passes314.803s on older BuildR8, before later UI/form guards; twelve originals retain that boundary.

R5 presentation fails after searching an earlier row that left the lazy accessibility tree; the helper incorrectly kept scrolling down. R6 adds a test-only known-earlier-row direction hint. SmallR1 reaches save/relaunch but fails a second-import coverage-switch AX tap. SmallR2 touches the visible native switch thumb once per requested state and asserts the resulting state, without retry or state injection. R7 adds test-only measured complete action/footer positioning and actual editor captures.

The R15 logic round's equality assertion incorrectly compared fractional Date values with the existing whole-second archive precision. Later checks compare every persisted field at archive precision and independently verify exact original FHIR tokens/byte ranges. Early compile/invocation/interrupted-build failures retain their recorded boundaries; no failing check is relabelled.

## Limits and remaining roadmap

Synthetic input only. This local review neither authenticates a clinical author nor validates every FHIR profile. Remote references, paging links, attachments and terminology are not downloaded. Clinical interpretation, broader FHIR bulk/XML/NDJSON and OCR tables, coding/UCUM normalization, live providers, physical devices, VoiceOver and release/privacy governance remain open. Keep the original source file separately.
