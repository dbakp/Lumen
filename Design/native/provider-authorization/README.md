# Provider authorization · Batch42 baseline checkpoint

**Defects reproduced; production repair remains open.** This is a verified starting point for the next implementation, not a completed application delivery. Batch41 remains the latest accepted application batch. The full product goal is active.

Signed simulator BaselineR3 traverses the actual shared refresh decoder, Keychain/defaults writes, private route resolver, coach preparation and final Foundation transport. The DEBUG-only seam changes only a validated fixed synthetic token request's HTTP destination. No live account, credential, provider or arbitrary health history is used.

Ten scenarios produce ten token exchanges and nine chat requests, independently matched to the host audit, with zero hold timeouts:

| Mutation during held refresh | Observed pre-repair result |
| --- | --- |
| Unchanged control | Refreshed token stored; original route/model sends and accepts reply |
| Disconnect | Mode becomes on-device and refresh token is removed; late access/expiry writes occur and chat still sends |
| On-device mode | Late refresh and chat submission still occur |
| Endpoint replacement | The pending original packet goes to the replacement endpoint |
| Model replacement | The pending original packet uses the replacement model |
| Client or scope replacement | Late refresh writes and original packet sends |
| Model change then revert | Pending packet still sends; no generation detects the intervening change |
| Provider-related reset operations | Access/expiry are recreated after actual defaults/secret erasure; no chat sends because the endpoint was removed |
| Refresh failure | The expired access token is reused and chat sends |

`baseline-r3-report.json` records actual native observations; `baseline-r3-host-readback.json` is an independent live server read-back. Neither contains arbitrary prompts or token/header values. Synthetic credential classifications are fixed fixture names. The reset case exercises the actual provider-relevant reset operations, not the entire Settings UI or all reset domains. One original screenshot documents completion through the existing debug status overlay; it is not a product design acceptance screen.

## Boundaries and earlier failures

`baseline-source.json` and `baseline-instrumentation.json.gz` freeze212 inputs against starting checkpoint `16bf5fe560ae0c9c6cd8f140adffd757ed977ff2`. BaselineR1 fails before token traffic because its synthetic Keychain seed cannot be read back in the unsigned simulator build. No Security OSStatus was captured, so a specific underlying Keychain error is not claimed. BaselineR2 uses the same application source with ad-hoc simulator signing; seed/read/write and one outgoing request work, but the local server omits required choice index0 and Lumen correctly rejects that malformed reply. Its failure, report, host receipts and complete logs remain.

`baseline-source-r3.json` changes only the server to include index0; no application rebuild/authorization repair occurs between R2 and R3. `baseline-r2-build-identity.json` records actual executable identity and the simulated entitlement link input, including application identifier. Simulator entitlements live in a linked section; an empty code-signature dictionary alone does not prove their absence. Ad-hoc simulator success is not physical-device or live-OAuth acceptance.

Run `python3 Design/native/provider-authorization/audit-baseline.py` to reconstruct both source boundaries and verify the observed defects, failed attempts, matched packets, original screenshot hash and compressed archives. Baseline success means the old defects were reproduced. After repair, preserve these immutable snapshots instead of keeping a production legacy path or expecting this old-behavior test to pass against fixed sources.

## Next work

[The declared contract](protocol.md) and [implementation sequence](repair-design.md) cover checked atomic credentials, original account/route generation, refresh/login ownership and final handoff, actual provider labels and explicit checked key drafts. Implement and test those contracts before considering Batch42 complete. Newly inspected AI settings onChange/onAppear behavior is a source finding without runtime reproduction yet.

Repeat actual fixed scenarios plus cached/API-key/final-preparation, overlapping refresh, stale login and typed storage-failure controls; include Library/personal/transport regression and exact source/Release audits. Any changed provider UI requires the same continuing critic and actual main/compact normal/largest captures. Durable Health intent, acknowledged Watch delivery and broader evidence/provider/device/accessibility/privacy/distribution gates remain afterward.

Storage: one native/dependency/logic cache is reused. Keep the signed Debug cache for immediate repair work. Compact current evidence is retained; delete redundant completed raw bundles only after exact GitHub backup proof. No large fixture or model download is needed.
