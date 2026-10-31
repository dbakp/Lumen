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
