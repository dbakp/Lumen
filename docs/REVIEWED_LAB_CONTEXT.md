# Complete reviewed lab fields with selected excerpts

Batch31 carries complete reviewed lab observations beside relevant Library excerpts. A900-character window can otherwise separate a test name/result from its unit, collection day, qualifiers or person label. This change keeps those associations available without changing the original excerpt or converting the reported values.

## Selection and source identity

Only a currently valid, reviewed `LabReport` on a shared record can contribute attached fields. A selected window must overlap the observation's exact saved-source anchor or its actual constructed region in canonical reviewed metadata. Regions come from construction, not searching for headings in user-controlled text. A forged heading such as `Lab result1` cannot create an attachment. Matching words, a record title or a clinical-code guess cannot substitute for source overlap.

Each attachment keeps the entire `LabObservation`: exact test/result/unit/reference/flag; optional collection day, original collection wording and reported status; laboratory/specimen/method; original source anchor/excerpt; and retained FHIR provenance/fields where present. The record's original imported person label and review time accompany it. Blank, whitespace-only and absent source person labels remain distinct in stored data; none establishes a verified person. No unit conversion, test-code equivalence, normality, diagnosis or intended-person inference is added.

Reviewed corrections can differ from the saved source. The provider receives separate `savedText` and `reviewedLabFacts` JSON fields and explicit instructions to keep original wording separate from the complete reviewed observation. Review time is an ISO UTC timestamp, not a collection time. Missing units/days/person labels remain unknown. The new source-sheet section and literal fallback expose the same distinction, including the original source excerpt.

Saved excerpts, complete reviewed fields, user questions and built-in lookup replies use the native selectable literal reader. Asterisks and link-like source text remain characters; wrapping cannot insert discretionary hyphens into names, identifiers or URLs. The reader follows the selected text size. User bubbles keep their question colour and fit short text. Model-authored replies retain their existing formatting.

## Bounds and honest omissions

Each passage can carry at most four distinct overlapping observations. The complete attachment set is limited to8,000 characters/32,000UTF-8bytes of deterministic reference text, including original source excerpts and an explicit UTC review timestamp. A review time outside the four-digit ISO year range cannot become an attachment. These bounds are separate from the unchanged four-passage/two-per-document and900-character excerpt limits.

If the whole overlapping set cannot fit, no subset or shortened row is presented as complete. `omittedReviewedLabFacts` records the number of overlapping observations, and the source sheet/lookup/prompt explains that the complete fields need Library review. Text-search coverage counts remain separate from this field-attachment omission. Original records and transcriptions are not truncated or erased.

## Currentness, history and saved copies

The canonical text/fingerprint contract remains byte-compatible. A new attached packet is checked against the current report's complete fields, source anchors, person label and review timestamp as well as the existing excerpt/content/sharing checks. ISO storage's loss of subsecond review-time precision alone does not mark unchanged fields stale. A source edit, correction, removal, withdrawal or actual review-time change invalidates its current attachment. Older references without attachment metadata retain the existing source policy and do not acquire invented fields.

History can replay only the matching current source packet. Sharing withdrawal/deletion blocks later reuse, including complete attached fields. Earlier conversations, saved copies, readable sharing and backups can retain their captured fields and source excerpts; those copies are not erased by changing the original sharing switch. Referenced Markdown includes attached fields, while uncited provider context remains omitted. Optional metadata keeps existing stored records readable; compatible and encrypted backups retain the new facts.

Canonical paragraph splitting now respects actual Swift Character boundaries for CR/LF/CRLF blank lines and appended metadata. The ordinary LF path retains its earlier windows. This prevents a carriage return at the body boundary from shifting a saved excerpt or the associated metadata range; original canonical bytes are unchanged.

## Verification boundary

Production checks cover complete late-window fields, corrected/original separation, qualitative negation, missing fields, table/FHIR person and coding provenance, forged headings, currentness/privacy/history, whole-set omissions, UTC/storage precision and compatible/encrypted backup round trips. Native proof must include the exact reference reader, full-size text/scrolling/actions, sharing withdrawal, retained fields after relaunch, omission, actual dark/AccessibilityXXXL and compact-phone presentation. Exact outcomes, failed attempts, source boundaries and continuing design review belong in `Design/native/lab-context`.

This is source coherence, not a claim that every selected record answers the question or that a model's explanation is entailed by it. The frozen challenge's seven unsupported-topic selections remain separate; no replacement model, cutoff or query prefix is selected. Clinical/provider/language quality, signed devices, accessibility and release/privacy gates remain open.
