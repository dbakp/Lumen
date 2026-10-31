# Offline embedding evaluation

These research tools do not install, select or enable an app model. They compile the actual production tokenizer and CPU encoder into a standalone Mac diagnostic. Corpus/source text is never uploaded. Model downloads use public immutable URLs and the checked-in source manifest; inference runs offline.

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
