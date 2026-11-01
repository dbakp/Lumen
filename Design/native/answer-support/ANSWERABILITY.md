# Batch 33: extractive answerability development trial

**Decision: reject this fixed reader policy.** Public SQuAD 2 development reproduction passes, but neither frozen Lumen source pipeline meets the supported-answer requirement, and the stress cases expose unsupported source-label and unit answers. No production reader, model, query, cutoff, prompt, UI or schema changes. Application/build inputs remain the published Batch 31 version `73362aecdd0eaa4fd0e2952367e1c6f01e4f3ecc`.

The protocol, immutable answer aliases and eight stress cases reached GitHub before reader inference in `e87f49dbf7af6d2b5ab9c9bbb8a24083505f6fdd`. Protocol SHA-256 is `85b1e6ad885d7064cbda9b75d71111162467036f75a99c08ddd816b2a1be8b99`. No threshold, gold alias or denominator was changed after outputs. This follows Batch 32's negative finding that a relevance cutoff alone cannot satisfy its joint ranking/support criteria.

## Fixed experiment

One pinned `deepset/minilm-uncased-squad2` English extractive reader runs as upstream FP32 on this Mac CPU, four threads, eager attention and evaluation mode. It sees complete original questions and all overlapping context windows, with a 384-token sequence limit and at most 30 answer tokens. Legal answer tokens belong wholly to one original source-body region. Query, heading, padding and cross-source spans cannot become answers. Every original span has code-point and separately verified UTF-8 byte anchors. This is not native Swift `Character` parity or iPhone latency.

The null decision uses the minimum CLS start-plus-end score over all windows, minus the maximum legal span score. A difference greater than zero abstains; ties retain the span. It is an uncalibrated fixed decision rule, not a probability. Gold answers are separate files and never loaded by the inference runner. No training, app installation or CoreML conversion is performed.

## Complete public reproduction

All **11,873** official SQuAD 2 development questions finish: 5,928 answerable and 5,945 unanswerable, represented by 12,134 context windows. No incomplete, unscored or input-limit case is omitted.

| Group | Questions | Exact match | Token F1 | Empty answers |
|---|---:|---:|---:|---:|
| All | 11,873 | 76.189674% | 79.534118% | 4,814 |
| Answerable | 5,928 | 78.491903% | 85.190381% | 421 |
| Unanswerable | 5,945 | 73.894029% | 73.894029% | 4,393 |

This clears the predeclared reproduction sanity gates of EM ≥74, F1 ≥77 and unanswerable abstention ≥70%. The model maintainer already evaluates on this development set; this is **replication/development, not unseen generalization**. It is not clinical, multilingual, full-conversation or provider-grounding evidence. Official punctuation/article normalization is used only for this public benchmark, never the synthetic literal answers.

The complete pinned official evaluator was inspected before execution. Independent per-case EM/F1 agrees in all **23,746** comparisons; all **nine** aggregate values agree with the official CLI without a no-answer probability file or best-threshold search. `public-outcomes.jsonl.gz` retains every ID, literal output, status, candidate span, anchors, raw null difference and independent score. Every variable prediction/span field was checked against the raw run before compaction. See [attribution and output license](ATTRIBUTION.md).

## Frozen Lumen source pipelines and stress contexts

The original 32 self-authored questions run against both previously frozen source selections. The eight extra cases use provided contexts rather than native retrieval. These are development diagnostics, not independent clinical truth.

| Context pipeline | Complete supported | Unsupported nonempty | Cases with no eligible source |
|---|---:|---:|---:|
| Production baseline packet | 10/17 | 0/15 | 8 |
| Research reranked packet | 10/17 | 0/15 | 8 |
| Provided stress context | 2/4 | 2/4 | 0 |

Both native-source pipelines miss the ≥16/17 completion requirement. Their zero unsupported emissions includes eight empty-source cases each; learned no-answer evidence applies only to the remaining seven related-context negatives in each pipeline. All eight stress contexts have sources, so their abstention failures cannot be attributed to empty retrieval. Overall 72 cases produce 36 nonempty answers, 20 model abstentions and 16 explicit no-source results. All 56 eligible features are scored.

`synthetic-results.json` retains all questions, contexts, original owners, frozen labels and raw outcomes. The primary agent directly inspects all 72; `qualitative-review.json` distinguishes actual support/type failures from strict surface-form misses. The review changes no score or advancement decision.

- Ferritin and Tuesday fever abstain despite their selected sources. Sleep returns only `three times`, omitting duration. Train returns only the date, omitting `14:32`. Pan returns only its material, omitting the object.
- Baseline Monday contains the correct `no fever` statement plus additional true source wording. The paid invoice includes an unlisted prefix. Both remain frozen strict-alias failures; they are not false factual answers. Reranked Monday instead selects an allergy-note statement about absent prescription/dose/treatment: a wrong-source/topic answer, though the quote itself is present in that source.
- Reviewed Ferritin returns `Original saved`, not the reviewed result. Original Ferritin returns `Ferritin <5,0 µg/L`, preserving the complete original fact with an unlisted analyte prefix; this remains a strict miss without relabelling it as an incorrect value.
- Absent source label Evan produces the Mara-labelled `12.1 g/dL`. Missing Alpha unit produces numeric result `7.4` as a unit answer. The latter does not invent `mg/L`; it fails the requested type and missing-fact requirement. Source labels are not independently verified personal identities.
- Noor's complete result and TEST-B1 negation pass. The malicious saved dose instruction and absent TEST-B3 produce empty answers. These limited passes do not prove general injection resistance or identifier safety.

There are no unsupported nonempty explicit-absence statements in the negative cases here. A returned absence statement would still fail strict empty-output scoring, but would need qualitative distinction from an invented fact. The unrelated absence statement for positive Monday is separately identified above.

## Integrity and runtime evidence

- Seven named decoder controls pass, including 72 independent exhaustive-logit oracles, header/query/padding exclusion, cross-source rejection, finite-logit guards, null/tie behavior and literal Unicode/operator/unit byte round trips.
- Five tokenizer/source controls pass in each run. A separate enumeration verifies all **63,030** contiguous spans of 1–30 tokens across an ordinary context and the minimum 32-token context budget: no boundary answer of the declared maximum length disappears between windows.
- Three fixed first/middle/last singleton-versus-batch checks pass per run. Maximum differences are recorded in the run receipts; no tolerance above the declared `1e-4` is allowed.
- Thirteen hand-expected metric controls pass, including Unicode article boundaries for public scoring and literal negation/operator/unit/date constraints for synthetic scoring. The earlier 12-control receipt precedes the final Unicode-boundary case; no model policy changed.
- Re-preparing all six input/label/receipt files reproduces them byte for byte. Protocol, source selection and fixture artifacts match the pre-scoring publication. Complete pinned model/data receipts and producer hashes at inference start remain in `provenance.json` and run receipts; producer code is checked unchanged at completion.
- Model-forward-only time is **259.932476s public** and **0.631766s synthetic** on this Mac. These exclude loading, tokenization, padding, decoding and control replays. They are not whole-app or physical-device measurements.
- A read-only real Mac Foundation Models availability probe reports `appleIntelligenceNotEnabled`; English is supported, but no Apple model inference occurs and no system setting changes. This does not establish iPhone behavior.
- All **191** tracked application/build inputs match Batch 31. This research batch does not rerun or recharacterize the earlier 1,465 production checks, 28 actual pinned embedding-model checks, simulator/Release builds or native screenshots. No new design score is needed because the app UI is unchanged.

## Reproduction and next work

Use an environment with Python 3.12, torch 2.7.0, transformers 4.51.3 and NumPy 2.2.6. `prepare.py` requires a fresh, nonexistent workspace and downloads only pinned model/data inputs. Preserve or reconstruct the four frozen Batch 32 pool/score inputs listed in `protocol.json`; they remain the current source-selection inputs. Raw public data, weights and output bundles are task-owned disposable files after retained evidence reaches GitHub.

```sh
python scripts/answer-support-probe/prepare.py /tmp/LumenAnswerabilityReproduction
python scripts/answer-support-probe/decoder_controls.py /tmp/LumenAnswerabilityReproduction/decoder-controls.json
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TOKENIZERS_PARALLELISM=false python scripts/answer-support-probe/coverage_controls.py /tmp/LumenAnswerabilityReproduction
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TOKENIZERS_PARALLELISM=false python scripts/answer-support-probe/score.py /tmp/LumenAnswerabilityReproduction synthetic
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TOKENIZERS_PARALLELISM=false python scripts/answer-support-probe/score.py /tmp/LumenAnswerabilityReproduction public
python scripts/answer-support-probe/metric_controls.py /tmp/LumenAnswerabilityReproduction/metric-controls.json
```

Inspect the entire downloaded official evaluator before using `evaluate.py`. Then run `python scripts/answer-support-probe/evaluate.py /tmp/LumenAnswerabilityReproduction --output /tmp/LumenAnswerabilityReproduction/evaluation`. Evaluation intentionally refuses to overwrite outputs; the optional destination allows independent reproduction without replacing retained evidence. The final destination-option change replays to byte-identical results before publication. Its independent public scorer never chooses a new null threshold. Producer/data/model receipts must continue to match.

Next predeclare a complete-answer/claim-evidence approach that can handle compound questions, source labels, corrected-versus-original fields and absent facts. This fixed single-span reader is not sufficient. Do not repair its failures by fitting a new threshold or widening aliases after observing them. Separate any new development from later independent validation; retain all earlier failures and unchanged retrieval/privacy gates. General conversational synthesis, live providers, multilingual/clinical quality, signed devices, VoiceOver, privacy governance and release remain open. The full product goal stays active.

## Publication and scoped cleanup

Research commit `1f1bf2fb458151b8540c31dcce59959a0a31f53d` reaches GitHub through `scripts/publish-batches.sh`. A fresh fetch, exact main read-back and Git-blob comparison of every answer-support source/evidence file precede deletion. All workers are stopped. The three known disposable roots are removed: `/tmp/LumenBatch33Answerability`, `/tmp/LumenBatch33ModuleCache` and `scripts/answer-support-probe/__pycache__`. They contain 126 file paths, 222,002,296 logical bytes and 219,734,016 unique-inode allocated bytes, counting hard-linked allocation once. Available space increases **50,246,520,832 → 50,464,526,336 bytes**, a measured **218,005,504 bytes (about218MB)**. APFS/concurrent activity explains differences from file accounting.

Compact complete outcomes, controls, source/provenance and attribution remain in Git. Frozen Batch32 source-selection inputs and canonical research models/data/Python environment/vectors remain for future work, along with the supplied skill/archive and all unrelated data. No symlink target, shared simulator/runtime or global/system/browser cache is removed. No cleanup-only build runs. Raw paths are historical and the rejected QA weights/availability binary must be regenerated if needed. Exact inventory and retained-Git checks: `storage-cleanup.json`.
