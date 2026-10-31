"""Prepare only the frozen development queries from pinned public inputs."""
import argparse
import hashlib
import json
from pathlib import Path


def checked(path, expected):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Unsafe or missing input: {path}")
    data = path.read_bytes()
    if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
        raise ValueError(f"Source hash mismatch: {path}")
    return data


def load_dev(source):
    canonical = Path(__file__).resolve().parents[2] / "Design/native/retrieval-quality/nfcorpus-source.json"
    manifest = json.loads(canonical.read_text())
    files = {item["path"]: item for item in manifest["files"]}
    needed = ["nfcorpus/corpus.jsonl", "nfcorpus/queries.jsonl", "nfcorpus/qrels/dev.tsv"]
    data = {name: checked(source / name, files[name]) for name in needed}
    qrels = {}
    for line in data[needed[2]].decode().splitlines()[1:]:
        query, doc, score = line.split("\t")
        if doc in qrels.setdefault(query, {}):
            raise ValueError("Duplicate judgment")
        qrels[query][doc] = int(score)
    queries = {}
    for line in data[needed[1]].decode().splitlines():
        row = json.loads(line)
        if row["_id"] in queries:
            raise ValueError("Duplicate query")
        queries[row["_id"]] = row["text"]
    if not qrels or any(q not in queries for q in qrels):
        raise ValueError("Missing dev queries")
    corpus_ids = [json.loads(line)["_id"] for line in data[needed[0]].decode().splitlines()]
    corpus_set = set(corpus_ids)
    if len(corpus_set) != len(corpus_ids) or any(doc not in corpus_set for rels in qrels.values() for doc in rels):
        raise ValueError("Duplicate or missing corpus documents")
    query_bytes = "".join(json.dumps({"id": query, "text": queries[query]}, ensure_ascii=False) + "\n" for query in sorted(qrels)).encode()
    return qrels, query_bytes, set(corpus_ids)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--query-instruction", action="store_true", help="Only the separately predeclared MedEmbed/BGE dev experiment")
    args = parser.parse_args()
    qrels, query_bytes, _ = load_dev(args.source)
    if args.query_instruction:
        from query_variant import instruction_queries
        query_bytes, _ = instruction_queries(query_bytes)
    args.output.mkdir(exist_ok=False)
    (args.output / "dev-queries.jsonl").write_bytes(query_bytes)
    (args.output / "dev-qrels.json").write_text(json.dumps(qrels, sort_keys=True))
    print(json.dumps({"split": "dev", "queries": len(qrels), "judgments": sum(map(len, qrels.values())), "testScoresInspected": False}))


if __name__ == "__main__":
    main()
