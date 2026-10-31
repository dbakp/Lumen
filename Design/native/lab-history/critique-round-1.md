# Batch 22 · native lab history · provisional Round 1

Independent App Designer Pro review, 31 October 2026. This is a **partial review, not batch sign-off**. No app source was edited.

## Evidence and boundary

Read `Design/DIRECTION.md` Batch 22, `docs/LAB_HISTORY.md`, and the supplied App Designer Pro critique, copy and finish references. Opened every supplied PNG at original size:

- `nativer1/530-history-record-selection.png`
- `nativer1/531-history-person-review.png`
- `nativer1/532-history-test-groups.png`
- `nativer1/unreachable-element.png`

The last image shows the series top after Dot selection. The reported journey failed because a scrolling gesture began over the fixed comparison footer. That failure is not evidence that the chart is inaccessible. No chart, complete literal-history page or comparison review is visible in these captures. No full-suite pass, source persistence, backup, physical-device, VoiceOver, clinical or browser-DOM behavior is inferred.

## What is already working

530 leads clearly with choosing records for one person. Each visible candidate has a literal record title, an explicitly unknown person label, a saved-transcription count and an Open record route. Review selection is visibly disabled at zero selected records.

531 keeps the person acknowledgement separate from the record list, shows the checked switch and an available Prepare action, and explains that source sharing settings remain unchanged. The clipped upper row is at the native scrolling/navigation edge, not evidence of a cropped row layout.

532 preserves the established expanded headline, cool ground and teal actions. Test, reported unit and laboratory stay distinct; a recorded-context disclosure is available. The selected count is factual and the single group is clearly labelled Ferritin. The series-top capture offers explicit Dot, Comma and Keep wording only choices without clinical colour or an inferred trend.

## Provisional scorecard

These scores apply only to the visible partial scope. A 4 is a scoped shipping score; unshown states receive no credit.

| Line | Score | Visible evidence and next scoped improvement |
|---|---:|---|
| 1 · Concept on the pixel | 4 | Choosing one person's records and “Results, with their sources.” make the fact/source concept legible. A complete source-linked literal-history and checked-comparison journey is still needed to assess the full concept. |
| 2 · Not the category average | 4 | Explicit person uncertainty and number interpretation avoid the usual assumed medical trend. Retain those boundaries in the unseen plot and comparison. |
| 3 · Not this skill's average | 4 | Expanded native display, cool white ground, deep ink and restrained teal carry Lumen's existing direction. No new decorative treatment is requested. |
| 4 · Hierarchy | 3 | The headings lead correctly, but the series top gives its strongest filled action to “Compare 0 results.” Make the zero/one-selection state instructional and unavailable. |
| 5 · Typography | 4 | Visible headings, literal names, unit and metadata are readable and maintain a clear scale. Actual XXXL/compact labels and the full comparison are pending. |
| 6 · Colour | 4 | The light palette is coherent; teal owns the selected interpretation and main actions. Apply that existing action treatment consistently to secondary navigation; dark mode is unreviewed. |
| 7 · Richness and joy | 3 | The current evidence is restrained native text and controls. The useful visual richness should come from the neutral, correctly labelled plot and literal data, not added imagery. Keep this honest 3 until that evidence is visible. |
| 8 · Rhythm and space | 4 | Record groups and disclosures have clear spacing and aligned leading edges. Validate the fixed footer and last rows in the pending complete/large/compact captures. |
| 9 · Finish and craft | 3 | The invalid-looking comparison action and body-coloured navigation leave avoidable ambiguity. Resolve requests 1–2 below and show the settled follow-up. |
| 10 · Native fluency | 3 | Native glass navigation, switch and disclosure grammar are present. The active-looking zero-selection action needs a clear unavailable state; full native scrolling and keyboard evidence remain pending. |
| 12 · Copy | 3 | Unknown identity and sharing wording are factual. “Compare 0 results,” “Group separators are unsupported” and the source-check sentence need the concrete wording changes below. |

**39/55; 6/11 lines (54.5%) at 4 or above.** Signature, motion, conversion and store-feature work are outside this addition's scope. No request to pursue portfolio-only embellishment is made.

## Five executable changes, in priority order

1. **Make comparison availability explain the required selection.** In the series screen, replace the active-looking filled “Compare 0 results” state with an instruction such as **Select 2 results**, and keep the comparison action unavailable until exactly two results are selected. Removing the empty fixed footer and placing the instruction beside the literal-result selection UI is a valid solution; an empty disabled fixed footer is not required. At one selected result, expose **1 of 2 selected**. With two selected results, enable **Compare 2 results**. The still establishes visual ambiguity, not whether the current button accepts a tap.
2. **Give secondary navigation the established action treatment.** Use the existing teal action ink for **Open record** in 530/531 and **All tests** in the series top. Give All tests a native back/chevron affordance if it returns to the test list. These currently look like body labels beside otherwise teal actions such as View history and Choose records.
3. **Replace implementation-led source-check copy.** In 530, change **“Preparation checks that each chosen source still matches its lab review.”** to **“Lumen checks each source for changes since its lab review.”** Keep the current change-blocking behavior and review route; the copy should describe the check rather than the preparation implementation.
4. **Explain decimal punctuation in ordinary language.** Replace **“Choose the reports' decimal mark, or keep wording only. Group separators are unsupported.”** with **“Choose the decimal mark used in these reports, or keep wording only. Numbers with thousands separators stay as wording.”** Keep the literal Dot/Comma examples and do not guess punctuation or strip grouping characters.
5. **Name the selection limit as a limit.** In 530, replace **“0 of 10 records selected”** with **“0 records selected · up to 10”**, using singular-aware selected counts. The existing phrase can read as ten available records rather than the maximum allowed selection.

## Missing coverage for Round 2

- Record-title search, selected state, ten-record boundary and paging; all candidates and selected records remaining reachable.
- Person acknowledgement off/disabled preparation, known and unknown person labels, actual local preparation/progress/Cancel, and changed/missing/invalid-source recovery.
- Expanded recorded context and separate exact-context groups, including missing context labels and groups with the same test name.
- Settled neutral plot with axes, literal labels and date window; Dot, Comma and wording-only outcomes; specific reasons for qualified, undated, unsupported or duplicate values not plotting; complete paged literal history and source/open-record routes.
- Zero/one/two result-selection states, selection across groups, full comparison source review, unknown/equal-day ordering, arithmetic or its precise unavailable reason, unchecked/checked acknowledgement and reset after changes.
- Checked Save, completion, sharing-off independent snapshot, relaunch and later source changed/deleted/current states. Backup behavior is a separate runtime gate.
- Actual dark, Accessibility XXXL and compact-phone captures, including complete long labels, footer clearance, final rows and relevant keyboard states.

Normal content continuing beyond a native viewport is not itself clipping. The next round should show the named content after deliberate scrolling rather than shrink it into one frame. Corrected scrolling gestures and a passing native flow would support behavior, but they do not replace the requested pixel evidence.

**Not done by the stop rule in critique.md.** This is the first partial round, concrete requests remain, the applicable score threshold is not met, and the complete native comparison flow is unreviewed.
