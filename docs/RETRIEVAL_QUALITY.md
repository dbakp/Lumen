# Retrieval quality · Batch26 investigation

The full product goal remains active. Batch25 is the latest published application. This work investigates the retained iron-stores/ferritin miss and broader retrieval quality. No new model, threshold, synonym substitution or app behavior is selected or shipped yet.

## Evidence before a product change

The current pinned MiniLM encoder was run on the original nine-query/eleven-document diagnostic, with original questions versus manually compacted hypotheses and title-plus-body versus body-only input. Shortening/removing titles does not recover ferritin; some other useful associations weaken. These are diagnostic input hypotheses, not a proposed question-rewriting feature.

An immutable upstream MedEmbed-small-v0.1 input is downloaded and hash-verified. Its declared modules use CLS pooling and normalization, with no configured query prompt. The original FP32 model ranks ferritin first in the retained iron-stores example and preserves the expected fatigue/sleep, finance and kitchen contexts in that small set. Its cosine distribution differs substantially from MiniLM: reusing the old0.42 threshold would admit many unrelated records. This nine-case result is not independent clinical validation or a shipping decision.

The first FP32-trace→FLOAT16 CoreML conversion compiles but the production encoder rejects its output as invalid. Conversion warnings and the failed result are retained. Diagnose and repair conversion/parity before any app integration; never relax finite-vector guards or relabel a failed attempt as a pass.

## Acceptance before changing the search model or policy

- Preserve shared-record filtering, source fingerprints, exact original excerpts, source-state/consent checks, four-passage/two-per-document limits, cancellation and honest comparison coverage.
- Retain literal identifiers, numbers, units, qualifiers and negation. A topic match never establishes clinical equivalence, entailment, source authenticity or a current measurement.
- Verify complete tokenizer/window behavior and native conversion against upstream vectors across lengths, padding, Unicode, identifiers and numeric/negation examples; retain all failed attempts and warnings.
- Broaden evaluation beyond the known example. Separate calibration from held-out queries, include unanswerable and non-health queries, and report misses/unexpected selections. Do not choose a cutoff merely to pass the old nine cases.
- Measure actual on-device preparation/inference/cleanup behavior and storage costs. Keep downloads explicit and pinned, protect old installations/legacy metadata, and provide clear user control before any model replacement.
- Verify relevant production logic, all app targets and unsigned Release after app changes. For UI changes, use the supplied App Designer Pro workflow and the same continuing critic. Publish coherent source/evidence before stopped-worker cleanup.

## Sources and scope

The [Sentence Transformers semantic-search guide](https://www.sbert.net/examples/sentence_transformer/applications/semantic-search/README.html) distinguishes similar-text and query-to-passage retrieval tasks. The [upstream MedEmbed card](https://huggingface.co/abhinand/MedEmbed-small-v0.1) describes its medical retrieval training and non-medical limits. [Apple's conversion workflow](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html) describes tracing/export followed by CoreML conversion. These are primary implementation references, not independent proof of clinical quality. Source revisions/hashes and compact probe outcomes are in `Design/native/retrieval-quality`.


## Compatibility checkpoint ·31 October2026

The repaired canonical export passes79 production-tokenizer/native-encoder cases and154 vector comparisons against the original upstream FP32 model. Token IDs, every padded window/mask and controller status match exactly. Minimum cosine0.9999746616, maximum component difference0.0015715063; the finite-mask representation itself changes none of85 FP32 reference-window outputs. Portable source pins, producer snapshots, rejection controls and exact per-case outcomes are retained in [the research evidence](../Design/native/retrieval-quality/README.md).

This closes numerical compatibility for the measured candidate; it does not select a search model or a score cutoff. The official BEIR NFCorpus input is downloaded and hashed, and its local dev/test protocol is fixed before scores are inspected. Raw public corpus/query text and temporary vectors stay outside Git. Full-corpus preparation/dev encoding and no-match/non-health/current-app checks are the next work. The app and its current model/threshold/UI remain unchanged; no new application build or design score is claimed.


## Development ranking result · candidate not promoted

The full dev-only experiment includes all3,633 documents,8,239 actual production passages and9,166 complete windows per model. Both models accept all324 original dev queries. No-cutoff nDCG@10 is0.301666 for MiniLM and0.316880 for MedEmbed: +0.015214 falls below the frozen+0.02 gate. Precision@4 improves0.320216→0.334105, but this does not override the missed ranking gate. No exception is taken; the app model/cutoff/UI remain unchanged. Test retrieval scores have not been computed.

[The decision](../Design/native/retrieval-quality/dev-decision.json) retains the exact gate, paired changes, misses and tool repair history. Compact reports preserve every query and all top-four choices/judgments. Raw public text and matrices remain outside Git. pytrec-eval-terrier0.5.11 supplies BEIR's metric family; independent graded/AP/empty-result/tie/window-max oracles and six corpus controls pass. All1,294 existing logic checks also pass; app source is unchanged. This is offline document-max research, not the live four-passage fusion/budget, physical-iPhone or clinical gate.

The next development hypothesis must be declared before its scores. A possible query-instruction trial has primary support in the [BGE base model's short-query guidance](https://huggingface.co/BAAI/bge-small-en-v1.5#frequently-asked-questions), but that does not establish its suitability for the MedEmbed fine-tune. Preserve this raw-query result and the original frozen protocol; do not tune on test queries. No-match/non-health/identifier, model storage/legacy/consent, actual app fusion and physical-device gates remain independently necessary.

## Supplementary instruction trial and source-support challenge

The one fixed BGE instruction was committed in `0a8e0b2` before encoding/scoring, with the raw-query protocol and failed gate preserved. It improves dev nDCG@10 to0.327284 (+0.025618 over raw MiniLM) and Precision@4 to0.350309 (+0.030093), passing the separately declared ranking gate. All324 complete queries encode; passages, windows and weights are unchanged. This is permission to investigate further, not an app model/query/cutoff selection.

The separately committed synthetic challenge has17 documents and32 questions:17 supported and15 with no directly supporting source. Both models rank the expected record first for every supported question without a cutoff. No fixed-grid cutoff retains at least90% supported hit@4 while returning no topics for all15 unsupported questions. For MedEmbed at0.75,16/17 supported remain and2/15 unsupported still select a topic; at0.85 only5/17 supported remain. This demonstrates the limits of scalar source-support inference on these synthetic inputs; related-topic selection is not itself a clinical false answer.

Actual production keyword selection/local reply finds expected text within four passages for all17 supported questions, but selects text for9/15 unsupported questions. Missing `TEST-AX3` returns `TEST-AX2`/`TEST-AX1` and other lab text; missing `AF-742` returns the two existing neighboring invoices. The local reply quotes their literal values with its existing disclaimer; it does not invent a result. This is nevertheless a concrete reason to prioritize literal identifier lookup protection before adopting a new retrieval model. All32 selected contexts remain valid/current, and withdrawal of each supported source is honored.

Current evidence is [instruction-challenge-decision.json](../Design/native/retrieval-quality/instruction-challenge-decision.json), with every dev case, every challenge ranking, native receipts, exact tool hashes, four instruction controls and a raw-baseline regression. All1,294 existing logic checks pass on current research-tool source. Production app/model/cutoff/UI remain Batch25 and NFCorpus test retrieval scores remain uncomputed. Freeze any surviving model/query/selection policy before test scoring; source support, exact identifiers, consent, actual app fusion/budget, legacy/storage, physical devices and clinical/provider validation remain independent gates.
