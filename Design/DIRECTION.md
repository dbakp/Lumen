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
