# Reviewed lab records · Batch 20

This batch adds structured, user-reviewed transcriptions to saved Library records. The implementation and scoped delivery checks are complete, published as `4e455c67560d9e5a46dad0ad63cf547fbcb431b6` with matching GitHub main read-back. The original saved text remains separate and unchanged. No real patient data is used during development.

## Contract

Each result retains the literal test name, result (including comparison signs, decimal punctuation or qualitative wording), unit, reported reference wording and reported flag. Laboratory, specimen and method stay literal or unknown. Multiline wording and whitespace remain literal. A collection day is optional and must be an explicitly reviewed YYYY-MM-DD calendar day; absent dates are not replaced with today. Lumen does not convert units, infer a normal range, assign high/low flags, map names to a clinical code or infer comparability/clinical meaning.

Results attach to an existing record, with stable identities and exact source excerpts/character offsets. Each review row exposes its complete source excerpt before saving. The review acknowledgement must be fresh after edits. Saving uses checked storage and rejects a concurrently changed/deleted record or a changed lab review. Sharing follows the current document choice; opening a review cannot reset a newer consent choice. Removing all transcriptions requires explicit review and preserves the source document.

The saved lab review binds to the complete source-body SHA-256. Later text edits retain the historical transcription with a visible changed-source state; its structured values are withheld from future assistant retrieval until re-reviewed against current source excerpts. Earlier independently saved replies/references retain the existing copy policy. Matching body hashes with invalid source anchors, duplicate row identities, unsupported versions and malformed fields cannot be restored. Legacy documents without lab metadata still decode.

Current reviewed fields join the consent-filtered canonical Library search text and change source fingerprints when corrected. They remain untrusted reference data. Backups, readable recovery and Markdown retain literal fields, review time, exact excerpts and source-change state. No HealthKit writes or new automatic provider requests are introduced.

## Native screens to verify

- Saved record: **Lab results**, count/review time, literal result/unit, optional reported reference/flag/date, **Saved source excerpt**, **Review lab results** or **Add lab results**. Changed text says **Source text changed** and identifies the earlier transcription.
- Review: **Keep each result with its source.**, **Add result**, editable rows with removal, **I checked every result and its source**, separate **Cancel** and **Save**. Removing every existing row explicitly removes the transcription, preserving the record.
- Result editor: **Test name**, **Reported result**, **Unit**, **Reference wording**, **Reported flag**, optional **Collection day**, **Laboratory**, **Specimen**, **Method** and **Choose source text**. All optional fields can remain unknown. Full literal wording stays editable.
- Source picker: exact selectable saved-text lines, top search and explicit further-results access; **Include previous line** / **Include next line** retain contiguous wrapped wording within a checked 2,000-character excerpt limit; no guessed row/value extraction or clipped source lines. Overlong lines remain in the original document and are not silently truncated into anchors.

The existing App Designer Pro daylight-observatory direction, expanded display typography and native controls remain. The scoped native checks below verify the local review flow; production checks cover conflicting edits and consent retention. Portable CSV/JSON lab import, automatic table proposals, longitudinal lab comparison, FHIR/clinical-document ingestion and clinical validation remain open work; none is claimed by this transcription foundation.

## Primary design references

[HL7 FHIR R4 Observation](https://hl7.org/fhir/R4/observation.html) distinguishes observations from diagnoses and separates values, methods, specimens and reported reference data. [FHIR quantities](https://hl7.org/fhir/R4/datatypes.html#Quantity) retain comparator/unit information. These references inform the separation of fields only: this Lumen format is not a FHIR implementation or a validated clinical interpretation.

## Scoped verification

**633 production-logic checks pass**, including literal comparator/comma-decimal/qualitative/multiline values, Unicode/CRLF source offsets, adjacent-line expansion, bounds, malformed dates/anchors/versions, duplicate identities, source and concurrent-review conflicts, current sharing retention, stale-metadata withholding and actual version-one/encrypted/readable backup round trips. Missing lab metadata remains compatible with older records. A new test caught page-label inheritance on appended metadata after a trailing source newline; source-body offset boundaries now prevent that. The failure remains in the report.

All five simulator targets build for testing. Unsigned generic-iOS Release passes, minimum iOS 18, with no bundled model packages. The earlier marker check did not cover the inherited startup-reset shortcut or unreachable speech label; Batch21's broader audit finds and gates those paths for Debug simulators. At the Batch20 checkpoint, app source matches ReleaseR3; only test gestures/selectors change afterward. Source equality covers172 native/project/UI-test files and25 package/test/script files.

**NativeR3 fully passes**, zero failures/skips/recorded runtime warnings: presentation 221.019s and reviewed lifecycle 224.023s. This includes actual Files recovery, exact source/adjacent-line selection, typed values, source-before-save, acknowledgement/reset, correction/relaunch, changed-source warning, removal retaining the document, light/dark/XXXL sources, multiline editing/software keyboard/Done and collection-day controls. Visibly local test lookup prevents generative-provider requests. These cases use only synthetic data.

The continuing critic completes two rounds at ten of eleven applicable lines4+, Richness 3, with no remaining concrete defect. All 22 final originals and precise capture/result/source boundaries are retained in `Design/native/labs`. NativeR1/R2 and the initial test-compile failures remain explicitly failed; none is relabelled. A paginated system edit menu and propagated disclosure accessibility identifier required corrected test interactions, not product workarounds.

Current delivery evidence is [verification.json](../Design/native/labs/verification.json), with native gallery and critique beside it. Exact preserved strings and storage are behavioral checks; individual stills do not prove every position in an arbitrary long value, VoiceOver, clinical accuracy or physical-device behavior. No real health data or live generative-provider requests were used. The full product goal remains active.

## Storage checkpoint

After remote confirmation, scoped cleanup removed 66 task-owned roots and increased available space by **2,991,542,272 bytes (about 2.99 GB)**. All 22 final originals and useful before defects remain; full earlier sets are recoverable in the application commit. The working repository, supplied design skill and current inputs are preserved. [Cleanup scope and accounting](../Design/native/labs/storage-cleanup.json) retain exact facts. Raw temporary report paths are historical; no app build followed this documentation-only checkpoint.
