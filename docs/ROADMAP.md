# Lumen product gaps and delivery batches

Audit date: 29 October 2026. Scope: the actual native repository, not the screenshot preview.

## Delivery rules
Each batch is a separate conventional commit pushed to GitHub after relevant logic checks and a native build. Native integration tests cover the final combined flow. No fabricated integrations, clinical claims or app-store readiness claims. Existing local data must continue to decode.

## Batch 0 — publish the verified foundation
Contextual Today; symptoms and check-ins; local imports; AI/provider provenance; Library and plans; quiet reminders; light-first design and Watch/widgets. Previous work is local and must be committed before further changes.

## Batch 1 — personal context and plans
Missing: explicit long-term preferences/constraints, user control over assistant memory, editable checklist actions, dates, active/completed/archived plan states and a practical view of upcoming steps.
Deliver: local personal context editor (goals, food preferences, allergies, injuries/limitations and schedule), per-profile sharing consent; dated editable plan steps, progress/status and an upcoming-actions view. Context is supplied only when opted in. User-entered medical constraints are reference notes, not diagnoses. Completed/archived plans do not generate overdue pressure.

## Batch 2 — conversation continuity
Missing: conversation history, reopening/renaming/deleting past chats, and robust handling of a reply finishing after navigation or a new conversation.
Deliver: persisted conversations with migration of legacy chat; search/history/rename/delete; replies and saved plans tied to the originating conversation; one in-flight send with clear cancellation behavior; no lost or misattributed replies. External model availability still requires real-device/provider verification.

## Batch 3 — useful longitudinal insights and appointments
Missing: meaningful period comparisons using actual recorded coverage, a browsable insights destination, and appointment summaries with symptom details and relevant timeline context.
Deliver: current-versus-previous 7/30-day comparisons, source/coverage labels, clear minimum-data rules; local appointment summary document with symptoms, check-ins, activity and questions; save summaries to Library and share through existing document controls. Associations are not diagnoses or causal claims. Missing days are never treated as zero.

## Remaining roadmap after these batches
1. Backup/restore with versioning, preview, validation and merge conflicts; include meal photos and verify migration without dropping historical logs. Current export is not a complete restorable backup.
2. Background HealthKit observation/anchored synchronization, permission-aware freshness and delivery diagnostics, tested on a signed physical iPhone. Current refresh-on-open is not continuous monitoring.
3. Apple Health ZIP ingestion, cancellation/progress for large imports, richer provenance, OCR for scanned records, and reviewable structured lab records. Keep unsupported formats explicit.
4. Direct provider connections only where official OAuth/API access is configured and tested. Existing HealthKit and Strava are not a substitute for pretending every device is connected.
5. User-reviewed conversational logging, voice input, structured AI-generated multiweek plans and explicit tool confirmations. The assistant currently advises; it does not silently modify every health log.
6. More complete data editing and reconciliation: HealthKit write failures, deletion confirmation/retry, source priority, import rollback, configurable retention and export units/timezones.
7. Device release validation: denied/partial HealthKit access, real model inference, notifications in the background, camera, Face ID, Watch offline/reconnect and widgets, accessibility text sizes, localization and energy/performance profiling.
8. Clinical/product governance before any diagnostic feature, medications guidance, lab interpretation or regulated claims. Keep wellness guidance distinct from medical assessment.
9. Distribution: signed builds, CI on a configured macOS runner, TestFlight, privacy/store disclosures and crash reporting with explicit data-minimization choices. No credentials or paid services are assumed.

## Completion log
Pending batch entries will record commit, validation and push outcome below.
