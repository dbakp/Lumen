# Offline embedding evaluation

These research tools do not install, select or enable an app model. They compile the actual production tokenizer and CPU encoder into a standalone Mac diagnostic. Corpus/source text is never uploaded. Model downloads use public immutable URLs and the checked-in source manifest; inference runs offline.

## Full-corpus development evaluation

The frozen protocol is `Design/native/retrieval-quality/retrieval-protocol.json`. `corpus.py` reads only pinned corpus/query/dev-judgment inputs. It never opens test judgments. No truncated question, instruction prefix or selected corpus prefix is permitted in this experiment.

1. Build the existing verification executable with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --scratch-path WORK/LogicBuild`.
2. Run `WORK/LogicBuild/debug/LumenLogicChecks --retrieval-corpus-prepare DATA/nfcorpus/corpus.jsonl WORK/prepared`. The actual production passage builder must index every document without `limited` or unrepresented IDs. Output must be new.
3. Run `python scripts/embedding-probe/corpus.py DATA WORK/dev` to prepare all original development queries from the pinned source. Raw text stays outside Git.
4. Compile `Encode.swift` with the same three production files as the parity CLI below, naming the executable `WORK/EmbeddingCorpusProbe`.
5. For each model run `WORK/EmbeddingCorpusProbe MODEL.mlmodelc VOCAB WORK/prepared/passages.jsonl WORK/MODEL-corpus passages`, then `WORK/EmbeddingCorpusProbe MODEL.mlmodelc VOCAB WORK/dev/dev-queries.jsonl WORK/MODEL-dev queries`. The original MiniLM vocabulary is `SOURCE/tokenizer/vocab.txt`; MedEmbed uses `SOURCE/vocab.txt`. Keep one encoder running at a time. All windows are written as Float32 little-endian, with exact input/model/matrix hashes and complete row mappings. Overlong queries remain explicit zero-vector rows; other failures stop the run without a completion receipt.
6. Run `python scripts/embedding-probe/evaluate.py DATA WORK/prepared WORK/MODEL-corpus WORK/MODEL-dev WORK/MODEL-results.json`. The loader verifies full coverage, hashes, dimensions, normalization and every offset/ID. Document scores use the maximum across every prepared window. `pytrec-eval-terrier==0.5.11` supplies the metrics used by BEIR; all dev queries stay in the denominator, even rejected/empty ones. Graded gains, AP, empty results, tie ordering and window reduction have independent small oracle checks. This custom preparation is not leaderboard parity.
7. Run `python scripts/embedding-probe/controls.py PREPARER ENCODER MODEL VOCAB WORK/prepared WORK/MODEL-corpus WORK OUTCOME.json` for duplicate-ID, complete-index, rejected-query, canonical-path and corrupt/partial-receipt controls. Synthetic files/hard links are removed afterward without changing the source matrices.
8. `compact.py FULL_REPORT COMPACT_REPORT` retains all query metrics, every top-four selection/judgment, first relevant rank, relevant count@100 and full ranking digests. Never copy raw public text into Git. Record the model/policy decision before any held-out scoring.

The initial encoder computed incorrect relative artifact paths through macOS `/tmp` aliases. `normalize_receipt.py REPORT COMPILED_MODEL` is a historical metadata-only repair: it refuses unless the complete multiset of file sizes/hashes matches, retains the original receipt hash and changes no vectors/mapping/timings. Current native enumeration returns relative paths directly; the control verifies them. The exact original producer is retained separately in the evidence.

Raw-query development results miss the predeclared model-promotion gate; no model/cutoff is selected. See `Design/native/retrieval-quality/dev-decision.json`.

Use Python3.12, Xcode and one task-owned workspace. Install dependencies into that workspace with `pip install --no-cache-dir -r scripts/embedding-probe/requirements.txt`; do not modify the shared bundled runtime. The complete measured environment is retained in `Design/native/retrieval-quality/evaluation-environment.txt`.

## Candidate parity workflow

Run from the repository root. Choose new output paths; keep the same workspace for iteration.

1. `python fetch.py MANIFEST SOURCE` downloads only missing pinned MedEmbed files. Use `Design/native/retrieval-quality/medembed-source.json` as MANIFEST. Cached files are checked without downloading their weights again.
2. `python reference.py SOURCE Tests/Fixtures/EmbeddingParity.json UPSTREAM_JSON` runs the unmodified upstream FP32 encoder and declared CLS/L2 pooling, with the independent upstream tokenizer. `pin.py` binds inputs to the checked-in hashes and refuses unknown files or symlinks. Safetensors and local-only loading are required.
3. `python convert.py SOURCE Tests/Fixtures/EmbeddingParity.json UPSTREAM_JSON OUTPUT.mlpackage CONVERSION_JSON` validates every reference passage window before exporting the finite-mask FLOAT16 graph. Output must not exist. Conversion may emit warnings; retain the log and exact artifact hashes. Container identifiers can differ on re-export, so numerical reproducibility is separate from a selected artifact's exact checksums.
4. Compile that package with `xcrun coremlcompiler compile OUTPUT.mlpackage COMPILED_PARENT`.
5. Compile the native diagnostic with the actual source files:

   ```sh
   xcrun swiftc -parse-as-library \
     Lumen/Algorithms/MiniLMTokenizer.swift \
     Lumen/Algorithms/SemanticModelPackage.swift \
     Lumen/Services/MiniLMEncoder.swift \
     scripts/embedding-probe/Parity.swift -o WORK/EmbeddingParityProbe
   ```

6. Run `WORK/EmbeddingParityProbe COMPILED.mlmodelc SOURCE/vocab.txt Tests/Fixtures/EmbeddingParity.json NATIVE_JSON`.
7. Run `python compare.py UPSTREAM_JSON NATIVE_JSON Design/native/retrieval-quality/parity-policy.json OUTCOME_JSON`. A failed gate returns nonzero and preserves its cases in the report.

The exact R3 export producer is separately retained as `Design/native/retrieval-quality/conversion-r3-producer.py`. Subsequent public-tool changes strengthen immutable-input verification without changing the conversion mathematics. The failed original-mask/all-FLOAT16 producers and direct invalid-output inspector are historical evidence, not valid model recommendations.

The79-case fixture includes all prior golden tokenizer texts, the original diagnostic inputs, exact254-token questions, longer rejected questions, all overlapping passage windows, Unicode, input bounds, identifiers and numeric negation. It is a compatibility fixture, not a clinical or multilingual quality benchmark. A source token list longer than512 can trigger the upstream tokenizer's generic warning; each actual model call is independently windowed to256 tokens.

## Input-configuration diagnostic

`diagnostic.py PARITY_FIXTURE NATIVE_JSON Tests/Fixtures/MiniLMRetrieval.json CONFIG MODEL_ID OUTPUT_JSON` reconstructs all36 original/compact and title/body configurations. CONFIG is the retained `minilm-query-probe-r1.json`; only its input/label fields are read, never its saved scores. The published MiniLM result is reproduced to floating-point rounding using the same parity CLI with the pinned MiniLM compiled model and vocabulary. These manual compact questions remain hypotheses; they are not shipped question rewriting.

## Broader quality and storage

The frozen public-dataset protocol is in `Design/native/retrieval-quality/retrieval-protocol.json`. Development calibration, locally held-out test scoring, no-match/non-health cases, current-app fusion/consent/legacy checks and native iPhone/resource validation remain separate gates. Do not transfer MiniLM's0.42 cutoff to the candidate or infer clinical accuracy from vector parity.

Keep raw dataset text and temporary vectors outside Git. Publish compact outcomes, failures, producer/source hashes and protocol before removing redundant scratch data. Keep the current canonical candidate, baseline model, needed source inputs and environment for the next step; delete only stopped task-owned obsolete exports/caches. Preserve unrelated projects, user files and global caches.
