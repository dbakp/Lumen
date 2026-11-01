# Batch30 · complete, bounded provider responses

The former compatible-provider route loaded an unbounded HTTP body with a shared session and could return ordinary-chat prose whose finish reason reported an output limit. The new shared transport accepts only one complete assistant text choice, rejects refusals/tool payloads/ambiguous or malformed JSON, limits encoded requests/decoded body accumulation, refuses redirects and uses a private ephemeral request lifetime with cancellation and timeouts. The [contract](../../../docs/PROVIDER_REPLIES.md) records compatibility and memory boundaries.

- `logic-r1.json`:1,425 production checks, including27 new parser checks. No networking in the ordinary executable suite.
- `transport-r1.json`:15 actual URLSession loopback checks, including exact-limit acceptance, byte-split Unicode, headerless oversize rejection, redirect refusal, pre-network request rejection, cancellation and idle timeout.
- `server-summary.json`: route/event counts only; no request body/header/credential retained. No redirect-target or oversized-request endpoint was reached. Each of the four native HTTP routes was reached once.
- `native-captures.json` and `native-r1/`: four useful originals with hashes/timestamps. NativeR1 passes107.208s,1test,0failures/skips/recorded runtime warnings. It uses the actual HTTP/client transport boundary with synthetic data and includes a complete-response control, cancellation, persistence and ordinary lookup after removing the adapter.
- `release-audit-r1.json`: unsigned generic-iOS Release, minimumiOS18, no model packages and16 specifically checked development markers absent.
- `source-r1.json`:257 tracked/new code/test/build/resource/script inputs, including both unchanged Shared Swift files. No source change follows final checks/builds.
- `verification.json`: exact scope, log hashes, server reset note, source boundaries and remaining gates. Both simulator/all-five-product and unsigned Release builds pass.

The existing app screens and product wording are reused; no new interface/design score is claimed. The image display tool resized1206×2622 originals to942×2048. Frames811/812 contain ordinary scroll/transition edges, so they are not complete-footer or Stop-control layout proof. Test assertions, server receipts and the complete-response control establish behavior; no live provider/model or physical device was tested. Server-side idle keepalive resets after client closure are retained as a compact note, not relabelled as silent console output.

Completion and source identity do not establish claim support or clinical correctness. No model/query/cutoff/schema/prompt or token-budget change; Apple Foundation Models remains separate. The seven frozen unsupported-topic selections and broader provider/clinical/language/device/accessibility/privacy/distribution gates remain open. Raw temporary paths become historical after publication and scoped cleanup.
