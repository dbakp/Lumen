# Conversation storage and returned replies

Batch39 is published as `1ecb6938f9e81df6fa3926f1838c693e488d757f`, with exact GitHub source/evidence read-back before scoped cleanup. The [evidence ledger](../Design/native/conversation-storage/verification.json) records each actual source boundary and failed attempt. The full product goal remains active.

## Checked changes

Opening a saved conversation, starting a new one, renaming, deletion, Settings Clear, saving a question and saving a returned reply use the same checked storage boundary. Visible history and selection change only after that boundary commits. An unsuccessful operation keeps the saved state and offers recovery; Rename keeps its editable draft. A title changed since the editor opened is rejected rather than overwritten.

The outgoing question must save before any provider request starts. Only the exact submitted composer draft clears after success; independently entered new text stays. A question-write failure leaves the draft available and does not call the provider. Failures in either the archive or the compatibility mirror reject the linked operation.

If a returned reply cannot save, Lumen retains its exact message, provider label and selected Library-reference snapshots in memory. The reply is explicitly marked **Reply not saved** and offers **Retry save**. Retry writes the retained packet without another provider request or duplicate message. A separate Library plan copy cannot claim a saved conversation message before that message commits.

This pending reply is not a durable outbox. Keep Lumen open until it saves. Quitting can lose an unsaved reply; deleting its conversation, clearing it, reset or restore also discards pending work as disclosed by those actions. A recovery link returns to an inactive conversation containing an unsaved reply.

Batch41 work carries each returned reply's text, source, personal/Library provenance and automatic-plan eligibility as one immutable outcome. The save path uses that request's outcome rather than shared last-reply display fields. A later completion cannot turn a notice into another request's plan. Pending save retries retain the original decision. This is locally verified work in progress; see the [current evidence and remaining gates](../Design/native/request-authorization/README.md).

An ordinary conversation creates an automatic Library plan only for an accepted planning reply with at least two nonempty numbered steps. Urgent guidance, search/change notices, rejected model answers, literal lookups and prose without steps retain their conversation text without inventing checklist tasks. Explicit **Save to Library** remains available; existing plans are preserved. A numbered structure does not establish clinical or factual quality.

## Ownership and cancellation

Navigation and New conversation preserve a request to its intact originating conversation. A reply completing elsewhere saves to that origin and preserves the current selection. Renaming does not change origin ownership.

Stop, deletion, Clear, reset and restore invalidate the appropriate request. Cancellation is registered with the store so it still applies when the Assistant screen is absent. Conversation lifetime, store generation and latest saved question identity reject obsolete callbacks. A newer storage revision or changed operation also rejects an already prepared transaction before installation. Neither a rejected prepared save nor a late response may recreate removed history or erase newer composer text.

Clear and Delete use a full-width native review with fixed Cancel and removal actions. The complete scope and retained-data assurance scroll at the selected text size. The review owns its checked operation and recovery alert, and closes only after success or an explicit cancellation.

Conversation removal does not remove separately saved Library copies or independently confirmed health entries. Their retained origin receipts remain distinct from the conversation itself. Account reset has its own wider scope; this batch does not establish a power-loss-safe erase across all domains.

## Startup and compatibility

An existing `conversations.json` is authoritative, including an explicit empty array. Only an absent archive permits migration from legacy `chat.json` or older defaults. Corrupt, unreadable, nonregular or structurally invalid history produces **Conversations unavailable** with **Retry opening**. Sending and history changes remain unavailable; startup does not silently replace that history with defaults. A competing local storage revision during startup migration gets a bounded retry with a fresh read; corrupt-file and I/O failures do not take that retry path. Duplicate identities and a selection pointing to a missing conversation are rejected.

Checked conversation transactions install the archive, compatibility chat mirror and explicit selection file together. An unsent new conversation has a nil selection and empty mirror. Unrelated health persistence no longer rewrites conversation files. When a previous directory survives an interrupted swap, preparation must validate current conversation history before retiring that recovery copy. Both linked writes and backup restoration use this protection.

Old message/conversation fields remain compatible. Encrypted backups and readable recovery retain literal Unicode text, provider labels, selected reference snapshots and original message identities. Restoration retains current versions of existing records, adds missing records and installs a coherent unsent selection. Restore confirms that it stops in-progress replies and discards unsaved replies. Separate existing Library-consent checks continue to apply; this batch does not establish recall of remote input or broader personal-context history privacy.

## Verification limits

Portable actual-file checks, actual iOS store/backup integration and native UI with controlled delayed loopback responses cover complementary requirements. Passing one does not substitute for the others. Main/compact, keyboard and largest-text results are scoped to their recorded runs; current app27/UI23 passes final main/compact XXXL recovery checks and the continuing critic accepts the scoped visual review at43/55. Separate runs retain their original boundaries; publication/read-back is separately verified.

Synthetic simulator checks do not prove physical-device storage pressure, sudden power loss, live-provider quality, clinical correctness, accessibility completion or release readiness. Broader privacy, durable Health intent and acknowledged Watch delivery remain separate roadmap work.
