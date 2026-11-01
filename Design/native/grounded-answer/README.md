# Batch 34: complete answers with exact source quotes

**Reject this fixed generative model/prompt/evidence policy.** Every output has valid JSON and valid literal quote provenance, but some answers assign facts to the wrong test, label or sample, invent a missing unit, or treat a saved instruction as a prescription. Exact quote checking is not a claim-entailment or question-answering validator. No application model, UI, prompt, schema or cutoff changes.

Protocol, prompt and clause labels reached GitHub before generative outputs in `142da1c203c813a70256411cfea5bf613e24ee15`. Protocol SHA-256: `614a25920e72730f29aefc7256c6fdeae20e929aaa69c4a0a263a989df75f1f1`. All 72 frozen cases finish with one sample each; no retry, prompt repair, alias expansion or new threshold is selected after outputs. The public stage is **not run**, as required by the predeclared synthetic prerequisite. No public pass, independent validation or held-out score is implied.

## Fixed local experiment

The official [Qwen3-1.7B model](https://huggingface.co/Qwen/Qwen3-1.7B/tree/70d244cc86ccca08cf5af4e1e306ecf908b1ad5e), revision `70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`, runs locally through existing transformers 4.51.3/torch 2.7.0 on this 16GB Apple M1 Pro Mac. Its Apache-2.0 source/license and every selected file are pinned in the protocol and `model-source.json`. Direct downloads total 4,079,448,540 bytes; no duplicate model cache, conversion, fine-tuning or app installation is made. This model was selected for an actual local feasibility experiment, not as the production model or a state-of-the-art claim.

The pinned chat template disables thinking. Sampling follows the model card's documented non-thinking values: temperature 0.7, top-p 0.8, top-k 20, min-p 0. Each original case ID supplies a SHA-256-derived seed, with one sample and at most 512 new tokens. Complete original questions and all selected source bodies are preserved; there is no input truncation. All source IDs are request-local opaque labels. Gold, previous model answers and expected original document IDs never enter the model payload. The eight no-source cases per native-source pipeline still receive real model calls.

Weights are converted from upstream BF16 storage to FP16 for MPS, an explicit protocol choice rather than a CPU/FP32 equivalence claim. Three fixed non-quality probes compare final-token logits against sequentially loaded/unloaded CPU FP32. All are finite, all three top tokens match, and maximum differences are 0.071120, 0.082473 and 0.115649, below the predeclared 0.25 limit. There are no missing, unexpected or mismatched model keys. This limited numerical check does not prove full-generation parity. MPS fallback is not enabled.

The output contract requires a boolean `answerable`, an answer string and source-ID/quote pairs. It rejects duplicate/extra keys, invalid types, nonfinite JSON, incomplete generation, oversized output, unknown owners, altered text and nonunique source quotes. Answer/evidence bounds are 4,096 UTF-8 bytes/eight entries; quotes are at most 2,048 bytes; response JSON is at most 32,768 bytes. `answerable=false` requires empty answer/evidence. Anchors retain original code-point and separately round-tripped UTF-8 byte ranges. **These checks establish provenance only.**

## All-case outcomes

| Context pipeline | Literal clauses complete | Unsupported nonempty | Mechanically valid | Unchanged whole-alias diagnostic |
|---|---:|---:|---:|---:|
| Frozen production source packet | 16/17 | 3/15 | 32/32 | 2/17 |
| Frozen research-reranked packet | 16/17 | 3/15 | 32/32 | 2/17 |
| Provided stress context | 4/4 | 4/4 | 8/8 | 2/4 |

The two completion columns intentionally differ. The new clause metric was declared before generation for free-form answers: all required literal parts must occur in the answer and in anchored quotes from the correct original owner. It does not replace or retroactively improve Batch 33's exact whole-answer aliases. Verbose sentences often fail those old aliases while containing the requested facts. The walk's faithful `thirty minutes` paraphrase still fails the new frozen literal `thirty-minute` clause; no alias is widened. These scores are not a direct numerical improvement over Batch 33's different strict metric.

Sleep now includes duration and waking count, train includes date and time, and all four provided-context positives preserve their requested facts. Nevertheless, the zero-unsupported-output requirement fails in both native-source pipelines and all four negative stress cases. All 16 empty-source inputs produce real-model empty answers; these are separately identified from the misleading-source cases.

The primary agent directly reviews all 72 questions, original source bodies, raw answers and quotes. The ten nonempty negative answers comprise **six wrong factual attributions** and **four correct explicit-absence statements that violate the fixed abstention contract**:

- Both calcium questions receive `not detected` from TEST-AX1 wording, despite no calcium test being identified. The quote is real; the test attribution is false.
- Both vitamin D and both LDL questions correctly say the requested result is absent from the provided sources, but set `answerable=true` and return nonempty content. They fail strict abstention; they do not invent vitamin D/LDL measurements.
- The saved-instruction dose is returned as a prescribed dose while the attached quote expressly says it is not a prescription. This is a failed synthetic saved-instruction diagnostic, not an actual prescription or patient record.
- Absent label Evan receives Mara's result; absent sample TEST-B3 receives TEST-B1's wording; missing Alpha unit receives Beta's `mg/L`. Correct file/source IDs and exact quotes do not bind the answer to the requested entity, sample or field. Labels are not independently verified identities. The supplied-context B3 case does not establish a regression in native identifier exclusion.

Additional wording is retained honestly: Ferritin adds an unrequested comparison with the displayed reference interval, not independently established clinical normality; one plant answer adds irrelevant manual water-log facts without explicitly proving any plant watering quantity/date. Other verbose correct-source answers remain old strict-alias misses. See `qualitative-review.json`; no review annotation changes the frozen scores.

## Integrity and source boundaries

- All 72 generations finish on EOS, with 4,315 finite-logit generation steps and no length/input limit or dropped case. Synchronized MPS generation takes **556.068869 seconds**, including sampling/finite guards but excluding model loading, CPU probes, tokenization and JSON validation. This is not iPhone, native-app, energy or whole-workflow timing.
- All 23 hand-expected contract controls pass. One deliberately false claim with a real quote passes mechanical validation, documenting the semantic limit rather than hiding it.
- All 216 post-output reviewed case comparisons agree with the automated mechanical/clause/alias results. All 72 original payloads, rendered prompts, token counts, seeds and EOS-trimmed raw outputs replay; all 56 quote anchors are independently enumerated and all 4,315 generated IDs remain in range. This reviewed expectation matrix is an audit, not blind/held-out evaluation.
- Independent replay R1 mistakenly reuses sorted pretty-evidence JSON key order, causing a prompt-hash mismatch. R2 restores the original `id,title,savedText` rendering order, and every replay passes. No actual model input, prompt, gold, inference, metric rule or gate changes. The failed attempt remains in `producer-logs.json`. The exact original input/output JSONL bytes are additionally retained in compact gzip, preserving key order and raw hashes.
- Complete source/output/seed/token evidence is in `synthetic-results.json`, with raw archives, model/source receipts, exact producer hashes, controls, full compact logs and separate final `decision.json`. The machine result's pending-semantic flags describe that automated step; final review/decision is separate and complete.
- Every 191 tracked application/build input remains published Batch 31 (`73362aecdd0eaa4fd0e2952367e1c6f01e4f3ecc`). There is no new app build, production test run, design score, Apple model, real provider, clinical, multilingual or physical-device proof. Prior verification keeps its exact earlier source/runtime boundary.

## Reproduction and next work

Use the recorded Python/torch/transformers runtime on a compatible Mac with sufficient free memory/storage. The fresh-workspace preparer pins every download. `run.py` requires the declared numerical controls before quality calls, writes every raw sample before evaluation and refuses accidental output replacement. Its explicit resume path is for missing records after a terminal process, not quality resampling; no resume is used in this run.

```sh
python scripts/grounded-answer-probe/common.py /tmp/LumenGroundedReproduction
python scripts/grounded-answer-probe/contract_controls.py /tmp/LumenGroundedReproduction/contract-controls.json
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TOKENIZERS_PARALLELISM=false python scripts/grounded-answer-probe/run.py /tmp/LumenGroundedReproduction
```

`evaluate.py` writes a fresh evidence result and refuses to overwrite existing results. Independent replay expects the retained reviewed run; fresh stochastic outputs are not promised bit-identical on another runtime. Do not rerun quality answers to obtain a better sample or fit a new prompt to these known failures. No conditional public runner is invoked or required after this failed prerequisite.

Future answer support needs question/claim binding for entity, field, negation and saved instructions, beyond literal quote provenance. Any new complete policy needs a separately declared evaluation and later independent/provider/native validation. Continue the broader data editing/reconciliation roadmap as well; another passing quote parser is not a substitute for the full assistant. Live providers, clinical/language quality, signed Health/Watch/voice devices, VoiceOver, privacy governance and release remain open. The full goal stays active.

## Publication and scoped cleanup

Research commit `c8746f0586d66513cbce25190214a6961d9d720a` reaches GitHub through `scripts/publish-batches.sh`. Fresh fetch/main read-back and exact Git-blob comparisons cover all grounded-answer source/evidence and updated handoff/roadmap/verification before deletion. All workers are stopped. Cleanup removes only `/tmp/LumenBatch34GroundedAnswer`, its separate `/tmp/LumenBatch34GroundedAnswer-fetch.log` and `scripts/grounded-answer-probe/__pycache__`: 28 disposable file paths, 4,079,577,271 logical bytes and 4,111,872,000 unique-inode allocated bytes.

Available space increases **44,064,141,312 → 48,176,177,152 bytes**, a measured **4,112,035,840 bytes (about4.11GB)**. APFS/concurrent activity differs from file accounting. Exact raw input/output bytes remain in the two compact Git archives, alongside readable outcomes, review, controls and source/model provenance; rejected weights and raw workspace are no longer local. Frozen Batch32 inputs, canonical research source/models/data/Python environment/vectors, supplied skill/archive, all unrelated user data and primary/Watch/Taskfold/shared simulators/runtimes remain. No symbolic-link target or global/system/browser/application cache is removed, and no cleanup-only build runs. Raw temporary paths are historical; regenerate rejected weights only if a later task actually needs them. Exact inventory and retained-Git checks: `storage-cleanup.json`. The full product goal remains active.
