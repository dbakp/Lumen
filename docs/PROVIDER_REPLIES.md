# Complete, bounded compatible-provider replies

Batch30 hardens the existing OpenAI-compatible Chat Completions route used by key/OAuth coaching, meal analysis, multiweek-plan proposals and the connectivity test. It does not change provider selection, models, request prompts, output-token budgets, Apple Foundation Models, clinical interpretation or Library ranking.

## Accepting a response

The configured endpoint must return a successful HTTP response directly and one unambiguous, complete JSON choice at index0. The message must have the assistant role, nonblank string content and `finish_reason: stop`. Truncated (`length`), filtered, tool/function-call, missing/unknown finish reasons, nonempty/malformed refusals, tool payloads beside ordinary prose, malformed/duplicate-key JSON, invalid UTF-8 and unexpected envelope shapes are rejected. Optional refusal/tool fields can be absent, null or explicitly empty. Accepted content preserves internal characters, whitespace, numbers and units; only outer whitespace is trimmed. The app does not execute tools from this endpoint.

The distinction between a completed response, an output limit and a tool request follows the [official OpenAI Chat Completions response contract](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create), checked1November2026. Compatible gateways must supply the same required choice/role/completion metadata. The previous ordinary-chat path could accept partial text even when its finish reason reported an output limit. Scheduled plans already required a complete finish; the shared path now applies that prerequisite consistently.

A completed response is not proof of truth or source support. After transport acceptance, coaching still checks current Library/settings state and applies Batch29's current-request citation gate. Uncited general conversation remains allowed, and even a valid current citation can accompany an unsupported claim. Live-provider answer quality, clinical suitability and multilingual/device behavior remain open gates.

## Bounds and request lifetime

The encoded request body is limited to12MB. Before encoding, input text is limited to12MB and an optional image to8MB. The decoded response-body accumulator is limited to1MB, with an early declared-length check and an independent byte-count check for missing/misleading/chunked lengths. The exact1MB response boundary remains usable; larger responses are rejected rather than truncated into apparent answers. JSON depth/node/duplicate-key/UTF-8 checks reuse the existing bounded literal parser. These limits do not establish a whole-process memory ceiling: Foundation/TLS buffers and already-saved application inputs are separate.

Each request uses an ephemeral session without a URL cache, cookie store or credential store. The caller's explicit Bearer authorization remains part of the request. Redirects are refused; configure the final responding endpoint rather than relying on a gateway redirect. Request idle time is capped at60seconds and session resource time at90seconds. Task cancellation is checked before networking, during body accumulation and around parsing; the private session is invalidated/cancelled on exit. A stopped local task cannot recall a request already received by a server.

Rejected responses reuse existing caller behavior: coaching uses its current local lookup/guide; structured meal/plan callers receive no generated proposal; connectivity testing receives no successful answer. The displayed fallback label describes the answer's source, not whether a failed remote attempt previously received context. No new product interface, layout or wording is introduced.

## Reproducible synthetic verification

`ProviderReplyChecks.run` exercises the production parser without networking. The explicit integration probe uses the same production transport with the task-owned loopback server:

```sh
python3 scripts/provider-reply-server.py --report /tmp/LumenProviderReplyServer.json
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --scratch-path /tmp/LumenProviderReplyBuild LumenLogicChecks --provider-transport-check http://127.0.0.1:48731 /tmp/LumenProviderReplyProbe.json
```

Start the server only for the check, stop it afterward, and remove the disposable reports/build output after retaining useful compact outcomes. It binds only127.0.0.1, uses synthetic payloads, and retains only route/event counts. It never records prompts, source excerpts, headers or credentials. The probe is explicit; the ordinary logic suite makes no network requests.

The Debug simulator-only `-providerTransportUITestMode` adapter calls the actual `LLMClient.complete` route against that server. It sends only a synthetic request-specific ID, never the normal health summary/history/excerpts. The native test must include a complete-response control and matching server receipts so a broken or blocked connection cannot masquerade as successful incomplete-response rejection. The Release audit excludes the adapter, fixed loopback endpoint and synthetic-model marker. Exact evidence and source boundaries are in [the batch record](../Design/native/provider-replies/verification.json).
