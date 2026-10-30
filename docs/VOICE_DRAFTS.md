# Voice drafts

Assistant → **Speak a message** (microphone) opens a temporary voice draft. Lumen's built-in voice capture needs iOS 26 or later and supported on-device speech for the chosen language. The rest of the app retains its existing system requirements. Older systems can still use typed input or their keyboard's dictation.

## Speak, review, then use

Opening the screen checks language/device availability without requesting a microphone or a language download. **Start recording** requests microphone access, then starts capture only while Lumen is active. The UI shows actual elapsed time and live text, with a persistent **Stop recording** control. The latest 1,200 characters are a labelled live preview; the entire accepted transcript remains available for review.

Stopping ends the audio engine/tap before waiting for final text. Recognition is bounded to three minutes, with up to five seconds for the final response. Backgrounding, audio interruption or a changed route stops recording rather than automatically restarting it. Lumen sleep sounds pause for capture; their existing sleep timer continues, and playback can be resumed from Sounds. A failed start that captured nothing retains previously corrected voice text.

The stopped state leads with **Check your words**. **Edit text** opens a focused native editor. Unsaved editor changes have keep/discard choices. Editing resets **I checked names, numbers and units**. That acknowledgement starts off; **Use text** remains disabled until the current text is valid and checked. Starting over and dismissing a nonempty voice draft have separate keep/discard decisions.

**Use text** appends to the existing unsent message draft. It doesn't send a message or create health records. The target conversation and earlier typed draft must still match their captured identities; otherwise the insertion fails and the voice text can be copied. Explicit **Send** uses the configured assistant and existing consent/context rules. **Review health entries** and each health entry's confirmation remain separate, unchanged actions. No spoken number is interpreted as a clinical result by this feature.

## Speech, storage and privacy

The production path uses Apple's `SpeechAnalyzer`, preferring `SpeechTranscriber` where available and using `DictationTranscriber` for its supported language/device combinations. These analyzer modules process speech on device. No server-transcription fallback is added. Names, numbers, units, negation, language and punctuation can still be wrong: a finalized recognition segment isn't proof of accuracy.

A missing language has a separate **Download language** decision. Apple supplies those shared system assets; model installation is never started merely by opening voice input or pressing Start when a download is needed. Actual download progress is shown when iOS supplies it. Closing cancels Lumen's wait/request and releases its reservation when work stops. iOS can retry or finish a shared download and decides when unused shared assets are removed, so closing is not a promise of immediate disk reclamation. Only a device-local preferred language identifier is retained. On opening a new session after earlier work has stopped, Lumen releases its unused reservations, including any left by an interrupted launch.

Lumen writes no recording or temporary audio file. Captured buffers are owned copies in bounded queues; sample-rate/channel conversion feeds the analyzer's compatible format. Queue overflow stops processing instead of silently skipping audio. Accepted text is bounded to 8,000 characters, 32,000 UTF-8 bytes and 2,048 segments. Final hypotheses replace overlapping provisional text; conflicting/delayed final-range content cannot rewrite finalized words. Exact repeated finals don't duplicate a phrase. Invalid/overlarge packets leave the previous accepted text available with an interruption notice rather than silently clipping it.

Audio and unused voice text aren't part of app backups, readable exports or Library records. Closing releases them from the app session after workers stop. Used/sent text becomes ordinary editable message content, subject to the existing history/export/provider behavior. Copy text is an explicit system-clipboard action. Model assets are OS-managed and aren't bundled into or exported by Lumen.

## Composer behavior

Only an actual single appended keyboard Return edit or the keyboard's native submit action sends from the composer. A multiline paste or a programmatically inserted voice/quote draft doesn't invoke the former trailing-newline watcher. Keyboard submission is handled after the input callback completes its binding writes, with a matching conversation/current-draft guard, so submitted text clears without erasing new typing. Voice insertion preserves the existing typed prefix and trims only the new speech text's outer whitespace. The combined draft must fit the voice/health-entry review bound; an error leaves the earlier draft intact.

## Verification boundaries

Production logic checks cover result replacement/order/bounds, late conflicting results, target changes, multiline/empty/overlarge drafts, owned-buffer copies and actual generated-PCM resampling/drain without files. Native debug-simulator fixtures visibly say **Simulated speech. No microphone.** They run the same result buffer, review, target and composer paths but never capture audio or download a language. These fixtures are excluded from Release builds; they prove state/interaction and exact text handling, not acoustic recognition. The real availability path is checked separately without microphone or download consent. Exact outcomes and sources are in VERIFICATION.md and Design/CRITIQUE.md.

Signed-iPhone capture, multilingual/medical-word/number/negation accuracy, Bluetooth/route/interruption behavior, energy/latency, model download/cancel/release behavior under resource pressure, accessibility/VoiceOver and release privacy disclosures remain device/release gates. No clinical transcription benchmark or end-to-end live recognition is claimed from a UI fixture or unsigned build.

## Apple references

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) and [Apple's SpeechAnalyzer session](https://developer.apple.com/videos/play/wwdc2025/277/) describe the local module/input/result architecture.
- [Speech authorization](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition) distinguishes the older server-capable recognizer authorization from analyzer modules. Lumen uses the microphone permission for its analyzer path.
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory) and [downloadAndInstall](https://developer.apple.com/documentation/speech/assetinstallationrequest/downloadandinstall()) describe shared assets, reservations and deferred retries. [Releasing a reservation](https://developer.apple.com/documentation/speech/assetinventory/release(reservedlocale:)) doesn't promise immediate removal of system-managed assets.
