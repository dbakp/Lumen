# Batch26 · retrieval-quality investigation · in progress

Batch25 application `f190b1d` and checkpoint `f102497` remain published. The app/search model/threshold/UI are unchanged. This investigation follows [the acceptance contract](../../../docs/RETRIEVAL_QUALITY.md); the full product goal remains active.

## Findings so far

- The actual pinned MiniLM encoder's36 input configurations retain the original nine-case miss. Manual compact questions/body-only inputs do not recover ferritin and weaken some other associations. No question rewrite is selected.
- Upstream MedEmbed-small-v0.1, revision40a5850d046cfdb56154e332b4d7099b63e8d50e, is downloaded with immutable URLs and individual hashes. The original FP32 declared CLS/normalized encoder ranks ferritin above the kitchen decoy on the known example. Its scores have a different distribution; reusing0.42 would admit unrelated text. No cutoff/model is selected for the app.
- First FP32 trace→FLOAT16 conversion compiles but fails native production-encoder validity checks. A direct synthetic-token inspection records384/384 NaNs. Keep this failed result and conversion warnings distinct from the repaired attempt.
- An all-FLOAT16 PyTorch tracing attempt fails conversion because layer-normalization epsilon/gamma types disagree. A subsequent compile/prediction was incorrectly attempted without a model; this was a harness sequencing error, not a second app-vector failure. The chain now stops at the first failed dependency and the diagnostic catches errors without creating a top-level crash.
- The repaired export retains original FP32 weights and replaces only the padding-mask representation with finite−10000 for padded positions/zero for real tokens. That representation matches original FP32 outputs exactly across40 texts. Native CoreML FLOAT16 outputs are finite on all40, minimum cosine0.99998624 and maximum element difference0.00103087 against the unmodified upstream FP32 model. This is numerical sanity, not clinical/device validation. Converter warnings remain recorded.

## Verified compatibility checkpoint

The portable recipe's canonical candidate is `conversion-r3.json`. Its finite-mask representation is identical to the original upstream FP32 outputs across85 passage windows. Native79-case R3 passes154 query/passage vector comparisons: minimum cosine0.9999746616, maximum element difference0.0015715063, zero token/window/mask/status discrepancies. All outputs returned by the production encoder are finite. Exact reference/native report hashes, policy and every case are in `parity-r3.json`.

The same public tools reproduce all36 published-MiniLM input configurations to rounding (maximum score difference2.23e-16). Source validation binds the immutable checked-in manifest, rejects a forged receipt and symlinked root, and successfully exercises a201-byte missing-file download while reusing hard-linked cached weights. Deliberate vector/window corruption is rejected by the comparator. These integrity checks are separate from model-quality claims; see `tool-integrity.json`.

The original R2 reference and R3 export producers are retained and hash-match their source map. Current tools strengthen input verification without changing conversion mathematics. [Reproduction instructions](../../../scripts/embedding-probe/README.md) describe the actual production-source CLI, fixed source pins and offline upstream comparison. The app, installed model, threshold, user data and UI remain unchanged; all task download/export/probe workers are terminal. No app build/design review was needed for this research-only change.

## Resume the broader quality work

The official BEIR NFCorpus archive is downloaded and matches its published MD5. `nfcorpus-source.json` records the archive/file hashes without redistributing text. `retrieval-protocol.json` is fixed before retrieval scores are inspected: calibrate on dev, record model/policy candidates before locally held-out test scoring, retain no-cutoff rankings and all misses/unsupported inputs, and separately check no-match/non-health/identifier cases and actual app fusion. Upstream training overlap is unknown. No dev/test retrieval score or new app cutoff has yet been computed or selected.

Current retained inputs are:

- `/tmp/LumenBatch26MedEmbedSource`:133MB source weights plus pinned configs/vocabulary; required for original-model comparisons.
- `/tmp/LumenBatch19ModelSource`:the existing45MB pinned baseline input; preserve it.
- `/tmp/LumenBatch26Probe/medembed-evaluation.mlpackage` and `.mlmodelc`:the canonical66MB evaluation package/compiled candidate from R3.
- `/tmp/LumenBatch26Probe/all-minilm-l6-v2.mlmodelc`:the compiled baseline for the coming comparison.
- `/tmp/LumenBatch26ModelEnv`:task-only Python environment needed for the next evaluation; no pip download cache was created.
- `/tmp/LumenBatch26NFCorpus`:verified archive/extracted public inputs; keep them outside Git.

The next safe action is a complete production-prepared corpus index and offline native corpus/dev-query encoding for both models, then metric/calibration analysis under the frozen protocol. Do not rerun successful79-case checks without a new source/artifact concern. Selected-model hosting, explicit upgrade/legacy/storage behavior, app/native/Release validation and any continuing UI critique remain future gates. No AppStore/clinical/physical-device claim follows.

## Storage

About28GB was available at the last check. The original45MB MiniLM source and new133MB FP32 candidate are current inputs; no duplicate external model download is needed. The task-only Python environment was installed without pip cache. Keep source/provenance, useful compact outcomes, current model inputs and supplied skill. After required evidence reaches GitHub and all workers stop, remove obsolete graphs/raw vectors/build/cache output only within verified task-owned locations. Preserve other projects/processes, shared runtimes and global caches. No Batch26 cleanup has occurred yet.
