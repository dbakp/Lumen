"""Independent graded metric/denominator oracles for all rerank outcomes."""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("outcome", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Output exists")
    import pytrec_eval
    from evaluate import metric_controls
    upstream = metric_controls()
    manifest = json.loads((ROOT / "Design/native/retrieval-quality/nfcorpus-source.json").read_bytes())
    pin = next(r for r in manifest["files"] if r["path"] == "nfcorpus/qrels/dev.tsv")
    data = (args.source / pin["path"]).read_bytes()
    if hashlib.sha256(data).hexdigest() != pin["sha256"]:
        raise ValueError("Changed development judgments")
    qrels = {}
    for line in data.decode().splitlines()[1:]:
        q, doc, value = line.split("\t")
        if doc in qrels.setdefault(q, {}):
            raise ValueError("Duplicate judgment")
        qrels[q][doc] = int(value)
    d = json.loads(args.outcome.read_bytes())
    if d["split"] != "dev" or {c["queryID"] for c in d["cases"]} != set(qrels) or len(d["cases"]) != 324:
        raise ValueError("Changed denominator")
    def manual(q, rows):
        docs = list(dict.fromkeys(r["documentID"] for r in rows))
        if len(rows) > 4 or len(docs) > 4:
            raise ValueError("Changed packet capacity")
        grades = qrels[q]
        dcg = sum(grades.get(doc, 0) / math.log2(rank + 2) for rank, doc in enumerate(docs))
        ideal = sum(grade / math.log2(rank + 2) for rank, grade in enumerate(sorted(grades.values(), reverse=True)[:4]))
        hits = sum(grades.get(doc, 0) > 0 for doc in docs)
        positives = sum(grade > 0 for grade in grades.values())
        return {"ndcg_cut_4": dcg / ideal if ideal else 0., "P_4": hits / 4, "recall_4": hits / positives if positives else 0., "hit_4": float(hits > 0)}
    manual_baseline = {c["queryID"]: manual(c["queryID"], c["baseline"]) for c in d["cases"]}
    comparisons, per_query_comparisons, policies = 0, 0, []
    evaluator = pytrec_eval.RelevanceEvaluator(qrels, {"ndcg_cut.4", "P.4", "recall.4"})
    for position in [-1] + list(range(10)):
        values = manual_baseline if position == -1 else {c["queryID"]: manual(c["queryID"], c["policies"][position]["passages"]) for c in d["cases"]}
        expected = d["baseline"] if position == -1 else d["policies"][position]
        packets = {c["queryID"]: c["baseline"] if position == -1 else c["policies"][position]["passages"] for c in d["cases"]}
        run = {}
        for q, rows in packets.items():
            docs = list(dict.fromkeys(r["documentID"] for r in rows))
            if docs:
                run[q] = {doc: float(4 - rank) for rank, doc in enumerate(docs)}
        actual = evaluator.evaluate(run)
        for q, manual_values in values.items():
            for m in ["ndcg_cut_4", "P_4", "recall_4"]:
                if abs(actual.get(q, {}).get(m, 0.) - manual_values[m]) > 1e-12:
                    raise ValueError("Independent per-query metric mismatch")
                per_query_comparisons += 1
        means = {m: sum(v[m] for v in values.values()) / 324 for m in ["ndcg_cut_4", "P_4", "recall_4", "hit_4"]}
        for m, value in means.items():
            if abs(value - expected[m]) > 1e-12:
                raise ValueError("Independent metric mismatch")
            comparisons += 1
        if position >= 0:
            changes = [values[q]["ndcg_cut_4"] - manual_baseline[q]["ndcg_cut_4"] for q in values]
            paired = {"improved": sum(v > 1e-12 for v in changes), "worsened": sum(v < -1e-12 for v in changes), "unchanged": sum(abs(v) <= 1e-12 for v in changes)}
            if any(expected[k] != value for k, value in paired.items()):
                raise ValueError("Paired change counts differ")
            comparisons += 3
        policies.append({"policyPosition": position, "independentMeans": means})
    report = {"passed": True, "independentAggregateComparisons": comparisons, "independentPerQueryMetricComparisons": per_query_comparisons, "completeQueryPolicyCells": 324 * 11, "denominator": 324, "policies": policies, "existingMetricOracles": upstream, "outcomeSHA256": hashlib.sha256(args.outcome.read_bytes()).hexdigest(), "sourceSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "scope": "Direct linear graded-DCG,Precision@4,Recall@4,hit@4 and paired-count computation from original dev judgments; no test queries/judgments read."}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": True, "aggregateComparisons": comparisons, "perQueryMetricComparisons": per_query_comparisons, "completeCells": 324 * 11}))


if __name__ == "__main__":
    main()
