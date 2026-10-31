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

The official BEIR NFCorpus archive is downloaded and matches its published MD5. `nfcorpus-source.json` records the archive/file hashes without redistributing text. `retrieval-protocol.json` is fixed before retrieval scores are inspected: calibrate on dev, record model/policy candidates before locally held-out test scoring, retain no-cutoff rankings and all misses/unsupported inputs, and separately check no-match/non-health/identifier cases and actual app fusion. Upstream training overlap is unknown. Development retrieval scores are now recorded below. Test retrieval scores remain uncomputed and no app cutoff/model is selected.

Current retained inputs are:

- `/tmp/LumenBatch26MedEmbedSource`:133MB source weights plus pinned configs/vocabulary; required for original-model comparisons.
- `/tmp/LumenBatch19ModelSource`:the existing45MB pinned baseline input; preserve it.
- `/tmp/LumenBatch26Probe/medembed-evaluation.mlpackage` and `.mlmodelc`:the canonical66MB evaluation package/compiled candidate from R3.
- `/tmp/LumenBatch26Probe/all-minilm-l6-v2.mlmodelc`:the compiled baseline for the coming comparison.
- `/tmp/LumenBatch26ModelEnv`:task-only Python environment needed for the next evaluation; no pip download cache was created.
- `/tmp/LumenBatch26NFCorpus`:verified archive/extracted public inputs; keep them outside Git.

The complete production-prepared corpus and native corpus/dev encoding are now verified; see the dev result below. The next safe action is to declare a supplementary development hypothesis before its scores, then check no-match/non-health/identifiers and actual app behavior before any promotion. Do not inspect test scores to rescue the missed gate. Do not rerun successful79-case checks without a new source/artifact concern. Selected-model hosting, explicit upgrade/legacy/storage behavior, app/native/Release validation and any continuing UI critique remain future gates. No AppStore/clinical/physical-device claim follows.

## Storage

About29GB was available after the scoped cleanup below. The original45MB MiniLM source and new133MB FP32 candidate are current inputs; no duplicate external model download is needed. The task-only Python environment was installed without pip cache. Keep source/provenance, useful compact outcomes, current model inputs and supplied skill. After required evidence reaches GitHub and all workers stop, remove obsolete graphs/raw vectors/build/cache output only within verified task-owned locations. Preserve other projects/processes, shared runtimes and global caches. The scoped cleanup below is now complete after GitHub confirmation.

## Complete development evaluation · raw-query candidate not promoted

All3,633 pinned public documents become8,239 passages through actual `RecordRetrieval.candidates`; no limit or unrepresented document is accepted. Both actual native encoders retain every9,166 passage window and encode all324 original dev queries. Offline document-max scoring has no live12-second budget or keyword fusion; it is not an app/clinical benchmark. Native corpus times are125.753s baseline and152.695s candidate on this Mac, not iPhone performance.

| Dev metric, no cutoff | MiniLM | MedEmbed | Difference |
| --- | ---: | ---: | ---: |
| nDCG@10 | 0.301666 | 0.316880 | +0.015214 |
| MAP@100 | 0.132910 | 0.140935 | +0.008025 |
| Precision@4 | 0.320216 | 0.334105 | +0.013889 |
| Recall@4 | 0.087128 | 0.089835 | +0.002707 |
| Recall@100 | 0.303592 | 0.317529 | +0.013937 |

The predeclared+0.02 nDCG gate is missed. No exception, model replacement or cutoff selection follows. Candidate nDCG improves for122 queries, worsens for90 and is unchanged for112.123 candidate queries have no judged-relevant top-four result, versus129 baseline;40 versus46 have none at100. Incomplete public judgments do not prove those results clinically irrelevant. Both score distributions retain strong relevant/unjudged overlap; the old0.42 cutoff does not transfer. Every dev query's metrics, top-four choices/judgments, first relevant rank and ranking digests remain in `baseline-dev-r1.json` and `medembed-dev-r1.json`; raw corpus/query text is not redistributed. `dev-decision.json` records the gate and test holdout.

Six corpus controls pass: duplicate corpus/native IDs, complete-index rejection at5,001 documents, retained overlong-query rejection, corrupted matrix digest and dropped mapping. The accepted/overlong query control also verifies exact relative model paths. Independent graded/AP/empty-result/tie-order/window-max oracles pass with pytrec-eval-terrier0.5.11. All1,294 existing logic checks pass after adding the research CLI mode to the verification executable. Production app/UI source is unchanged; no new app build or design score is claimed.

Failed initial vocabulary lookup, macOS alias path receipt defects, failed first path repair and corrected tie preparation are explicit in `dev-decision.json`. Receipt normalization proves the complete model file size/hash multiset unchanged and changes no vectors, inputs, mapping or timing. Native relative paths now come directly from the enumerator and pass the control. Exact original native producer, current tool hashes, corrected compact receipts and their original hashes are retained.

Keep `corpus-prepared`, `dev-input`, `baseline-corpus`, `candidate-corpus` and current native encoder under `/tmp/LumenBatch26Probe` for immediate further research, alongside the canonical models/source/environment/dataset listed above. Raw temporary report paths are historical if later cleaned; pinned public inputs and retained code reproduce them.

## Publication and scoped storage cleanup

Research/source/evidence commit `23ee57a20dd3f1a3f9fcd63d1ff89582103ac2e3` reached GitHub through `scripts/publish-batches.sh`; exact main read-back matched before deletion. All known task build/encoder workers were terminal. Cleanup removed119 known obsolete roots, including four superseded model package/compiled exports, task-only Swift package scratch, earlier vectors/full report copies, raw logs, smoke fixtures/hard links, two obsolete helper cache namespaces and two exactly timed diagnostic crashes. Symlinks were unlinked without following targets. `storage-cleanup.json` retains exact roots, ownership, inventory digest, hard-link accounting and reverified current input hashes.

Available bytes increased from28,618,870,784 to29,395,804,160: a measured **776,933,376-byte increase (about0.78GB)**. Removed files total1,172,674,610 logical bytes and1,048,768,512 unique-inode allocated bytes;914,030,592 allocated bytes had every hard link in the removal set. APFS/concurrent activity differs from the observed available-volume delta. The compact report replaces the disposable full temporary inventory after its publication.

The working repository, compact outcomes/source/producer maps, original/current model inputs, task Python environment, verified public dataset, prepared passages and complete current matrices remain. The current `EmbeddingCorpusProbe` helper cache is retained for immediate query-policy work; global/shared/other-project caches, simulators/runtimes and personal files are preserved. No new app build was run for cleanup. `current-tools-source-map.json` is the earlier compatibility checkpoint's map; `corpus-tools-source-map.json` is current for this development evaluation. The full goal remains active.

## Supplementary instruction and unsupported-query checkpoint

Read `instruction-challenge-decision.json` for the current result. The raw-query decision/protocol above remain frozen historical outcomes. One separately predeclared BGE instruction passes dev ranking:0.327284 nDCG@10 (+0.025618 baseline),0.350309 Precision@4 (+0.030093), all324 queries.127 query nDCGs improve,88 worsen,109 remain equal. `instruction-dev-r1.json` retains every case/top-four selection/metric/digest and `instruction-native-receipt.json` binds native query rows and exact weights/inputs.

The separate challenge has17 synthetic documents,17 directly supported questions and15 unsupported questions. Both models rank all supported documents first with no cutoff; no fixed cutoff meets the declared direct-support profile. At candidate0.75,16/17 supported are retained and2/15 unsupported get a topic; at0.85 only5/17 supported remain. `challenge-outcome.json` retains all32 full document rankings/grid results; `challenge-native-receipts.json` binds the actual native artifacts. Topic relatedness is not proof of direct support or clinical error.

Actual production keyword/local reply verification preserves32 valid/current contexts and17 sharing withdrawals. It finds all17 supported sources within four passages, but selects text for9/15 unsupported questions, including both absent identifier examples. Neighboring literal sample/invoice text is shown; no absent result is invented. `challenge-keyword-outcome.json` retains the actual local text and IDs. Prioritize literal identifier/source-selection protection before model integration. Test retrieval scores remain uncomputed; no app cutoff/query/model/UI change follows.

Four instruction controls pass (`instruction-controls.json`); raw-baseline rankings/metrics/grid are unchanged; current research Swift build and1,294 existing logic checks pass. `instruction-tools-source-map.json` is the current source map, while earlier maps remain historical. Reproduction is documented in scripts/embedding-probe/README.md. Keep the existing prepared public corpus/matrices/models/sources/env/current native helper and one package build directory for the immediate source-selection implementation; disposable raw result copies can be removed after this checkpoint reaches GitHub. The full goal stays active.


Batch26 instruction/challenge publication: `ff0673bb9d5175e7b99fc8249b117d73cd5ec5b7` reached GitHub through the batch publisher, with exact main read-back before cleanup. The separately frozen protocols/labels are preserved in `0a8e0b2` and `2c14538`. The instruction passes dev ranking only; literal identifier/source-selection work remains next and no app model/query/cutoff change is selected. Stopped-worker cleanup removes obsolete full ranking copies/logs/limit controls/bytecode and recovers a measured21,155,840 available bytes (about21.16MB). Current model/source/env/dataset/prepared corpus/matrices, native helper/cache and one package scratch remain for immediate source-selection implementation; all unrelated data remain. Details: Design/native/retrieval-quality/instruction-storage-cleanup.json. Raw temporary paths are historical; no cleanup-only app build was run. The full goal stays active.
