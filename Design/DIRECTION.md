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
