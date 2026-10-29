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
