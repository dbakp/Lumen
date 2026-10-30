# Reading records in Library

Choose **Library → Add document → Import a record**. Lumen reads the selected file on the device, then opens a page-by-page review. Nothing is saved until you confirm that you checked the text and choose Save. This is reference text, not a diagnosis, interpretation or structured laboratory import. It does not write measurements to Health or Lumen's health logs.

## Supported files and bounds

- PDF, including image-only scans; still JPEG, PNG and HEIC/HEIF images; UTF-8 text and Markdown.
- Other formats identified by the system as plain text, such as UTF-8 CSV, remain readable as reference text. This does not add their rows to health measurements.
- Up to 20,000,000 input bytes, 100 PDF pages and 200,000 text characters. Page headings count toward the saved-text bound. Split larger records before importing.
- Locked PDFs need an unlocked readable copy. PDF form widgets require a flattened readable copy so values aren't silently omitted. Damaged/unsupported files produce an error and leave Library unchanged.
- Still images must contain one image and at most 100 million source pixels. PDF/image reading uses a raster with a maximum side of 2,400 pixels; page previews together are bounded to 150 MB. This is not an original-resolution document archive.

## Read, compare and correct

PDF pages retain both selectable text and recognized text where available. Scans use recognition. Pages containing image XObjects, including nested forms, prefer recognition so a selectable header doesn't hide the image body. Other selectable pages prefer their embedded text. You can choose the other version; replacing edited text requires confirmation. Unusual PDF encodings, inline images, columns, tables, handwriting and reading order still require particular care.

Recognition uses Apple's on-device Vision request in accurate mode. Automatic language detection is enabled, supported preferred-device languages plus English are requested, and language correction is disabled to avoid automatic spelling changes to names, numbers or units. Support and recognition quality depend on the operating system and document. There is no accuracy or clinical validation claim.

Expand Page image or open the original to compare it with Page text. The original opens in a read-only system preview with an explicit Close action; markup editing is disabled. Correct every relevant name, value and unit. Confidence warnings count candidate lines below the request's threshold; unmarked text can also be wrong. A page with no text must be transcribed or explicitly excluded. Every remaining page must have text and at least one page must remain. The save acknowledgement resets after text, source or exclusion changes. Title edits and page changes stay in the draft until saved; cancelling an edited draft asks whether to discard it.

**Use in assistant starts off.** Turning it on allows excerpts to accompany questions to the selected AI provider. Importing and reviewing alone do not send the file to a provider. The record remains untrusted reference material under the existing assistant-context rules.

## What is kept

Save writes the reviewed text with page headings and optional extraction metadata: source filename, SHA-256 fingerprint, read/review times, per-page method, edit/exclusion flags and uncertain-line count. The fingerprint detects importing the same file again; a separate copy requires explicit confirmation. A different file with similar text is not treated as identical. Legacy documents without metadata remain readable, and metadata is included in normal backups. Later body edits retain the import-review date and mark the text as subsequently edited.

**Keep the original separately.** Library does not retain the source PDF/image, page rasters or original OCR alternatives. Share document exports the saved reviewed text. The private selected copy and page previews are temporary and explicitly removed when the import sheet dismisses, even if SwiftUI retains the closed preview; abandoned Lumen-owned working folders are cleaned on the next import. Input coordination and recognition have cancellation handlers. Cancellation never creates a record. Source copying and recognition run off the main actor.

New imports and Library editor, sharing-setting, checklist and deletion actions use checked storage before publishing success. A failed write keeps the visible state/draft and reports the failure. This doesn't establish every storage-pressure or interruption path on a physical phone.

## Verification boundary

Production-logic tests use actual Vision recognition on synthetic PDF scans, hybrid pages and PNG images, plus selectable/UTF-8, malformed/locked/oversized/page-limit inputs, cancellation, review/exclusion and backup compatibility. Native simulator tests exercise the real Files picker and review flow. Exact final results and remaining device gates are recorded in [Verification](VERIFICATION.md). No real patient documents, clinical accuracy study, signed-device OCR performance, every language/layout or iCloud transfer is established by those fixtures.
