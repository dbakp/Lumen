# Next data-confidence audit

Read-only source audit during Batch38 verification. These paths are not changed or claimed as repaired by Batch38.

## Conversation storage

`Lumen/Models/HealthStore.swift` currently loads legacy `chat`, migrates it when the saved conversation archive is empty, and saves the resulting archive unchecked. The current `saveActiveConversation`, selection, rename, deletion and inactive reply append paths also use unchecked local writes. `persist()` rewrites both chat/archive on unrelated health persistence.

`Lumen/Views/ConversationHistoryView.swift` clears the rename state after an unchecked mutation and clears deletion confirmation without save feedback. `Lumen/Views/CoachView.swift` clears the outgoing draft and starts the reply after unchecked user-message persistence; a returned reply is also persisted unchecked. Current reply ownership rejects appending to a deleted conversation, which must be preserved.

Required follow-through: checked archive/message mutations before showing success or starting a provider request; retained rename/send drafts with retry; failed deletion preserving the current conversation; late replies respecting deletion/reset/restore; and removal of unrelated archive rewrites. The archive and legacy-chat compatibility mirror need a coherent recoverable commit boundary. A partial deletion that empties the archive but leaves legacy chat could otherwise feed startup migration; test actual files and relaunch, not only live arrays. Selection metadata can only refer to a valid saved conversation.

Generated-reply save failure requires recoverable pending content without falsely calling it saved or repeating a provider request as a storage retry. Existing Library copies, source-message receipts, citations and backup/readable-export compatibility need regression coverage. Do not replace this with a rename-only repair and claim complete conversation persistence.

### Concrete next-batch acceptance checks

Read-only follow-up confirms `Lumen/Persistence/LocalStore.swift` already stages linked profile/goals and weight/today files through `BackupFileTransaction.prepare`, a captured storage revision and a same-main-actor installation callback. Assess reuse for archive/chat coherence instead of introducing an independently ordered pair of atomic files. `ConversationArchive.migrate` currently treats an empty archive as missing, so persisted `[]` and a truly absent archive need distinct treatment; a failed migration must preserve the readable legacy source for retry.

Before implementation, preserve this verification scope:

1. First send/new conversation: injected archive or mirror preparation/commit failure retains the original composer, leaves live arrays/selection and actual saved files unchanged, and starts no provider request. Retry stores the user message once before starting one request.
2. Rename: failure retains the editable title, existing saved title/search order/selection and exact message IDs. Retry and relaunch show the saved replacement; cancellation keeps the original.
3. Delete active/inactive/last conversation: failed commit retains visible/history/file state. Successful final deletion remains empty after relaunch even with old legacy chat bytes. Saved Library copies and confirmed-log receipts remain independently available.
4. Select/new: saved active metadata must resolve to an existing conversation or the explicit unsent state. No delayed selection or stale prepared transaction may replace newer user typing, deletion, reset or restore.
5. Returned reply: storage failure keeps the exact response/provider/reference packet available with an honest unsaved state and storage-only retry. It must not call the provider again, save a plan claiming a persisted conversation message, or append a duplicate. Preserve reply-to-origin ownership when navigation changes.
6. Pending work: delete/reset/restore and a newer saved revision invalidate stale prepared commits and late replies without recreating removed conversations. Preserve stopped-response behavior and independently entered new composer text.
7. Actual startup/files: legacy-only migration, existing empty/nonempty archive, unreadable/corrupt archive, interruption recovery and unrelated health persistence all need explicit outcomes. Do not silently substitute defaults for an unreadable saved archive or overwrite it during initialization.
8. Compatibility: unchanged old message/conversation decoding, backup/restore and readable export, literal user text, provider labels, selected Library snapshots and their current consent checks. Test actual Foundation files/relaunch plus controlled delayed transport; pure archive-array checks alone cannot prove durable/UI behavior.
9. Settings' **Clear coach conversation** directly assigns `health.chat = []` then calls unrelated `persist()`. Route this through the same checked conversation boundary with confirmation/failure feedback and late-reply invalidation; a successful rename/delete/send repair that leaves this setter unchecked is incomplete. The Assistant's toolbar New conversation entry point also needs the checked new/selection outcome, not only the history sheet.

Current `CoachView.send` calls ensureConversation, clears the composer, then appends unchecked before its Task; both active and inactive append paths need the same repaired boundary. `ConversationHistoryView` currently dismisses after selection/new and clears rename/delete state immediately. These remain source findings and planned checks, not Batch38 deliverables or passing evidence.

## Personal-context request and history provenance

`Lumen/Services/ChatCoachService.swift` constructs personal context before awaiting the provider. It rechecks Library passage consent/content and semantic-search settings after that await, but does not currently give personal context the same request/history provenance guard. `RecordRetrieval.history` protects Library references, not all personal notes that might be incorporated into prior prose. Batch38's saved-off context-builder check therefore proves only omission from fresh context; it does not prove recall of an in-flight request or removal from historical provider context.

Derive an explicit policy for changed/withdrawn personal notes during a request and for later history reuse, with compatible retained provenance and honest UI. Preserve user-authored questions and visible history; do not pretend remote inputs can be recalled. Verify through a controlled delayed transport and actual outgoing request/history contents before making broader privacy claims. No new provider/model/schema policy is implemented by this audit.
