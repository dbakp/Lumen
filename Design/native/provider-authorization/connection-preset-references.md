# Connection preset sources · 3 November 2026

Checked official pages before replacing the key-writing settings form:

- [OpenAI GPT-4o Mini](https://developers.openai.com/api/docs/models/gpt-4o-mini) marks the model deprecated and lists Chat Completions/text/image input support. [GPT-4.1 Mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini) is also marked deprecated. Do not present either as a fresh default. Preserve existing installed values until the user explicitly edits/saves; expose the model field and provider model documentation. This is not proof of account access or live behavior.
- [Google OpenAI compatibility](https://aistudio.google.com/docs/openai) documents the compatible endpoint and currently uses `gemini-3.8-flash`. [Google deprecations](https://aistudio.google.com/docs/deprecations) lists `gemini-2.0-flash` shutdown on1 June2026. Use3.8 only for an explicit new Google AI Studio draft preset, without silently replacing existing model IDs.

The current request shape remains compatible chat completions. A user-selected model must support that shape and the required feature; Google OAuth still requires an appropriate native client, scopes and token-accepting gateway. Synthetic checks prove local boundaries only. No live request or real credential was used for this documentation/implementation work.
