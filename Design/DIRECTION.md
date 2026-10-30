# Lumen direction

## Brief (self-authored from the user's go-ahead)
A private, native iPhone health companion. First ten seconds: understand what matters today and record how you feel. Light first; precise, humane, luminous. Keep the name, Apple Health, Watch, widgets, nutrition, activity, sleep, sounds, trends, local storage and optional AI providers. No subscription is introduced.

## Current app
The original core is a dark readiness ring, greeting, boxed focus list and four equal metric tiles. Keep all existing data and feature destinations. Lose forced dark mode, generic recurring notifications, unsupported certainty about missing logs. New tabs: Today, Journal, Assistant, Library. Sleep, Activity and Food remain accessible from Today. New tabs are deliberate navigation decisions made under the requested redesign scope.

## Exploration
1. Lumen is a daylight observatory (place): cool white, SF Pro Expanded, teal enamel and a readable daily signal arc. Selected: puts context and action before a score, with room for human symptoms.
2. Lumen is a field guide (printed): midnight blue, Georgia serif, amber annotated rhythm lines. Rejected: reading feels thoughtful but dark-first contradicts the brief.
3. Lumen is a tide pool (nature): saturated blue, rounded display, crisp illustrated ripples. Rejected: playful and memorable, but a colour field competes with clinical records.
See explore.html and shots/explore. No paid image generation.

## The bar
Native iOS navigation, one focal headline, useful negative space and clear source labels. No invented measurements, testimonials or clinical validation. The demo exploration is explicitly labelled sample data.

## Category default refused
Dark recovery dashboards, purple AI sparkles, cream-and-sage wellness, unexplained readiness scores. A single daily narrative is the hero; evidence sits beside each inference. No generic cheering or food guilt.

## Tokens
Any / dark: ground #F4F8F9 / #101C21; surface #FFFFFF / #1C2C33; raised #E7F0F2 / #263C45; ink #17333C / #ECF5F6; secondary #4F6871 / #ACC2C8; tertiary #627B84 / #91ABB4; rule #D7E4E8 / #35505A. Action teal #006C74 / #71D3D5, on-accent white / #102D33. Sleep blue #395B9A; activity rust #B04B31; food ochre #8A631E; water blue #176992; symptom rose #A33755. Hues belong to these domains, never random decoration.
Display: SF Pro Expanded bold, 34pt scaled, tracking -1. UI SF Pro: 28/22/17/15/13/11 with regular and bold contrast. Margin 24; radii 16/24/32; spacing 4/8/12/16/24/32/48. Glass is reserved for system navigation. Dynamic Type and Reduce Motion respected.

## Richness
An observatory's readable arcs: a crisp semicircle showing sleep, movement and nourishment as separate labelled signals. The arc is a data illustration, not a made-up wellness score. Teal briefing object, white journal sheets, quiet raised navigation.

## Voice
A thoughtful companion speaking plainly. (1) Say what was recorded and when. (2) Separate an observation from a possible explanation. (3) Offer one small next step without diagnosing or prescribing. Unknown is unknown; missing food logs never prove fasting.

## Content
Today: date, Your day, in context; contextual headline and reason; Why this; Log how you feel; sleep, activity, food links; water quick log; today's timeline; connections.
Journal: symptoms, check-ins and a merged daily timeline. Log symptom: location, severity, onset, duration, description, triggers, resolution. Check-in: energy, mood, stress and note.
Assistant: context availability, active symptoms, user question, grounded response, save to Library. Generated plans are saved automatically and remain editable drafts.
Library: plans, notes, imported records, search and type filters; document detail with checklist, Markdown share, edit and delete. Weekly review includes counts and coverage, never causal conclusions.
Connections: Apple Health, Strava through existing service, import XML/CSV/JSON, preview before commit, source history, privacy and reminder preferences.

## Signature
Log → symptoms sheet → save: light haptic, sheet closes, daily narrative updates and timeline gains the event. A 250ms spring only on state change. Reduce Motion: immediate replacement. New symptoms reduce exercise pressure and suppress movement nudges.

## Promises
Local storage; explicit consent before imported document text enters cloud AI; no automatic third-party connections; export and erase include the new domains. Notifications are optional, capped, quiet overnight and rebuilt from current context, with no recurring generic schedule. Background delivery cannot re-evaluate HealthKit unless the app runs; explain this in settings.

## Batch 9 content and interaction

Continue the selected daylight-observatory direction. App Designer Pro was supplied again on 29 October 2026. This is an extension of the existing native app; the previous three concepts, palette, icon, navigation and signature remain the design contract.

- Today: “No activity reading” / a recorded amount including “0 steps”; food shows “No food reading” / “Reading available” / meal count; water shows “Not recorded” or a recorded amount. “Review today's readings” opens the evidence list. Recorded-zero signals count as recorded in the arc.
- Today's readings: “What was recorded?”; “A zero is a reading. Missing data stays unknown.” Sections: Sleep and movement, Heart and body, Food and water. Each metric opens its own details. Values and sources come from the shared resolver, never demonstration data.
- Reading details: one prominent value or “Not recorded”, the actual day, selected recorded/imported/cached sources and their periods, estimate labels, and the last Apple Health check outcome/time when available. Daily imports say sample times are unavailable. Empty queries keep read access unknown. Query windows never stand in for latest sample times.
- Water/workout details: “Edit entry” for confirmed local records; “Edited” time stays separate from original confirmation. Original-message provenance remains readable. Source-managed records retain their source details and have no local edit action.
- Correction form: recorded time, persistent ml/min/kcal labels, optional notes, “Cancel”, “Save changes”. Blank energy remains unknown. “Saves this Lumen entry only. No changes are sent to Apple Health.” Edited Close/swipe asks “Discard your changes?” with “Discard changes” / “Keep editing”.
- Delete: a separate destructive action, followed by “Delete this water entry?” / “Delete this workout entry?” and “Delete entry” / “Keep entry”. “Deletes this entry from Lumen. Its original conversation and separate source records remain.”

Correction signature: edit the recorded quantity, save, return to the same entry with the new amount and an edit timestamp; the original statement remains unchanged. Today's derived totals, source evidence, reminders and assistant context refresh through the same stores. Existing state confirmation motion and reduced-motion handling apply. At accessibility sizes, metric values and row metadata stack vertically; system forms remain scrollable. Native light, dark and accessibility captures are reviewed by one independent critic. No paywall, new exploration, store assets or promotional reel are introduced in this feature batch.


Batch 9 refinement after native review: no energy readings collapse the weekly plot to one explicit sentence; Delete entry uses the native red trash treatment; single-source details avoid a duplicate amount and unrelated Health boilerplate. Preparation copy reads “Prepared on this iPhone”. A Readings toolbar link keeps evidence directly reachable at the largest text size. The category is labelled “Stand or roll hours”, reflecting qualifying clock hours rather than standing duration. Numeric fields retain the typed decimal text while validating their numeric value; invalid nonempty input is not treated as an optional blank. No tab, app-name or hero-concept change is introduced.


Batch 9 text-colour check uses the declared sRGB asset values. The inline destructive action now owns a darker red in light mode (`B3261E`) and a light red in dark mode (`FFB4AB`); its native destructive role and trash symbol remain. System alerts retain system colours. These ratios cover the listed solid colour pairs; they do not measure every translucent/system/pressed state.

| Appearance | Text / surface | Contrast |
|---|---|---:|
| light | Ink / Ground | 12.47:1 |
| light | Ink2 / Ground | 5.53:1 |
| light | ActionTeal / Ground | 5.78:1 |
| light | OnAccent / ActionTeal | 6.18:1 |
| light | DestructiveText / Ground | 6.11:1 |
| dark | Ink / Ground | 15.67:1 |
| dark | Ink2 / Ground | 9.34:1 |
| dark | ActionTeal / Ground | 9.90:1 |
| dark | OnAccent / ActionTeal | 8.29:1 |
| dark | DestructiveText / Ground | 10.22:1 |

## Batch 10 content and companion evidence

Preserve the selected direction and feature destinations. Food leads with **Recorded food energy**, an optional amount or **Not recorded**, rounded **Estimated target**, independent macro availability and a teal **Review source details** route. Water keeps **Undo quick log** separate from confirmed Journal entries and reports the actual local/Health removal outcome. No missing intake becomes a claim about fasting or unmet need.

Sleep distinguishes **Time in bed** from **Recorded sleep**. **Recorded nights** names saved-entry count, recorded days and **Saved-entry average**. An optional 14-night debt estimate is separate. **Planned bedtime** comes from profile goals unless sufficient recorded timing is available; schedule estimates are not measured alertness or melatonin. Sleep history labels its 14-day chart as recorded hours, without assigning a recovery colour to short entries.

Companions retain native Watch/widget structure. Unknown values keep their metric names. **Readiness estimate** never exposes the heuristic's starting score when no contributing evidence is available. The missing Watch state reads **More evidence needed**; stale snapshots ask the user to open Lumen on iPhone. Actual snapshot dates/times are distinct from sample times and the Watch clock. Watch-local water and the iPhone total remain separate, with a visible save failure. Tonight uses a teal field; Sleep uses a muted blue-teal field, with cyan reserved for native Watch actions/navigation. No paid assets, new direction exploration, store set or motion claim is introduced in this scoped continuation.

## Batch 11 content and backup interaction

Extend the established native direction with encrypted, file-backed backups. No new exploration, paid assets, paywall, store set or promotional motion is introduced. Home retains **Keep your history close.** Creation uses **Protect your history.**, persistent **Password** / **Repeat password** labels and an unrecoverable-password explanation. A finished file leads with **Encrypted backup ready to save** and **Save or share backup**; review remains secondary.

Unlock, preview and confirmed restore remain separate states. Errors name the failed action and explain that the password may be incorrect or the file damaged without claiming to distinguish those causes. Restore offers **Keep reviewing** beside **Restore records**. Actual item/byte progress and a reachable Cancel action cover file preparation, encryption, decoding, photo checks and restore staging. Navigation brings the active section into view. Explanatory copy uses the established secondary ink; secure contents are never replaced with mock text for capture. Review includes actual dark appearance and Accessibility XXXL captures. The original record/context signature and all feature destinations remain.

## Batch 12: Health updates between visits

Extend the existing Connections form with an opt-in Health background preference. Keep connection state, requested delivery and actual check times separate. The switch can be on while the source is still disconnected. “Background status” names its actual state; an empty Health read never proves a denied or granted permission. “Lumen refreshed” is general app activity; “Sleep & workout check” describes the paged history check/application, including an empty result.

Preserve native grouped navigation, teal actions and the established secondary ink for meaningful status/privacy copy. At accessibility sizes, the full-width label precedes its switch and the status uses a vertical layout. Preserve text size and scrolling rather than splitting a long label around a switch. The timing explanation gives the practical action to open Lumen; simulator/device verification belongs in engineering documentation. This scoped extension adds no new paywall, icon, motion signature or visual direction.

## Batch 13 · scanned record review

The existing daylight-observatory direction continues. This is a Library extension, not a new concept, icon, onboarding, paywall or motion assignment. Cool white/deep teal surfaces, expanded native display headlines and native body text remain. The useful object is the user's actual page, reached through Page image and Open original; decorative clinical imagery would compete with accurate review.

The core action is read → compare → correct → explicitly save. Initial copy: “Read a record.” / “Choose a file”. Review copy: “Review your record.”, “Page text”, “Exclude this page”, “I checked all included pages against the original”, “Use in assistant”. The last control starts off. Names/numbers/units and original-file retention limits appear at their decision points. The draft is cancellable and edited text requires a discard decision. The saved document carries its import-review time separately from later edits. Native system Files/Quick Look and the persistent toolbar Cancel/Save carry platform behavior; no ornamental motion is added.

The scope includes actual native light/dark and accessibility-size captures, source comparison, progress/errors, consent and saved provenance. Capture review and independent scores are recorded in CRITIQUE.md. Browser-DOM shoot/scan is not evidence for SwiftUI; native screenshots and assertions must supply that evidence. Synthetic fixtures are visibly labelled and never presented as real patient data.

## Batch 14 · a reply's Library references

Preserve the daylight-observatory direction and existing destinations. The question selects relevant saved text; references are quiet, numbered teal objects below the reply. “Library matches” identifies literal on-device lookup. “Library for this reply” distinguishes excerpts sent to a provider from the ones its answer actually cited. Neither label promises verified medical accuracy.

The reference sheet leads with the document title, then page/excerpt location and exact saved text. Selection time and document update time remain separate. “Open in Library” reaches the current version; changed text, sharing off and removal are factual states. Earlier replies and saved copies retain their snapshots. Source text is user content, rendered literally. Native disclosure/sheet/navigation patterns, dark appearance, scrolling and actual Accessibility XXXL support carry the extension. No new concept, icon, paywall, store assets or promotional motion is in scope. Native captures and the continuing independent critic provide the design evidence; no browser scan is claimed.

## Batch 15 · readable export and reviewed recovery

Continue the daylight-observatory direction within Settings and Backup & restore. The existing Export my data action opens a native page headed “Your data, in plain text.” It states “This JSON file isn't encrypted and doesn't include meal photos.” Create export and Save or share export are explicit separate steps; encrypted backups remain the route for photos/password protection.

A separate Recover a readable export page leads with “Review before adding.” Choose export opens native Files. The converted file shows its actual filename/export date, selectable record categories with counts and Review records, and optional name/sleep settings, body/activity goals, sleep routines and personal notes, all replacement choices off by default. Partial files never invent selected defaults. Read-only record pages show saved text/values, with page controls for long text. Omitted cache/unknown sections, missing photos and any recovered active chat are factual review items. No measurements or medical interpretation are created from cached totals.

Keep reviewing and Add selected data form the explicit confirmation; no data changes at file selection. Current matching records win, added documents start with assistant sharing off, and recovery doesn't write to Apple Health. Progress and Cancel stay reachable; leaving releases private files after work stops. Recovery complete leads back to the user's real data. Native light/dark and actual XXXL controls/readers, cancellation/error, partial-file, merge/relaunch and export/share/reopen behavior require simulator evidence and the continuing independent critic. No new visual concept, icon, paywall, paid assets or promotional motion is in scope.

Batch 15 refinement after native round 1: recovery finishes with “Recovery complete.” and its saved-result sentence, an explicit Done action and secondary Choose another export. Body-sized export dates and omission counts use the declared secondary ink. File trust and omission wording is plain; actual unknown section identifiers remain literal. Page controls stay in the bottom safe area for long lists/readers, and empty history categories cannot be selected. The runtime alert presentation uses local view state; observable errors clear only from user actions.

## Batch 16 · speak, review, then use the draft

Extend the existing native Assistant composer with an accessible microphone action. Preserve the daylight-observatory palette, native expanded headlines and body text, retained source/copy controls and all destinations. No new concept, icon, paywall, store set or ornamental motion is introduced. App Designer Pro and the continuing independent critic supply native light/dark/actual XXXL review.

Voice opens **Speak a message.** with **On-device speech**, an explicit language choice and **Start recording**. If a language needs assets, **Download language** is a separate decision with actual progress and the explanation that iOS manages shared language storage. No model download or microphone access happens on opening. The microphone prompt follows Start; unsupported devices/languages and denied access have useful factual states. Recording has elapsed time, live text and **Stop recording**; background/interruption stops capture. Lumen sleep sounds pause without losing their timer. Audio is held only in bounded memory, never recorded to an app file or sent to a transcription server.

The stopped state leads with **Check your words.** and literal **Voice text**. **Edit text** opens a focused native editor; unsaved changes have explicit keep/discard choices. **I checked names, numbers and units** starts off. **Use text** adds to the current unsent composer; Send and confirmed health-log review remain separate actions. A changed target cannot receive the voice text; copying remains possible. Record again and close/swipe offer explicit keep/discard choices when text exists. A voice draft is temporary and isn't a clinical interpretation. User content stays literal and no missing/unsupported number is invented.

Synthetic native driver fixtures are explicitly labelled **Simulated speech. No microphone.** and are compiled only for debug simulator verification; screenshots prove state/interaction, not live recognition. Real device speech/language accuracy, interruptions/routes/energy and microphone behavior retain explicit device gates. The same core result buffer and target/composer policies serve production and fixtures. Native controls reflow at accessibility sizes; no capture animation is needed beyond actual elapsed state.

Batch 16 refinement after native round 1: review actions use text-only labels at accessibility sizes so wrapped words share one leading edge; standard sizes retain native symbols. Stop/privacy copy says “you left Lumen” / “leave Lumen.” The focused editor disables autocorrection, preserves the earlier draft until Done and keeps native Cancel/Done in the toolbar.

## Batch 17 · health-entry keyboard dismissal

Preserve the current health-entry Form, dates, values, notes, source statement and individual confirmation. Runtime isolation identifies the SwiftUI keyboard-toolbar path as the source of the invalid-frame diagnostic on this simulator; changing its spacer alone and deferring it to text focus do not remove the diagnostic. Done now occupies a native material bottom inset only while a uniquely identified input is focused. It remains trailing-aligned, at least 44 points high, grows with text size and dismisses focus without changing the value. No new concept, icon, paywall or motion is added.

Native light/dark and actual Accessibility XXXL captures must show Done above the software keyboard, multiline note content, dismissal and edited-draft protection. Focus routing must work for water, workout, symptom and check-in fields. The existing separately reviewed confirmation and original-message provenance remain. Native pixels and the same independent critic supply design evidence; no browser scan or physical-device claim is made.

Batch 17 refinement after critic round 1: at actual XXXL, the inline multiline note leaves its caret behind the keyboard. Notes now use a full-size native TextEditor destination with a trailing Done inset above the keyboard, preserving arbitrary caret editing and the existing optional/8,000-character draft semantics. The form has a short literal preview and Add notes / Edit full note. Edits mark the enclosing draft immediately; Done returns to that draft, while only Confirm and save entry persists it. Scalar inputs retain the material dismissal inset. No text size is reduced and no scrolling test is substituted for the visibility fix.

Batch 17 correction-editor alignment: the saved local water/workout correction form uses the same focus-bound scalar Done inset and full-size notes editor. Save, Cancel, original-source details and the changed-draft guard remain separate from keyboard dismissal. Native final review includes correction light/dark/XXXL states; unchanged record-import controls are outside this form-specific investigation.

## Batch 18 · reviewed multiweek plans

Continue the daylight-observatory iPhone direction, with cool white ground, deep-teal actions and expanded native headlines. This is an added planning flow, with no new concept/icon/paywall/store/motion set. Preserve existing conversational plan saves, documents, source references, consent and health-log confirmation. New scheduled plans remain temporary until explicit review; their current dated checklist drives Library and the agenda.

Content and hierarchy: setup leads with **Make room / for a routine.**, then Your goal, Start date and Duration (1, 2, 4 or 8 weeks). **Prepare draft** names the selected provider and the exact shared context; a separately chosen **Use a planning template** explains its repeated prompts and lack of personalization. Preparation has Stop and preserves inputs on error. Review leads with the literal proposed title, weeks/dated-step count and actual source; native week sections expose every step, date and edit route. **I checked the steps and dates** gates **Save plan** and resets after edits. **Change goal or timeframe** explicitly discards only draft steps, retaining setup. **Plan saved.** leads completion, with View saved plan and Done. Close/swipe offers Keep planning / Discard draft. Assistant sharing starts off.

Planned dates are civil calendar days, preserving the chosen day during travel. The same current dates must appear in review, Library, agenda, editable documents, readable recovery and assistant excerpts. Legacy absolute due dates retain their earlier behavior. Goal/title/description and action wording use full-size native text editors with local live state, minimum44-point Done labels and keyboard clearance. At accessibility sizes the acknowledgement label takes the full row before its switch. Verify normal/light/dark and actual XXXL, eight-week coverage, the last action, safe cancellation, exact text, confirmation/relaunch/completion and sharing off. Debug-only simulator fixtures visibly say **Simulated plan. No AI request.**; they prove the parser and UI path without claiming model inference or clinical quality. Native captures and the same continuing critic provide design evidence; no browser-DOM scan claim.

Batch18 first native refinement: the eight-week24-step review at actual XXXL needs many scrolls. A native Weeks menu jumps to each full week or Before saving while retaining all actions. This navigation remains available during review; choosing it never acknowledges or saves. The native harness uses actual scroll/jump controls and checks the nested switch value rather than assuming a tap on its wide label changed it. New plans use the existing automatic completed status once every action is done, while preserving explicit later status choices.

Batch18 critic round1 refinement: saved-plan wording names its committed editable state; provider/template explanatory footers use the established secondary ink; invalid-reply recovery directly names a complete dated plan and the planning template. No content is removed and no source/model/consent boundary changes. Round2 adds large action/date/completion/persistence and explicit review-reset evidence.

Round2 completion/action layout: completion uses native scrolling so full-size supporting text and both actions remain reachable at XXXL. The action editor stacks its date label above the native date control at accessibility sizes, leaving full width for both. The editor keeps local live text and a keyboard-clear Done inset; native selection/typing, rather than hardware shortcuts, must prove the final caret with the software keyboard visible. The observed native date picker is exercised by its actual calendar-day labels and bounded date range.

Round2 pixel read catches an additional real input issue: the action string was exact, but its displayed caret appeared within the paragraph. The action editor now owns independent live wording/day state and returns one complete action through Done or Back; it never forces a caret to the end. The review resets acknowledgement synchronously when that action changes. Large completion labels also gain inner padding and centered wrapping, so white text stays within its owned capsule surface. A numeric-only opted-in probe subsequently found the actual selection at the complete string end while the painted glyphs/caret disagreed. The native bridge investigation did not establish a settled keyboard layout and is removed. The final step form instead follows the verified notes pattern: planned date, a short literal preview and Add step wording / Edit full step, opening the shared full-size native editor without the date header competing for space. Fresh native end/middle editing, Back/Done, date movement, completion and review-reset evidence must verify the result before sign-off.
