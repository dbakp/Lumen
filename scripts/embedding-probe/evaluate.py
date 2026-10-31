"""Frozen dev-only, full-corpus document-max evaluation. Never opens test qrels."""
import argparse
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path

import numpy as np
import pytrec_eval
from corpus import load_dev

MEASURES = {"ndcg_cut.10", "map_cut.100", "recall.4,100", "P.4"}
NAMES = ["ndcg_cut_10", "map_cut_100", "recall_4", "recall_100", "P_4"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def metric_controls():
    # Independently hand-computed graded gains, missing results and AP denominator.
    rels = {"q": {"a": 2, "b": 1, "c": 1}, "missing": {"z": 1}}
    result = {"q": {"b": 3.0, "x": 2.0, "a": 1.0}, "missing": {}}
    values = pytrec_eval.RelevanceEvaluator(rels, MEASURES).evaluate(result)
    expected = {"ndcg_cut_10": 2 / (2 + 1 / math.log2(3) + .5), "map_cut_100": (1 + 2 / 3) / 3, "recall_4": 2 / 3, "recall_100": 2 / 3, "P_4": .5}
    for name, value in expected.items():
        if not math.isclose(values["q"][name], value, abs_tol=1e-12):
            raise ValueError(f"Metric oracle failed: {name}")
    if any(values.get("missing", {}).values()):
        raise ValueError("Empty result did not yield zero metrics")
    tied = pytrec_eval.RelevanceEvaluator({"t": {"b": 1}}, MEASURES).evaluate({"t": {"a": 1.0, "b": 1.0}})
    if tied["t"]["ndcg_cut_10"] != 1.0:
        raise ValueError("trec_eval descending document-ID tie policy changed")
    # Document-max must prefer the later window, not the first or an average.
    scores = np.full(3, -np.inf)
    np.maximum.at(scores, np.array([0, 1, 0, 2]), np.array([.1, .5, .9, .4]))
    if not np.allclose(scores, [.9, .5, .4]):
        raise ValueError("Window reduction failed")
    return {"gradedAndBinaryMetrics": "hand-calculated values agree within 1e-12", "emptyResults": "zero", "windowReduction": "later-window maximum retained", "equalScores": "descending document-ID tie oracle agrees", "package": importlib.metadata.version("pytrec-eval-terrier")}


def load_matrix(folder, kind, expected_sha, expected_rows):
    report = json.loads((folder / "complete.json").read_text())
    data = (folder / "vectors.f32le").read_bytes()
    if report.get("complete") is not True or report["kind"] != kind or report["dimension"] != 384 or report["dtype"] != "float32-little-endian" or report["inputSHA256"] != expected_sha or report["matrixSHA256"] != sha(data):
        raise ValueError("Incomplete or mismatched native matrix")
    if report["samples"] != len(expected_rows) or len(report["rows"]) != len(expected_rows):
        raise ValueError("Partial input mapping")
    count = 0
    for row, expected in zip(report["rows"], expected_rows):
        if row["id"] != expected["id"] or row["offset"] != count:
            raise ValueError("ID or offset mismatch")
        if kind == "passages":
            if row["documentID"] != expected["documentID"] or row["status"] != "used" or row["vectors"] < 1:
                raise ValueError("Dropped passage")
        elif row["status"] == "used":
            if row["vectors"] != 1:
                raise ValueError("Truncated or duplicated query")
        elif row["status"] not in {"empty", "queryTooLong", "inputLimit"} or row["vectors"] != 0:
            raise ValueError("Unexpected query failure")
        count += row["vectors"]
    if report["vectors"] != count or len(data) != count * 384 * 4:
        raise ValueError("Matrix length mismatch")
    matrix = np.frombuffer(data, dtype="<f4").reshape(count, 384).astype(np.float64)
    norms = np.linalg.norm(matrix, axis=1)
    if not np.isfinite(matrix).all() or not np.allclose(norms, 1, atol=1e-5):
        raise ValueError("Nonfinite or unnormalized vectors")
    return report, matrix / norms[:, None]


def evaluate(source, prepared, corpus_folder, query_folder, query_instruction=False):
    controls = metric_controls()
    qrels, query_bytes, corpus_ids = load_dev(source)
    variant = None
    if query_instruction:
        from query_variant import instruction_queries
        query_bytes, variant = instruction_queries(query_bytes)
    input_bytes = (prepared / "passages.jsonl").read_bytes()
    preparation = json.loads((prepared / "preparation.json").read_text())
    canonical = json.loads((Path(__file__).resolve().parents[2] / "Design/native/retrieval-quality/nfcorpus-source.json").read_text())
    corpus_sha = next(item["sha256"] for item in canonical["files"] if item["path"] == "nfcorpus/corpus.jsonl")
    if preparation["inputSHA256"] != corpus_sha or preparation["preparedSHA256"] != sha(input_bytes) or preparation["limited"] or preparation["unrepresentedDocumentIDs"] or preparation["documents"] != len(corpus_ids) or preparation["searchedDocuments"] != len(corpus_ids):
        raise ValueError("Incomplete/unpinned preparation")
    inputs = [json.loads(line) for line in input_bytes.decode().splitlines()]
    if len(inputs) != preparation["passages"] or {row["documentID"] for row in inputs} != corpus_ids or len({row["id"] for row in inputs}) != len(inputs):
        raise ValueError("Incomplete corpus")
    queries = [json.loads(line) for line in query_bytes.decode().splitlines()]
    cr, vectors = load_matrix(corpus_folder, "passages", sha(input_bytes), inputs)
    qr, query_vectors = load_matrix(query_folder, "queries", sha(query_bytes), queries)
    if variant and cr["matrixSHA256"] != variant["corpusVectorsSHA256"]:
        raise ValueError("Instruction experiment must reuse the frozen candidate corpus matrix")
    if cr["compiledModelFiles"] != qr["compiledModelFiles"] or cr["vocabularySHA256"] != qr["vocabularySHA256"]:
        raise ValueError("Corpus/query models differ")
    documents = sorted(corpus_ids)
    doc_index = {doc: i for i, doc in enumerate(documents)}
    vector_docs = np.concatenate([np.full(row["vectors"], doc_index[row["documentID"]], dtype=np.int64) for row in cr["rows"]])
    rankings, query_status = {}, {}
    for row in qr["rows"]:
        query = row["id"]
        query_status[query] = row["status"]
        if row["status"] != "used":
            rankings[query] = []
            continue
        similarities = np.clip(vectors @ query_vectors[row["offset"]], -1, 1)
        scores = np.full(len(documents), -np.inf)
        np.maximum.at(scores, vector_docs, similarities)
        if not np.isfinite(scores).all():
            raise ValueError("Unscored document")
        # trec_eval breaks equal scores by descending document ID. Documents
        # start ascending, so reversing the stable ascending score sort agrees.
        order = np.argsort(scores, kind="stable")[::-1][:100]
        rankings[query] = [(documents[i], float(scores[i])) for i in order]
    protocol_path = Path(__file__).resolve().parents[2] / "Design/native/retrieval-quality/retrieval-protocol.json"
    protocol_bytes = protocol_path.read_bytes()
    grids = json.loads(protocol_bytes)["fixedCutoffGrid"]
    evaluator = pytrec_eval.RelevanceEvaluator(qrels, MEASURES)
    summaries, cases = [], []
    for cutoff in grids:
        results = {q: {doc: score for doc, score in ranked if cutoff is None or score >= cutoff} for q, ranked in rankings.items()}
        evaluated = evaluator.evaluate(results)
        aggregate = {name: sum(evaluated.get(q, {}).get(name, 0.0) for q in qrels) / len(qrels) for name in NAMES}
        summaries.append({"cutoff": cutoff, **aggregate, "queriesWithResults": sum(bool(value) for value in results.values()), "denominatorQueries": len(qrels)})
        if cutoff is None:
            for query in sorted(qrels):
                ranked = rankings[query]
                cases.append({"queryID": query, "status": query_status[query], "metrics": {name: evaluated.get(query, {}).get(name, 0.0) for name in NAMES}, "top100": [{"documentID": doc, "score": score, "judgment": qrels[query].get(doc), "judgedRelevant": qrels[query].get(doc, 0) > 0} for doc, score in ranked]})
    relevant_scores, unjudged_scores = [], []
    for query, ranked in rankings.items():
        for doc, score in ranked[:4]:
            (relevant_scores if qrels[query].get(doc, 0) > 0 else unjudged_scores).append(score)
    def quantiles(values):
        return {str(q): float(np.quantile(values, q)) for q in [0, .1, .5, .9, 1]} if values else {}
    return {"version": 1, "split": "dev", "scope": "Offline document-max over all production-prepared windows; not app fusion, clinical validity or live budget", "queryVariant": variant, "testScoresInspected": False, "protocolSHA256": sha(protocol_bytes), "preparation": preparation, "sourceReports": {"corpus": sha((corpus_folder / "complete.json").read_bytes()), "queries": sha((query_folder / "complete.json").read_bytes())}, "native": {"corpusSeconds": cr["seconds"], "querySeconds": qr["seconds"], "vectors": cr["vectors"], "queryStatuses": {state: sum(value == state for value in query_status.values()) for state in sorted(set(query_status.values()))}, "compiledModelFiles": cr["compiledModelFiles"]}, "metricControls": controls, "grid": summaries, "top4ScoreQuantiles": {"judgedRelevant": quantiles(relevant_scores), "otherOrUnjudged": quantiles(unjudged_scores)}, "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "prepared", "corpus", "queries", "output"]:
        parser.add_argument(name, type=Path)
    parser.add_argument("--query-instruction", action="store_true")
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Output exists")
    outcome = evaluate(args.source, args.prepared, args.corpus, args.queries, args.query_instruction)
    args.output.write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"grid": outcome["grid"], "native": outcome["native"], "metricControls": outcome["metricControls"]}))
