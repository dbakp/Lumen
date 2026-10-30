# Lumen design review

App Designer Pro supplied by the user was applied. Brief assumptions were self-authored under the user's “Go” instruction. One independent critic reviewed the same app across all rounds. Studies use explicitly labelled sample data. Native screenshots and integration results are reported separately in docs/VERIFICATION.md.

| Rubric | R1 | R2 | R3 |
|---|---:|---:|---:|
| Concept on the pixel | 3 | 4 | 4 |
| Category distinction | 4 | 4 | 4 |
| Skill distinction | 3 | 4 | 4 |
| Hierarchy | 3 | 4 | 4 |
| Typography | 3 | 3 | 4 |
| Colour | 4 | 4 | 4 |
| Richness | 3 | 3 | 3 |
| Rhythm | 3 | 4 | 4 |
| Finish | 3 | 4 | 4 |
| Native fluency (static grammar) | 2 | 4 | 4 |
| Signature | 2 | 4 | 4 |
| Copy | 3 | 4 | 4 |
| Motion (strips) | — | — | 3 provisional |

## Round 1 → 2
- Replaced decorative arc with three labelled recorded/missing signals.
- Replaced text-only serif tabs with system sans and one SVG icon family; removed tabs on modal frames.
- Reduced page-title competition with contextual recommendation and clipped the scrolling viewport above navigation.
- Gave document objects restrained depth.
- Changed “Make room for how you feel” to “Keep today’s plan flexible”; made assistant follow-up refer to recorded headache.
- Signature keeps the ongoing headache and adds the new energy/stress evidence.

Critic: static study meets the stop rule, 10/12 lines at 4; runtime, motion and fidelity not established by mockups.

## Round 2 → 3
- Explicit SF font for signal labels; added “recorded” to avoid implying goal achievement.
- Removed repeated copy; changed first-run supporting headline.
- Added “Check-in saved” to the signature's final frame.
- Refined small-phone clipping. Standard and small new-design sets: zero FAILs.
- Warning: 24pt check-in title is a deliberate dense form, accepted by critic.
- Warning: standard signature-3 source includes text beyond its clipped scroll view. It is not visible in the rendered screen; native layout uses a real ScrollView. Small layouts pass cleanly.

Critic: typography improves to 4; static stop rule remains met. Richness remains 3, not a portfolio-level claim.

## Motion
Eight-second local design studies, 12 fps, stationary hardware, one saved-state confirmation. MP4 export uses AVFoundation because ffmpeg is absent; six-frame strips were reviewed by the critic. Motion score 3 provisional: understandable but mainly a confirmation; encoded seam/pacing is not established from strips. The hero's stage paragraph contrast defect was corrected by scoping the stage caption style to direct children, then re-exported. Reduced-motion styles freeze the confirmation.

## Before/after and fidelity
before-after.html reconstructs the original dark readiness-ring layout from the repository source. It is not a screenshot of the original running app. Its old-side scan failures (greeting/default dashboard) are historical audit evidence, not failures in the new set. Original feature destinations, Watch, widgets, data formats and onboarding are retained in code; native flow tests verify access separately.

## Scope and limits
No paywall or subscription was introduced. No store-publishing assets were requested. iPhone is the shipping platform; Watch styling remains its native companion. No Android imitation is produced. The final app icon has default, dark and tinted assets. No clinical validation, App Store approval or physical-device feel is inferred from these studies.

## Final critic sign-off
Hero contrast correction was reviewed in the updated strip and a frame actually decoded from the MP4. Final motion 3/5; 11 of 13 applicable lines at 4 or above, none below 3. Critic: “Done by the design stop rule.” Both MP4s decode as 8.0 seconds. Endpoint PNGs: living exactly identical; hero differs by one channel in one pixel (mean absolute difference 0.000000267/255), an effectively matching visual seam. 12 fps previews do not prove native animation smoothness. Native early-flow screenshots are in Design/native/r1; later verification is tracked separately.

## Native fidelity review
The independent critic scored the captured native core flows 4/5. Its three concrete findings (adjacent symptom actions, duplicate-save affordance, clipped arc strokes) were fixed. Final source passed the full iPhone smoke scenario in 129.111 seconds, zero failures; final screenshots in Design/native/final. No new clinical or real-device claims are inferred.

## Follow-through batches review
One independent critic reviewed the new native personal-context, plan editor/agenda, conversation history, Insights and appointment-summary captures. Initial findings: literal block Markdown, repetitive empty metric cards, duplicate plan actions, weak link affordances and singular/plural copy. All were fixed. The final editor, agenda, document and empty-state screenshots were reviewed again; the critic confirmed the requested fixes landed and found no further high-impact visible defects. Captures: Design/native/batches. Real-device and accessibility-size behavior were not inferred from screenshots. Expanded integration scenario: 168.984 seconds, zero failures; actual logic checks: 48.

## Backup and restore review
The same independent App Designer Pro critic reviewed native backup home, preview and restored states. Hierarchy, native fidelity and privacy clarity: 4/5. Conflict clarity initially 3/5: “Existing records” and “when IDs match” were ambiguous/technical. Changed to “Already on this iPhone” and “Your current versions of these records will be kept.” A second review of the final native capture raised conflict clarity to 4/5 and found no remaining high-impact visual defects. Final native flow passed in 224.047 seconds, zero failures; 68 logic checks pass. Files/iCloud transfer, second-device restoration and accessibility scaling remain unverified.

## Health import progress review
The same independent critic reviewed actual native XML-progress, cancelled, CSV-preview and persisted-history captures. Initial progress/cancel usability: 2/5, because Cancel was behind the floating tab bar. Cancel import now stays in the navigation toolbar; spinner and reviewed-record count share a compact row. Corrected “1 days” in preview/history. Final native captures were reviewed again: progress/cancel usability improved to 4/5, preview clarity and native fidelity stayed 4/5, and no high-impact visible findings remained. Final file-backed native scenario: 85.097 seconds, zero failures; 74 logic checks. Captures demonstrate simulator behavior, not real-device performance.

## Direct ZIP import review
The same independent critic reviewed actual native invalid-ZIP recovery, measurement preview, persisted receipt and bundled license screens. Error clarity/native fidelity/license readability: 4/5. Preview clarity initially 3/5 because zero skipped records could imply the entire archive was imported. Added “Imports supported measurements. Clinical documents and workout routes aren’t included. Add PDF or text records separately in Library.” directly above Import. A second review confirmed it is visible/readable and raised preview clarity to 4/5 with no high-impact findings left. Native test explicitly checks visibility. Final combined suite: 3 scenarios, zero failures/no skips in 483.552 seconds; logic:106 checks. Captures: Design/native/zip. No real-device, iCloud or maximum-size performance claim is inferred.

## Workout and additional-signal review
The same independent App Designer Pro critic reviewed actual native import preview, workout detail/persistence and oxygen evidence captures. Preview hierarchy/native fidelity/copy were 4/5; workout affordances and evidence readability were initially 3/5. Required fixes: remove chevrons from read-only workout values, show exact recorded value/date and a readable record list, and display BMI without a unit. Round-2 native captures in Design/native/workouts/r2 confirm all fixes, including singular workout copy and human-readable metric labels. The same critic raised workout affordances and evidence readability to 4/5, confirmed copy at 4/5, and found no remaining high-impact visible defects. Done by the skill stop rule for this scoped addition. Final native suite: two tests, zero failures/no skips, 339.440 seconds; 140 logic checks. Synthetic simulator data only.

## Conversational health-log review
The same independent App Designer Pro critic reviewed six initial native captures. Hierarchy/native fidelity were 4/5; confirmation clarity, copy and saved-vs-unsaved clarity were 3/5. Requested fixes: persistent units after values are entered, upfront saved/pending and closing behavior, protection for edited drafts on Close/swipe, and separate empty optional notes instead of copying the entire source statement into every note.

Round 3 captures in Design/native/chat-logs/r3 implement all requests. Water keeps its ml label, workout fields keep min/kcal labels, closing has explicit Discard/Keep choices, notes start empty, and provenance preserves the source. The reviewer confirmed all fixes, raised the affected lines to 4/5, and found no remaining high-impact visual defects in all eight captures. Done by the skill stop rule for this scoped addition. An intermediate native test exposed an iOS confirmation popover that omitted the cancel action; a two-choice alert fixed it. The successful revised scenario passed in 209.463 seconds and the full daily/backup journey separately passed in 252.272 seconds. The final extension passed in 144.131 seconds and verified that a subsequent assistant reply uses the saved symptom. Final captures are in Design/native/chat-logs/r4; no product design changed from reviewed round 3. These are synthetic simulator captures; provider inference, accessibility scaling and physical-device behavior remain separate gates.


## Batch 9: current evidence and local corrections · round 1

App Designer Pro was supplied on this computer and read from the attached archive. One continuing independent critic reviewed six actual iPhone simulator captures: missing Activity, current readings, missing steps, recorded imported zero, dark recorded zero, and a saved water correction. The editor, workout deletion and largest text size were not yet evidenced, so this round was explicitly partial and not done.

Scores: concept 4, category distinction 4, skill distinction 4, hierarchy 4, typography 4, colour 4, richness 3, rhythm 3, finish 3, native fluency 3, copy 3. Signature, motion, selling assets and unshown flows were unscored. This does not meet the scoped stop rule.

Five required changes, all accepted: give Delete entry native red/trash treatment; collapse an empty weekly energy chart to “No workout energy recorded this week.”; remove irrelevant missing Health check-time copy from imported evidence; use source-specific missing-reading copy and remove repeated generic Health boilerplate; replace “Prepared by: Local draft” with “Prepared on this iPhone”. Combined-source values remain visible, while a single source no longer repeats the hero number. The weekly chart now uses known energy records only and preserves explicit zeros without filling other days. Rerendering and the next review remain pending.

Native rendering is the evidence for these additions. No browser DOM scan or new direction exploration is claimed; the established direction and native implementation are preserved. Uploaded skill resources are not included in the repository.


### Batch 9 · round 2

The same critic reviewed all 18 actual captures in `Design/native/confidence/r2`, including both correction forms, saved values, both delete alerts, retained source wording, post-delete unknown, dark mode and actual Accessibility XXXL layouts. All five round-1 requests landed. Scores: concept 4, category 4, skill distinction 4, hierarchy 4, typography 4, colour 4, richness 3, rhythm 4, finish 4, native fluency 4, copy 3. Nine of eleven lines were at 4, but Copy did not meet the required 4. Not done; the external managed-workout capture was still pending.

Accepted fixes: “this week” becomes “in the past 7 days” to match the rolling window; the standalone second “Walk” gets a persistent “Workout name” label; the correction toolbar action becomes “Save” and its accessibility-size title becomes “Water” or “Workout”, avoiding the visible “Edit w…” truncation. No request was declined. The initial amount-entry check was also corrected to select the whole value before replacing it: an intermediate capture showed 3520, rather than 35, because the test had inserted at the beginning. The completed corrected native scenario passed in 287.121 seconds. These preliminary captures are retained as review history; the next captures will verify the remaining wording and toolbar changes.


### Batch 9 · round 3 sign-off

The same independent critic opened all 21 native captures in `Design/native/confidence/r3`. The seven-day wording, persistent workout name, shorter Save action and complete XXXL Water title all landed. Source-managed details in 91/92/95 now show the source, named export, reported/end-time qualifications and the full local-correction boundary. The native assertion that edit/delete controls are absent is separate behavioral evidence.

| Rubric | R1 | R2 | R3 |
|---|---:|---:|---:|
| Concept on the pixel | 4 | 4 | 4 |
| Category distinction | 4 | 4 | 4 |
| Skill distinction | 4 | 4 | 4 |
| Hierarchy | 4 | 4 | 4 |
| Typography | 4 | 4 | 4 |
| Colour | 4 | 4 | 4 |
| Richness | 3 | 3 | 3 |
| Rhythm and space | 3 | 4 | 4 |
| Finish and craft | 3 | 4 | 4 |
| Native fluency | 3 | 4 | 4 |
| Copy | 3 | 3 | 4 |

The critic found no remaining concrete visual or copy defects and confirmed **Done by the skill stop rule**: 10/11 applicable lines at 4, none below 3, with Concept, Finish, Native fluency and Copy at 4. Richness remains 3; no portfolio-level score is claimed. All substantive asks were accepted. The solid asset-pair contrast calculations are in DIRECTION.md; they do not measure every system/translucent state. Native screenshots establish the shown layouts, including actual Accessibility XXXL. They do not establish VoiceOver, live HealthKit/provider reliability, clinical validity or physical-device feel. No new motion, store assets or browser-DOM scan is claimed for this native addition.

## Batch 10: Food, Sleep and companion evidence · round 1

The same independent App Designer Pro critic reviewed five actual iPhone captures in `Design/native/retained/r1`: missing Food/water, undo returning to missing, missing Sleep, one manual night, and partial imported food zeros with unknown fat. Scores: Concept 4, Category 4, Skill distinction 4, Hierarchy 4, Typography 4, Colour 4, Richness 3, Rhythm 4, Finish 4, Native fluency 4, Copy 3. Not done: Copy was below the required 4, and companion/dark/large-text evidence was pending.

All five asks were accepted: singular entry grammar; rounded and explicitly estimated macro/energy/water targets; an actual saved-entry denominator and recorded-day coverage; teal source navigation with chevrons; plain sleep-coverage wording and an explicit quick-undo Health outcome. The outcome is based on the actual deletion call, with no blanket permission/synchronization claim.

### Batch 10 · round 2

The critic opened all eight corrected iPhone captures in `Design/native/retained/r2`, including actual dark Food and Accessibility XXXL. Every iPhone ask landed; the scoped iPhone scores are now all 4 except Richness 3. Large Sleep remained pending.

The same round opened seven first-pass companion captures in `Design/native/retained/companion-r1`. Overall scores: Concept 3, Category 3, Skill distinction 4, Hierarchy 3, Typography 3, Colour 4, Richness 3, Rhythm 4, Finish 3, Native fluency 4, Copy 3. Not done. Required changes: withhold and recapture the unsupported default readiness score and name Readiness estimate; label all unknown Food/Water/Activity values; round Watch targets consistently; show actual snapshot dates/times; replace unexplained dashes and Model window wording. All were accepted. The iPhone's pure readiness gate now excludes a lone sleep total when none of the heuristic's contributing inputs exists.

The Watch denial alert and unchanged total were clearly readable. These captures establish rendered simulator behavior, not physical-device writes or timely fresh WatchConnectivity delivery. The widget was installed on the simulator Home Screen and read the actual iPhone shared cache. Its round-1 score is superseded only when the corrected source is recaptured. Final source/captures and the next review are pending; no sign-off is claimed here.

### Batch 10 · round 3 sign-off

The same critic opened all **12 final iPhone/widget captures** in `Design/native/retained/r5` and **nine Watch captures** in `Design/native/retained/companion-r2`. All requests landed; no remaining concrete defects or awkward strings were found in the visible content.

| Rubric | R1 iPhone | R2 overall | R3 final |
|---|---:|---:|---:|
| Concept on the pixel | 4 | 3 | 4 |
| Category distinction | 4 | 3 | 4 |
| Skill distinction | 4 | 4 | 4 |
| Hierarchy | 4 | 3 | 4 |
| Typography | 4 | 3 | 4 |
| Colour | 4 | 4 | 4 |
| Richness | 3 | 3 | 3 |
| Rhythm and space | 4 | 4 | 4 |
| Finish and craft | 4 | 3 | 4 |
| Native fluency | 4 | 4 | 4 |
| Copy | 3 | 3 | 4 |

The final medium widget names Readiness estimate, withholds its unsupported score/ring, and fits the full snapshot date/time. Watch missing/zero rows retain names and timestamps; Tonight uses explicit unavailable timing text; missing Readiness fits “More evidence needed”. The save-error alert and unchanged Watch-local water are clear. Actual XXXL Food/Sleep reflow, recorded-hour history coverage and both manual-editor dates are visible. The history transition image and the clipped intermediate widget/readiness frames remain review history, not final evidence.

**Done by the skill stop rule:** 10/11 applicable lines at 4, none below 3, with Concept, Finish, Native fluency and Copy at 4. Richness remains 3. No further polish was requested and no UI change was made after this sign-off. This covers the shown synthetic simulator layouts, installed medium widget and Watch pages; unseen widget/complication families, VoiceOver, physical-device feel and synchronization guarantees are not inferred. No new motion, store set, paid assets or browser-DOM scan is claimed.

## Batch 11: encrypted backups · round 1

The same continuing independent App Designer Pro critic inspected all ten actual native captures in `Design/native/backups/r1`. This extends the established iPhone direction. No new concepts, paywall, paid imagery, store assets or reel are in scope. The native captures do not show filled secure-field contents; no replacement text was composited into the images. Frame 111 was captured during presentation and is review history, not evidence of the settled empty form.

| Rubric | R1 |
|---|---:|
| Concept on the pixel | 4 |
| Category distinction | 4 |
| Skill distinction | 4 |
| Hierarchy | 4 |
| Typography | 4 |
| Colour | 4 |
| Richness | 3 |
| Rhythm and space | 4 |
| Finish and craft | 3 |
| Native fluency | 3 |
| Copy | 3 |

**Not done.** All four concrete findings were accepted: persistent Password/Repeat password labels outside secure contents; a visible non-committing restore choice; action-specific error titles with plain uncertainty about password versus file damage; and Encrypted backup ready to save with Save or share backup as the first action. The quoted “failed its integrity check” became “The password may be incorrect or this file may be damaged.” “Couldn’t complete backup” is replaced by create/open/unlock/restore-specific titles. Explanatory footers now use the established secondary ink. The actual empty form, complete restore options, legacy file, large-file progress/cancellation, dark appearance and actual XXXL remain to be reviewed in round 2.

### Batch 11 · round 2

The critic opened all 27 round-2 PNGs in `Design/native/backups/r2`, including native Files/share controls, actual large-file cancellation/restore, dark mode and actual Accessibility XXXL. All round-1 requests landed. Scores: Concept 4, Category 4, Skill distinction 4, Hierarchy 4, Typography 4, Colour 4, Richness 3, Rhythm 4, Finish 4, Native fluency 4, Copy 4. **Done by the stop rule** for the shown layouts: 10/11 at 4, none below 3; no portfolio-level 5 is claimed.

Two concrete after-done corrections were accepted: Library's “0 of 1 steps completed” becomes “0 of 1 step completed”, and preview integers use locale-aware grouping to match progress counts (100.000 in the shown locale). Recapture and a final critic check remain required for those changes. The accepted XXXL layout is scrollable: continued text below the viewport is not treated as a collision, and navigation/Cancel, labels and wrapped actions remain readable. The default filename/unlock/error frames were omitted in R2 pending a final regression after fixing a UTC filename-date mismatch; the system share and reopened-file captures already verify the local date. Rare validation/size/storage errors are production-logic coverage, not additional visually scored native states.

### Batch 11 · round 3 sign-off

The same critic opened all four corrected captures in `Design/native/backups/r3`: locale-aware 100.000, “0 of 1 step completed”, and the default locked/error states using the local filename date 2026-10-30. Both after-done corrections landed. No new concrete pixel/copy defects were found. Scores remain 4 across the applicable lines except Richness 3: **10/11 at 4+, Done by the skill stop rule**. No subsequent visual change is planned. Accessibility identifiers improve test stability without changing these pixels; VoiceOver itself remains unverified. The added large outgoing-export/reopen runtime check is a separate verification gate, not inferred from still images.

Supplemental round-3 runtime frames 138/139 were also opened by the same critic. The ready state retains its save-first hierarchy; the reopened archive shows 430 · 430 meals/photos, 100.001 water logs and 100.433 matching records without collisions. No new concrete defects; prior scores and Done remain. These figures are synthetic native data, with runtime/file-size proof recorded separately in VERIFICATION.md.

## Batch 12 · Health updates between visits · round 1

Same continuing independent App Designer Pro critic; actual SwiftUI captures in `Design/native/health-sync/r1` (160–164). No new direction, icon, paywall or motion signature is claimed. The native preference/persistence scenario passes separately in 122.148 seconds; this is not background-delivery evidence. No browser-DOM scan is claimed.

| Line | Score |
|---|---:|
| Concept | 4 |
| Category distinction | 4 |
| Skill distinction | 4 |
| Hierarchy | 4 |
| Typography | 3 |
| Colour | 3 |
| Richness | 3 |
| Rhythm | 3 |
| Finish | 3 |
| Native fluency | 4 |
| Copy | 3 |

Not done. The critic requested four concrete changes: stack the largest-text label above the switch to remove “Back-ground”; remove “Background delivery needs verification on a physical iPhone.” from the product form; use established secondary ink for status/privacy information; and replace “Delivery / Updates are off” with explicit background status. The critic retained the timing/unlock explanation and the distinction between enabled preference and disconnected Health access.

Changes prepared for round 2: full-width accessible label with the switch beneath it; vertical status at accessibility sizes; themed status/privacy ink; “Background status / Off” and “Waiting for Apple Health connection”; engineering verification detail moved to documentation. Round 2 will include scrolled large-type status and timing text as requested. Physical delivery and VoiceOver behavior remain outside pixel evidence.

## Batch 12 · round 2

The same critic opened all seven `Design/native/health-sync/r2` captures. The revised preference case passes individually in **125.681 seconds** in `/tmp/LumenBatch12HealthR6.xcresult`; that bundle also contains a failing system-authorization test and is not a passing combined suite. The earlier passing preference run was 122.148 seconds. Switch tests now tap the actual nested native switch rather than the wide accessibility wrapper.

Scores: Concept 4, Category distinction 4, Skill distinction 4, Hierarchy 4, Typography 4, Colour 4, Richness 3, Rhythm 4, Finish 4, Native fluency 4, Copy 4. **Done by the scoped stop rule.** All four requests landed; no concrete visible defect remains. The critic explicitly limits the XXXL value claim to the shown Off state; the longer awaiting-connection value is shown at normal size and dark mode. Runtime authorization and background delivery remain separate from the pixel review.

## Batch 12 · round 3, expanded runtime and onboarding copy

The critic inspected the five `Design/native/health-sync/r3` captures after the real foreground Health flow passed in 88.726 seconds, and onboarding/erase plus the full daily/backup regression passed together in 285.321 seconds. The native read-back held two 414-byte query anchors, zero sleep/workout records and no pending application. These empty-query results are not sample-delivery or background proof.

The background-control layout approval stood, but **Copy fell to 3**, so the expanded scope was not done. The critic requested conditional onboarding benefit language, check terminology for empty-query timestamps, a normal “Check Health now” action with retry reserved for errors, and a privacy footer that allows optional sharing. Round-4 changes use “Sleep readings available in Apple Health,” “Heart-rate readings for daily context,” and “Use available age, height and weight readings”; “Health check triggered,” “Sleep & workout check,” and “Check Health now”; and “Stored on this iPhone. You choose what to share.” The revised footer uses established secondary ink. Final captures and sign-off follow after the focused native rerun. The earlier copy-only capture run was deliberately stopped to apply that footer contrast refinement and is not claimed as passing evidence.

## Batch 12 · round 4 final sign-off

The same critic opened all **12** final `Design/native/health-sync/r4` PNGs at full size after the final three-case native suite passed with zero failures/skips in **247.928 seconds**. All requests landed: available-reading language, access-request versus empty-result separation, check terminology, normal check action, optional-sharing privacy copy and stronger footer ink. Native scroll edges are accepted; no unseen XXXL awaiting-connection value or VoiceOver behavior is claimed.

| Line | Final score |
|---|---:|
| Concept | 4 |
| Category distinction | 4 |
| Skill distinction | 4 |
| Hierarchy | 4 |
| Typography | 4 |
| Colour | 4 |
| Richness | 3 |
| Rhythm | 4 |
| Finish | 4 |
| Native fluency | 4 |
| Copy | 4 |

**Done by the scoped stop rule**, no remaining concrete visible defect. No app UI changed after this sign-off. Physical background delivery and actual Health sample receipt remain separate verification gates. The earlier rounds remain review history; the gallery now points to round 4.

## Batch 13 · scanned record review · round 1

The same continuing independent App Designer Pro critic inspected all eight actual native light-mode captures in `Design/native/records/r1`. This was explicitly partial evidence: source/original comparison, dark/XXXL, saved provenance, duplicate handling and the passing save/relaunch flow were still pending. Scores: Concept 4; Category distinction 4; Skill distinction 4; Hierarchy 3; Typography 4; Colour 3; Richness 3; Rhythm 3; Finish 3; Native fluency 3; Copy 3. Not done by the stop rule.

All five concrete asks were accepted: focus/scroll the active editor with a native keyboard Done action and end editing on acknowledgement; group Page image/Open original immediately above the correction surface with teal action treatment; visibly disable bounded pager arrows; change the acknowledgement to “I checked all included pages against the original”; and simplify the locked-file message to “This PDF is locked. Choose an unlocked copy, then try again.” Accessibility-size switches also stack their full labels above the controls, following the established Health form pattern. Edited-draft and source-replacement prompts use explicit two-choice alerts.

The critic correctly called out the visible synthetic “12.5 ma/L” recognition error. Raw output is retained for correction, not silently normalised. The native scenario now corrects both included pages to the original unit before saving. The original R1 stills and the failed native test are review history, not claims of successful saving, accuracy or final consent visibility. Current guarded bindings fix the runtime close crash; subsequent native evidence must establish it. No new concept, icon, paywall, motion set or browser-DOM scan is claimed for this extension.

## Batch 13 · round 2

The same critic inspected all 19 `Design/native/records/r2` captures. Eighteen are exported XCTest captures; `196-record-original.png` is a direct simulator capture while the original-PDF test waited for the older Done label. Native recovery, corrected two-page save/relaunch/duplicate and the daily/backup regression pass individually on that source. The presentation test fails on the Quick Look selector, so the combined suite is not counted as passing. The raw original visibly says mg/L and the saved/reopened body retains both manually corrected mg/L entries.

The critic confirmed all five round-1 asks landed. Scores: Concept 4; Category distinction 4; Skill distinction 4; Hierarchy 4; Typography 3; Colour 4; Richness 3; Rhythm 4; Finish 3; Native fluency 3; Copy 4. Not done: the largest source-picker label was vertically cropped, floating keyboard Done overlapped retention copy, and the dark TextEditor retained a square charcoal inner surface.

All three concrete fixes are accepted. The source chooser now has an intrinsically sized, multiline Menu label and native selection options; focused content receives 112 points of bottom clearance; and TextEditor hides its default scroll background so the rounded field owns its surface. Focused editing keeps the keyboard through scrolling until Done, page navigation or acknowledgement. Final captures must show these corrections, actual largest-size review/sharing controls, the excluded-all explanation/source-page counts, expanded Page image, native discard/source-replacement decisions and a software-keyboard state where obtainable. A software-keyboard-up state was not evidenced in round 2. Earlier stills remain review history; no physical keyboard/device/VoiceOver claim follows from them.

## Batch 13 · round 3 final visual sign-off

The same continuing independent critic inspected all 28 final PNGs and their capture-source list in `Design/native/records/r3`. All round-2 fixes landed: the source Menu label expands at actual XXXL, the retention footer clears Done with the software keyboard visible, and the dark editor uses one rounded surface. The excluded-all explanation and explicit source-page counts are visible. The final original viewer has a clear Close action and a readable PDF; native swipe/source-replacement alerts retain work; the largest acknowledgement and assistant-off controls are fully shown. Native scroll boundaries and the editable single-line title-field ellipsis are intentional, distinct from the corrected fixed-control cropping.

Final scores: Concept 4; Category distinction 4; Skill distinction 4; Hierarchy 4; Typography 4; Colour 4; Richness 3; Rhythm 4; Finish 4; Native fluency 4; Copy 4. **Done by the stop rule: 10/11 at 4+, none below 3, and all required lines at 4.** No remaining concrete visible/copy defect in the supplied scope. Physical-device feel, clinical accuracy, VoiceOver, every keyboard/device/language and unshown states remain outside these scores. No browser-DOM scan or additional icon/paywall/motion claim is made.

A subsequent nonvisual cleanup refinement registers the working folder with the Library sheet owner and removes it explicitly on dismissal. This addresses SwiftUI retaining the last closed preview beyond the view's visible lifetime. Cleanup behavior is not part of the visual score; it is independently verified by logic and native close/save checks. No layout or copy changes follow the visual sign-off. The final delivery evidence and source hashes are recorded in VERIFICATION.md.
