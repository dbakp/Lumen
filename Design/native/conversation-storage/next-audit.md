# Next audit · personal-context request and history provenance

This is a predeclared continuation scope, not an implemented privacy repair or an acceptance result. Batch39 checks conversation persistence and request ownership; it does not establish recall of provider input or personal-note provenance in reused history. Preserve the existing Library consent/reference rules.

## Observed boundary

`ChatCoachService.reply` builds personal context before awaiting the selected provider. It checks Library passages and search settings before and after that await. Its personal-context path does not yet apply an equivalent revision/content guard to the returned reply or to later history reuse. `CompanionStore.personalContextRevision` already protects checked note editing, and changes on reload/reset; that editor guard is separate from the request lifetime.

`RecordRetrieval.history` filters Library-referenced assistant messages. That alone cannot identify every old assistant message whose prose incorporated personal notes. User-authored questions and visible saved history must remain intact. Turning sharing off omits fresh context but cannot recall input already sent to a provider.

## Declare the policy before implementation

Define the snapshot identity of the personal notes actually included in a request. State what happens when sharing, note content, reset or restoration changes during search, an in-flight request, or a retained reply's storage retry. Define compatible provenance for future history, and conservative treatment of legacy assistant replies whose personal-context provenance is unknown. Preserve literal visible messages, origin ownership and saved Library/confirmed-entry copies. Do not solve historical reuse by deleting user questions or silently erasing conversation history.

## Required evidence

1. A controlled delayed provider receives a unique synthetic note canary only when the committed sharing choice permits it. Unsaved editor changes must not change the outgoing packet.
2. Withdraw or edit notes while a response is held. Inspect actual outgoing instructions and history, release the old response explicitly, and verify the declared reply policy, source label, saved packet and next request after relaunch. A request counter alone is insufficient.
3. Change notes while Library search is suspended, and while a returned reply is retained after a real storage failure. Verify each declared boundary without a second provider call on storage-only retry.
4. Exercise compatible legacy and new messages through encrypted/readable recovery. Unknown provenance cannot become a positive sharing claim. Exact Unicode, user messages and separately saved copies remain intact.
5. Check the explanation and recovery route on main and compact phones, normal and largest text, with actual keyboard evidence if editing is involved. Use the same continuing design-review workflow and record exact source boundaries.

Keep controlled transport evidence synthetic and bounded; redact credentials and never publish personal notes. After this coherent audit/repair, continue durable Health save/delete intent and identity-preserving acknowledged Watch delivery. Physical-device, live-provider, clinical, VoiceOver and distribution gates remain separate. The full product goal remains active.
