# Library preparation · Batch28

This batch reduces repeated work while preparing shared records. It computes title priority once per current shared document, sorts lightweight indices and reuses one validated canonical-text snapshot for fingerprinting, passage preparation and current-source checks. It adds no persistent text/index cache. Public text, fingerprint fields/JSON, model/query/cutoff policy, consent, source limits and native UI/copy stay unchanged. See [the contract](../../../docs/LIBRARY_RETRIEVAL.md).

## Frozen measurements and failed first trial

`sort-performance-protocol.json` in the sibling retrieval-quality folder reached GitHub as `8b276eb8ffe4f6b5d98247dcfcb722e07d5916b7` before new measurements. Seven original dev query IDs are selected by SHA256(ID), independent of timings. Every Release Mac process loads the complete3,633-document corpus, warms all seven questions and times only `RecordRetrieval.candidates`; source-signature generation stays outside the timer. Three processes per implementation alternate baseline/optimized. Every measured/warm index binds complete ordered rows, source hashes/offsets/excerpt hashes and the entire keyword ranking.

The first title-key-only trial preserves signatures but **fails** the frozen20% reduction target:1.144111s→0.944671s,17.4318%. `title-keys-r1-source.swift` and `title-keys-r1-timing.json` retain its exact producer/all runs. Its passing builds/1,379 logic/28 model checks have that earlier source boundary and are not final-source proof.

The separately declared `preparation-reuse-protocol.json` reached GitHub as `f2f2380a02b5562b718d094c84954f32d35bf50e` before the second implementation/timings. It preserves the original baseline, questions and20%/no-per-query-regression rules. All origin/FHIR/lab/comparison/checklist and size validation stays in the canonical builder; the fingerprint helper only receives its private validated snapshot, with independent metadata-byte checks. Counts are reused within that immutable record/call, never across edits or searches.

## Second trial · timing gate passes

`timing-r2.json` retains all42 measured queries and per-question medians:

| Warmed Release Mac preparation | Median |
|---|---:|
| Original baseline |1.147956s|
| Title keys + validated-text/count reuse |0.894132s|
| Reduction |22.11098%|

All seven per-query medians improve; ratios range0.6766–0.9028. Full ordered-row/keyword signatures match in every warm/measured comparison. No best-run selection or gate relaxation occurs. This is preparation on this Mac, not cold-start/whole-app/physical-iPhone/model/provider latency. Unrelated machine activity is not controlled or stopped.

## Source and functional gates

- Current DebugR3 passes **1,382 production-logic checks**. New cases cover title score/recency/ID ordering, edits/private exclusion, late record priority before the document limit, composed title/source UTF-8 bounds and appended canonical metadata exceeding the complete text limit.
- Actual pinned original MiniLM/CoreML R2 passes **28 checks**, retaining exact-ID eligibility/fusion/cache/privacy/cancellation and actual backup/export/legacy coverage. No model or query policy changes.
- All five simulator products and unsigned generic-iOS ReleaseR2 pass. `release-audit-r2.json` checks the exact executable, minimum iOS18, pinned vocabulary/dependency, specifically named development-marker absence and no bundled model package. This is not distribution readiness.
- All192 native inputs differ from published Batch27 only in `Lumen/Algorithms/RecordRetrieval.swift`. R2/R3 production and the native replay driver are equal. The three extra default-logic assertions follow the Release/model build; current DebugR3 executes them. Precise hashes are in `verification.json` and the source maps.
- Full324-public/32-synthetic question/12-policy comparison **passes exactly** against the published9f261a9 outcomes: all3888 public+384 synthetic source packets, offsets/fingerprints/methods/statuses/metrics/language decisions and privacy checks match. Compact comparison digests reference the existing complete baseline rather than duplicating its results. Current regular built-in native lifecycle passes **238.879s**, one test, zero failures/skips/recorded runtime warnings; console diagnostics remain separate from that xcresult array. Five useful original native captures are retained with all11 capture hashes/provenance. They were visually checked as synthetic app states, without claiming a new design score.

No UI/layout/copy/icon/navigation changes are proposed; current native surfaces receive behavioral regression coverage. No new design score, clinical/answer-support result, signed-device performance or release claim follows. The earlier retrieval-quality findings and seven unsupported keyword-topic selections remain unresolved; held-out retrieval scores stay uncomputed. The full product goal remains active.

Raw temporary results/builds are task-owned working evidence. Publish useful originals, compact outcomes and exact provenance before stopped-worker cleanup. Retain current research inputs/skill and preserve unrelated projects, personal data, primary/Watch simulators and shared runtimes. Removed raw paths become historical references.

## Publication and scoped cleanup

Application `d14d589c7024b6a18996aaad9fae30f66b28da62` reached GitHub through the batch publisher with exact main read-back before deletion. All build/test/export/publish workers were stopped. Cleanup removed7 verified task-owned roots plus2 redundant raw native reports: reused simulator/device build outputs, package clone/scratch, raw verification/baseline binaries, the exclusive test CoreML cache and local tool bytecode. Removed roots account for1,816,065,465 logical file bytes and1,854,627,840 unique-inode allocated bytes. Available bytes increased **27,718,709,248→29,534,736,384**, a measured **1,816,027,136 bytes (about1.82GB)**; APFS/concurrent changes differ from file accounting. An initial path-format check stopped before any deletion, was corrected and fully rechecked; the machine ledger preserves that boundary.

All5 useful native originals and compact exact trial/source/failure/outcome evidence remain. Current source/model/Python environment/dataset/prepared corpus/matrices/score/config inputs and the supplied skill/archive remain. A7,029,920-byte system-dependent current Release `LibrarySelectionProbe`/metadata replaces obsolete full package scratch for immediate research commands; after cache removal it replays all32 synthetic questions/12 policies exactly, without a new build. Its advertised commands are not the full current default test suite: rebuild from current sources for those or after production/driver changes. Primary/Watch/shared simulators/runtimes, unrelated projects/personal data and global/system/browser caches are preserved. No symbolic-link target was followed and no cleanup-only app build ran. Raw removed paths are historical; the full goal remains active.
