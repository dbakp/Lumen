# Batch 23 · reviewed FHIR lab import · Round 1

Independent App Designer Pro review, 31 October 2026. **Not done: this is a partial normal-phone review, with concrete semantic/affordance/copy corrections and appearance/compact evidence still required.** No app source was edited.

## Evidence boundary

Read Batch 23 in `Design/DIRECTION.md`, `docs/FHIR_LAB_IMPORT.md` and the supplied `critique.md`, `copy.md` and `finish.md`. Opened every one of the **12 original PNGs in `r4/` individually at original size**: 600, 609-coverage, 609-person, 601, 602, 603, 622, 604, 605, 606, 607 and 608. No older capture folder was substituted.

The reported lifecycle case passes in 314.803s, one test, zero failures/skips, covering real Files, coverage/person, explicit exclusion, correction/source reading and return, protected cancellation, save/receipt/relaunch and duplicate decline. This is reported behavior, not independently rerun here; the stills establish only their visible states. The separately pending core-only history guard earns no pixel credit. Earlier documentation describing older native failures is not treated as a passing whole-batch result.

## What already works

The established cool ground, deep teal action, expanded display and native sheets/forms remain consistent. The introductory task is clear, and the completion in 604 leads with **Lab results saved**, the actual record title, the included count and **assistant sharing off**. Its complete action fits its teal background.

Coverage separates **7 entries**, **6 resources** and **4 result proposals**, and explicitly says the additional reported page was not downloaded. The person screen visibly distinguishes two choices and requires its own check. Reported preliminary/cancelled statuses and unknown collection days remain visible; an effective timestamp has not been presented as a collection day in these frames.

The reviewed value **13.25** in 622/605 is visibly distinct from the exact original **12.00** token in 603, including its original unit/system/code and source pointer. The receipt retains file identity, counts, selected paths, person and omissions. The duplicate alert in 608 has two concrete choices, **Save another copy** and **Keep reviewing**, with a plain consequence. Raw JSON, source paths and hashes in explicitly original-field/receipt readers are legitimate source content, not copy to paraphrase or silently normalize.

## Five executable corrections

1. **Keep declared result form and correction status visible beside the displayed value.** In 605/607 the saved **Synthetic coded result** displays **12.00** in the same large-number hierarchy as the quantity above it, without an app-owned label identifying it as a coded value. The synthetic test name happens to disclose this; a real test name will not. Show a plain persistent label such as **Coded result · kept as reported** for that original form, and appropriate literal/structured labels for other forms. Preserve the literal value and original technical form in source details. Similarly label the corrected 13.25 as the **Reviewed result** and mark changed fields, with its **Original value: 12.00** or a directly adjacent original-field action. Do not imply that a reviewed correction changed the immutable original. This request concerns presentation, not a claim that history currently performs scalar arithmetic on the coded result.

2. **Make the unchecked coverage gate visibly unavailable.** In 609-coverage, the acknowledgement switch is off, but **Continue** has the same saturated teal/white appearance as the enabled **Review results** in 609-person. Apply a clear disabled treatment while the check is off, retain the underlying gate, and show the enabled treatment only after acknowledgement. The still does not prove whether tapping currently advances; the defect is the indistinguishable visual state.

3. **Give navigation/source actions their established teal affordance.** **File coverage details**, **Read original JSON**, **Back to coverage**, **Read person reference**, **Change person**, **Edit result**, **Original FHIR import** and **Original FHIR fields** currently read like ordinary ink text in 609/601/605. Use the existing teal action ink and an appropriate independent native chevron or return indicator where they open/return to another surface. Keep labels full width/multiline at large sizes; do not encode navigation solely through colour or make static metadata look tappable. The existing teal title-edit symbol already provides the intended distinction.

4. **Fix singular grammar and remove parser jargon from task instructions.** In 609-coverage, **“1 deletion entries · 1 request/response-only entries”** needs **“1 deletion entry · 1 request/response-only entry”**. In 609-person, **“1 result proposals”** needs **“1 result proposal”**. Use shared singular-aware counts throughout coverage/person/completion. Replace **“Choose one observation person group. Names alone do not establish identity.”** with **“Choose whose results to review. Check the original person reference; names alone do not establish identity.”** In 602, replace **“This original FHIR token stays separate from your corrections below.”** with **“This original field is kept unchanged. Corrections below apply to the reviewed result.”** Exact technical keys such as `valueQuantity` remain available in original details; a nearby plain label should explain the value form rather than asking a stranger to understand that key.

5. **Use the established secondary ink for essential editor section labels.** In 602, **Original FHIR excerpt** and **Reported result** use visibly pale grey. Sampled solid glyph RGB 134,135,140 against ground 244,248,249 yields approximately **3.35:1**. These standard-size headings distinguish immutable source from editable transcription, so use `Theme.secondary` rather than tertiary/system-grey ink. This is a scoped raster sample, not a whole-app accessibility audit. Keep disabled controls visually distinct from enabled labels.

The visible lower edges of 601/622 and 607 show content continuing beneath native scrolling/chrome. They are not evidence of a fixed crop. The full acknowledgement area, excluded-row explanation and expanded source controls still need their own settled captures before judging every word and action there.

## Provisional scorecard

Scores apply only to the shown normal-phone states. Dark, XXXL and compact are ungraded, not presumed failed.

| Applicable line | Score | Visible evidence and next scoped improvement |
|---|---:|---|
| 1 · Concept on the pixel | 4 | Literal originals, explicit unknowns and checked local review retain the factual observatory. Make declared forms/corrected values equally clear in the saved summary. |
| 2 · Not the category average | 4 | Coverage, person references and immutable source fields avoid a generic result dashboard. Preserve these distinctions beside numeric-looking coded content. |
| 3 · Not this skill's average | 4 | Cool white/deep teal and expanded display remain recognizably Lumen. Carry the existing action language into the ink-only navigation rows. |
| 4 · Hierarchy | 3 | Headings and completion lead well, but the coded value looks quantitative and the unchecked Continue looks enabled. Close corrections 1 and 2. |
| 5 · Typography | 4 | Normal-size display/body/source values wrap legibly, with no demonstrated internal truncation. Retain these full strings at actual XXXL and compact; those are evidence gates, not a shrinking request. |
| 6 · Colour | 3 | Owned teal is strong, but action rows lose its role and essential source/edit headings use pale grey. Close corrections 3 and 5; dark remains pending. |
| 7 · Richness and joy | 3 | Useful source content and a restrained native review surface suit this dense utility extension. No decorative imagery or new concept is requested. |
| 8 · Rhythm and space | 4 | Source/editor groups, person choices and the completion action have coherent spacing. Preserve this grouping when the new labels wrap at larger sizes. |
| 9 · Finish and craft | 3 | Complete source values and a fitted completion action are good; unresolved value-form/gate/contrast inconsistencies prevent sign-off. Close the concrete corrections rather than adding ornament. |
| 10 · Native fluency | 3 | Glass navigation, native forms/switches and the two-choice alert are coherent, but ink-only actions and the enabled-looking gate weaken affordance. Close corrections 2 and 3. |
| 12 · Copy | 3 | Unknown collection and duplicate/save wording are factual. Singular errors and “observation person group”/“FHIR token” need the concrete rewrites above. |

**38/55; 5/11 lines (45.5%) at 4 or above.** No 5 is claimed. Signature, motion, icon, onboarding, paywall and store work are outside scope; portfolio-only richness is not a requirement for closing this utility addition.

## Missing evidence for the next round

- Actual dark, Accessibility XXXL and 375×667 layouts, including full inclusion/acknowledgement/footer and completion actions.
- Full-size long-field editing with the software keyboard, reachable Select all/Done, exact replacement and return; long original-field reader/paging without loss.
- Settled excluded/cancelled-row explanation, corrected-versus-original labels and acknowledgement reset after correction/person changes.
- Complete source-only receipt after removal/relaunch and exact-file duplicate behavior for that state.
- Any coverage/person reference details, original JSON/omission readers or failure/progress states intended for final acceptance that are not shown in this set. They are unshown here, not scored as broken.

**Not done by the stop rule in `critique.md`.** This is only round 1, the required score thresholds are not met, concrete defects remain and the appearance/compact set is incomplete. No physical-device, VoiceOver, clinical/FHIR-conformance, provider-authorship or DOM-scan proof is inferred from these captures.
