"""One predeclared synthetic challenge; source support differs from topic relatedness."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from evaluate import load_matrix
from query_variant import instruction_queries

ROOT = Path(__file__).resolve().parents[2]
SOURCE_LABEL = "Synthetic retrieval development challenge; no personal data"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inputs():
    protocol_bytes = (ROOT / "Design/native/retrieval-quality/challenge-protocol.json").read_bytes()
    protocol = json.loads(protocol_bytes)
    fixture_bytes = (ROOT / "Tests/Fixtures/RetrievalChallenge.json").read_bytes()
    if sha(fixture_bytes) != protocol["fixtureSHA256"]:
        raise ValueError("Challenge labels changed after declaration")
    for name, key in [("instruction-protocol.json", "instructionProtocolSHA256"), ("instruction-dev-decision.json", "instructionDevDecisionSHA256")]:
        if sha((ROOT / "Design/native/retrieval-quality" / name).read_bytes()) != protocol[key]:
            raise ValueError("Prior protocol/decision changed")
    fixture = json.loads(fixture_bytes)
    docs = fixture["documents"]
    queries = fixture["queries"]
    doc_ids = {row["id"] for row in docs}
    if len(doc_ids) != len(docs) or len({row["id"] for row in queries}) != len(queries) or any(not set(row["expectedDocumentIDs"]).issubset(doc_ids) for row in queries):
        raise ValueError("Duplicate or invalid labels")
    def jsonl(rows):
        return "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows).encode()
    corpus_bytes = jsonl({"_id": row["id"], "title": row["title"], "text": row["body"]} for row in docs)
    raw_bytes = jsonl({"id": row["id"], "text": row["text"]} for row in queries)
    prefixed_bytes, _ = instruction_queries(raw_bytes)
    return protocol, sha(protocol_bytes), fixture, corpus_bytes, raw_bytes, prefixed_bytes


def evaluate(work):
    protocol, protocol_sha, fixture, corpus_bytes, raw_bytes, prefixed_bytes = inputs()
    preparation = json.loads((work / "prepared/preparation.json").read_text())
    passages = (work / "prepared/passages.jsonl").read_bytes()
    expected = [json.loads(line) for line in passages.decode().splitlines()]
    documents = sorted(row["id"] for row in fixture["documents"])
    if preparation["sourceLabel"] != SOURCE_LABEL or preparation["inputSHA256"] != sha(corpus_bytes) or preparation["preparedSHA256"] != sha(passages) or preparation["limited"] or preparation["unrepresentedDocumentIDs"] or preparation["searchedDocuments"] != len(documents) or {row["documentID"] for row in expected} != set(documents):
        raise ValueError("Partial/mismatched challenge preparation")
    summaries = {}
    model_pins = json.loads((ROOT / "Design/native/retrieval-quality/corpus-native-receipts.json").read_text())
    doc_index = {doc: i for i, doc in enumerate(documents)}
    for model, query_bytes in [("baseline", raw_bytes), ("candidate", prefixed_bytes)]:
        corpus_path, query_path = work / (model + "-corpus"), work / (model + "-queries")
        cr, vectors = load_matrix(corpus_path, "passages", sha(passages), expected)
        qr, query_vectors = load_matrix(query_path, "queries", sha(query_bytes), [json.loads(line) for line in query_bytes.decode().splitlines()])
        if cr["compiledModelFiles"] != qr["compiledModelFiles"] or cr["vocabularySHA256"] != qr["vocabularySHA256"]:
            raise ValueError("Challenge query/corpus models differ")
        if cr["compiledModelFiles"] != model_pins[model + "-corpus"]["compiledModelFiles"] or cr["vocabularySHA256"] != model_pins[model + "-corpus"]["vocabularySHA256"]:
            raise ValueError("Challenge model differs from the pinned baseline/candidate artifact")
        vector_docs = np.concatenate([np.full(row["vectors"], doc_index[row["documentID"]], dtype=np.int64) for row in cr["rows"]])
        cases = []
        for native, query in zip(qr["rows"], fixture["queries"]):
            ranked = []
            if native["status"] == "used":
                window_scores = np.clip(vectors @ query_vectors[native["offset"]], -1, 1)
                scores = np.full(len(documents), -np.inf)
                np.maximum.at(scores, vector_docs, window_scores)
                order = np.argsort(scores, kind="stable")[::-1]
                ranked = [{"documentID": documents[i], "score": float(scores[i])} for i in order]
            cases.append({"queryID": query["id"], "kind": query["kind"], "expectedDocumentIDs": query["expectedDocumentIDs"], "status": native["status"], "ranking": ranked})
        grids = []
        for cutoff in protocol["cutoffs"]:
            supported = [c for c in cases if c["expectedDocumentIDs"]]
            unsupported = [c for c in cases if not c["expectedDocumentIDs"]]
            def chosen(case):
                return [row["documentID"] for row in case["ranking"] if cutoff is None or row["score"] >= cutoff]
            def hit(case, k):
                return bool(set(chosen(case)[:k]) & set(case["expectedDocumentIDs"]))
            groups = {}
            for kind in sorted({c["kind"] for c in cases}):
                group = [c for c in cases if c["kind"] == kind]
                positive = bool(group[0]["expectedDocumentIDs"])
                groups[kind] = {"queries": len(group), "correctFirst" if positive else "withAnyTopic": sum(hit(c, 1) if positive else bool(chosen(c)) for c in group)}
            hit4 = sum(hit(c, 4) for c in supported)
            unexpected = sum(bool(chosen(c)) for c in unsupported)
            grids.append({"cutoff": cutoff, "supportedQueries": len(supported), "supportedHit1Count": sum(hit(c, 1) for c in supported), "supportedHit4Count": hit4, "unsupportedQueries": len(unsupported), "unsupportedWithAnyTopic": unexpected, "passesDirectSupportProfile": hit4 / len(supported) >= .9 and unexpected == 0, "groups": groups})
        summaries[model] = {"grid": grids, "cases": cases, "corpusReceiptSHA256": sha((corpus_path / "complete.json").read_bytes()), "queryReceiptSHA256": sha((query_path / "complete.json").read_bytes()), "queryStatuses": {status: sum(c["status"] == status for c in cases) for status in sorted({c["status"] for c in cases})}, "compiledModelFiles": cr["compiledModelFiles"]}
    return {"protocolSHA256": protocol_sha, "scope": protocol["scope"], "preparation": preparation, "models": summaries, "testRetrievalScoresComputed": False, "appModelCutoffUnchanged": True, "interpretation": "An unsupported question may retrieve a related topic; this score cannot establish that the source contains an answer. These synthetic labels are not clinical judgments or an actual app/provider test."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "evaluate"])
    parser.add_argument("workspace", type=Path)
    args = parser.parse_args()
    if args.mode == "prepare":
        _, _, _, corpus, raw, prefixed = inputs()
        args.workspace.mkdir(exist_ok=False)
        for name, data in [("corpus.jsonl", corpus), ("baseline-queries.jsonl", raw), ("candidate-queries.jsonl", prefixed)]:
            (args.workspace / name).write_bytes(data)
    else:
        output = args.workspace / "outcome.json"
        if output.exists():
            raise ValueError("Output exists")
        outcome = evaluate(args.workspace)
        output.write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n")
        print(json.dumps({name: result["grid"] for name, result in outcome["models"].items()}))
