# Lumen implementation plan

1. Audit and preserve native health, Watch, widgets, sleep, food, activity and privacy features.
2. Explore three directions; choose a daylight observatory: cool white, deep teal, native typography and a contextual daily narrative.
3. Add a persisted companion domain: symptoms with location/severity/onset/triggers/resolution, energy/mood/stress check-ins, records, editable documents and checklist plans.
4. Replace Today with evidence-led guidance and a merged timeline. Provide Today, Journal, Assistant and Library tabs; retain existing feature screens from Today.
5. Support previewed, deduplicated Apple Health XML imports and a documented portable CSV/JSON schema. Add text/Markdown/PDF records, local extraction, source provenance and explicit AI-sharing controls. HealthKit remains the primary live connector; Strava uses existing OAuth; other devices connect through Apple Health.
6. Ground conversation in current health, recent symptoms, check-ins, imported history and consented records. Save generated plans automatically; let users save any response, edit drafts and share documents. Protect against treating imported text as instructions.
7. Replace generic repeating notifications with optional, capped, quiet-hours-aware contextual check-ins. Cancel stale nudges when data changes. Explain foreground refresh limits.
8. Add weekly reviews, source/coverage transparency, privacy controls and export/erase coverage. Validate import formats, calculations, retention, symptom transitions, reminders and document persistence. Build all targets and exercise core flows where the installed simulator supports them.

## Research, 29 October 2026
- Bevel capabilities: https://help.bevel.health/en/articles/11586817 and version overview https://help.bevel.health/en/articles/11194113. Relevant: symptom triggers, memory, plans/files, journal timeline. Never infer causation from journal correlations.
- Oura meals: https://ouraringhelp.zendesk.com/hc/en-us/articles/40264659421843-Meals. Relevant: food timing alongside sleep and daily context; meals remain user reviewed.
- Athlytic export: https://athlyticapp.helpscoutdocs.com/article/47-can-i-export-data-from-athlytic. Relevant: portable health summaries, unavailable values stay unavailable.
- Apple Health authorization: https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data. Read authorization cannot be inferred from completing the sheet.
- Apple Foundation Models: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel. Model availability is checked at runtime; fallback is visibly identified.

## Boundaries
No diagnosis, medication changes, invented health measurements, speculative biological age or causal trigger claims. No fake OAuth connections. Real-device HealthKit, notification delivery, cloud-model responses and haptics require device validation. No server is deployed and no health data is uploaded during development.

## Additional evidence used in implementation

Urgent-symptom routing is deliberately conservative and does not diagnose. NHS headache guidance identifies sudden extremely painful headaches and neurological symptoms as reasons for emergency help: https://www.nhs.uk/symptoms/headaches/ . NHS chest-pain guidance covers persistent/sudden chest pain and associated breathing symptoms: https://www.nhs.uk/symptoms/chest-pain/ . The app refers to local emergency services rather than hard-coding a UK number. The generic under-seven-hour sleep observation is informed by CDC adult sleep guidance, not a personal clinical sleep prescription: https://www.cdc.gov/sleep/about/ . These sources do not validate Lumen's heuristic readiness score or its AI output.

## Initial foundation checkpoint · 29 October 2026

Implemented steps 1–8. All five build targets compile; 28 standalone Swift checks pass; the complete native smoke scenario passes on iPhone 18 Pro / iOS 27.0 with zero failures. See VERIFICATION.md for exact coverage, physical-device checks and supported import limits. Final implementation includes the refreshed app icon, source-aware totals, personal heart-signal baselines, historical summaries, editable logs, Library documents/checklists, and capped contextual notifications. No cloud deployment or App Store publication was performed.

## Continuing delivery · 31 October 2026

The initial foundation is not completion of the full product goal. The [roadmap](ROADMAP.md), [continuation handoff](CONTINUE_ON_NEW_COMPUTER.md) and dated [verification evidence](VERIFICATION.md) track subsequent batches and remaining gates. Batches21–23 are published. Batch22 adds [lab history and reviewed comparisons](LAB_HISTORY.md), and Batch23 adds [reviewed local FHIR lab import](FHIR_LAB_IMPORT.md), verified with996 logic checks, all-product simulator/unsigned Release builds, scoped native journeys and final design sign-off. Batch24 has verified [reviewed unit comparisons](LAB_NORMALIZATION.md):1,227 logic checks, current all-product/unsigned Release builds, scoped phone cases and final critic43/55. Coherent publication/read-back and scoped cleanup follow; exact source boundaries remain in the handoff. Publication and storage cleanup evidence remains scoped to each delivered batch. Physical-device Health/Watch/voice delivery, broader ingestion/relevance, clinical review, live providers and release/privacy governance remain open.
