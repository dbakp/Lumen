# Batch32 · question/passage relevance trial

**No app model or cutoff is promoted.** One small joint question/passage reranker improves public development ranking, but no declared policy also meets the unchanged direct-support selection profile. This is a completed negative development decision, not clinical validation or a shipped model replacement.

The [protocol](rerank-protocol.json) reaches GitHub as `cd180fa926d794566b83faabbec0dac3c049a132` before scoring. The [decision](rerank-decision.json), [all324 public outcomes](rerank-dev.json) and [all32 synthetic outcomes](rerank-challenge.json) retain every cutoff, selected source, grade, per-query metric and regression. Production remains application commit `73362aecdd0eaa4fd0e2952367e1c6f01e4f3ecc`.

## Experiment and result

The fixed model is `cross-encoder/ms-marco-MiniLM-L6-v2`, revision `233902d25c440f23af6f7d6e94d2946bac0bee0a`,22,713,601 parameters. Only the pinned safetensors/config/tokenizer/card files are downloaded:91,819,431 bytes. Every file matches its upstream Git blob or LFS SHA256; Apache2.0 metadata and exact hashes are in [the source receipt](rerank-model-source.json). No duplicate bin/ONNX/OpenVINO weights are downloaded.

Use actual current native first-stage candidates, original-query language eligibility, pinned MiniLM cosine0.42 and keyword-leading RRF. Re-score at most64 candidates per question with the complete original query and existing title-prefix160/excerpt text. Every paired input is kept whole or windowed without query truncation; explicit overlength errors cannot silently disappear from denominators. The actual native selector creates final four-excerpt/two-per-record/non-overlap packets. Production source, model/query/cutoff, metadata and UI remain unchanged.

| Raw-logit cutoff | Public nDCG@4 | Change | Precision@4 | Supported hit@4 | Unsupported selecting sources | Both gates |
|---:|---:|---:|---:|---:|---:|---|
| None |0.357902 |+0.021783 |0.332562 |17/17 |7/15 |Fail |
|−8 |0.356458 |+0.020339 |0.330247 |17/17 |3/15 |Fail |
|−6 |0.350105 |+0.013986 |0.324074 |17/17 |2/15 |Fail |
|−4 |0.339386 |+0.003267 |0.312500 |17/17 |1/15 |Fail |
|−2 |0.319926 |−0.016192 |0.288580 |16/17 |1/15 |Fail |
|0 |0.289219 |−0.046899 |0.253858 |16/17 |0/15 |Fail |
|2 |0.225542 |−0.110577 |0.192901 |14/17 |0/15 |Fail |
|4 |0.170815 |−0.165304 |0.144290 |11/17 |0/15 |Fail |
|6 |0.124063 |−0.212056 |0.104167 |8/17 |0/15 |Fail |
|8 |0.089172 |−0.246947 |0.077160 |2/17 |0/15 |Fail |

Baseline public nDCG@4/Precision@4 is0.336119/0.314043. The separately declared public gate is+0.02 absolute nDCG@4 without Precision@4 regression. The unchanged synthetic profile requires at least90% supported hit@4 and zero unsupported selections. Only no-cutoff/−8 pass the public gate; only0 passes the support profile. At0 the lost supported question is **What was the recorded hemoglobin?**; public changes are43 improvements,78 regressions,203 unchanged. No-cutoff changes73/48/203. Threshold8 retains two explicit identifier-coverage errors in the synthetic outcome. No finer cutoff or gate exception is tried.

All324 original public-dev questions remain in the denominator, including78 unchanged recognizer-language keyword fallbacks.243 English questions receive13,357 scored pairs; three have no first-stage pool. The synthetic set supplies59 pairs over24 questions; eight have no eligible pool. All356 unchanged baseline source packets, methods, language and statuses match the published replay. No held-out queries/judgments/scores are used by this trial. Public judgments measure document relevance; synthetic labels identify directly supporting saved facts. Neither is independent clinical answerability.

## Verification and source boundaries

- Upstream FP32 CPU evaluation, four threads, one raw relevance logit per pair; never a calibrated probability. All13,416 paired tokenizations match direct upstream tokenizer outputs. All inputs fit one window in these datasets; this does not establish native long-window/CoreML parity. Six fixed singleton/padded-batch score comparisons agree within1e-4, maximum difference9.5367431640625e-7.
- Actual Mac CPU inference takes217.561927s for13,357 public pairs and0.395533s for59 synthetic pairs, excluding load/tokenization/indexing. No iPhone/CoreML/cache/live-budget or whole-app latency claim.
- Every selected native source is current/valid.170 expected-source withdrawals and170 carried-source exclusions pass across all10 cutoffs. Both absent-ID queries stay empty.
- [Fourteen rejection controls](rerank-controls.json) include changed protocol/config/model pins, source text, missing/duplicate/reordered/nonfinite scores, wrong query/prepared identities and forged language/index-error states. Self-consistent outer hashes cannot bypass live-source validation.
- [Independent metrics](rerank-metric-controls.json) verify10,692 per-query values and74 aggregate/paired-count comparisons across3,564 complete query/policy cells. Direct graded-DCG,Precision@4,Recall@4 and hit@4 calculations agree with pytrec-eval, retaining empty results. Existing graded/empty/tie/window metric oracles pass.
- Default production checks pass1,465 in Release BuildR3. Only research-input validation changes in BuildR4; default checks and all191 application/build inputs remain unchanged. No new app build or design review is claimed for research-only changes. Exact final tool/package hashes and executable receipt are retained.

BuildR1 fails because a workspace-initializer closure captures an instance property before all stored properties are initialized. A local source label repairs that research initializer. BuildR2 passes; R3 adds frozen-protocol binding and complete withdrawal checking even for cutoff rejection; R4 validates actual language/index/error state rather than trusting saved flags. R3/R4 synthetic outcomes match exactly. Earlier source hashes and exactly reversible producer patches remain in [the boundaries](rerank-producer-boundaries.json); failed builds are not relabelled.

An initial read-only public baseline check includes the previous report's evaluation-only `judgment` annotation in its source comparison. The corrected reader accepts only that known annotation outside the exact six native source fields; all324 public and32 synthetic packets/statuses/languages match. The reporting pass later adds explicit per-query metrics/grades without changing any aggregate outcome, inference or native selection. Public metric loading reads only pinned dev judgments and existing dev-only pools, not the combined raw query file. [Verification](rerank-verification.json) and [producer receipts](rerank-producer-logs.json) retain these exact scopes.

## Next work and storage

Investigate question/answerability or explicit claim evidence separately from passage relevance under a new predeclared protocol. Preserve supported facts, exact identifiers, source limits/consent/currentness and all failed gates. Do not tune another scalar cutoff to the hemoglobin miss or present topic relatedness as support. Useful unthresholded ranking can remain research input for an end-to-end reading/abstention trial; it does not become an app candidate by renaming a gate.

Keep the current small first-stage pools and raw logits for that next experiment, plus existing canonical models/vectors/dataset/environment and the supplied design skill. Once source/evidence reaches GitHub, remove obsolete Batch32 build output, rejected downloaded weights, duplicate reports, raw logs/control bundles and producer mirrors with stopped workers. Exact paths and measured cleanup follow in the storage ledger; raw paths then become historical. No CoreML conversion/install, provider/clinical, language, signed-device, VoiceOver or privacy/distribution gate is closed by this trial.
