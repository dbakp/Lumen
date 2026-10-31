"""Exercise complete-index/rejection/receipt controls using small synthetic inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from evaluate import load_matrix, metric_controls


def run(args):
    checks = []
    with tempfile.TemporaryDirectory(prefix="LumenCorpusControls-", dir=args.workspace) as directory:
        root = Path(directory)
        def rows(name, values):
            path = root / name
            path.write_text("".join(json.dumps(value) + "\n" for value in values))
            return path
        def reject(label, command, output, expected):
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
            if result.returncode != 1 or output.exists() or expected not in result.stderr:
                raise ValueError(f"Rejection control failed: {label}")
            checks.append({"control": label, "exit": result.returncode, "noPartialOutput": True, "diagnostic": expected})
        duplicate = rows("duplicate.jsonl", [{"_id": "d", "title": "title", "text": "body"}] * 2)
        reject("duplicate corpus IDs", [args.preparer, "--retrieval-corpus-prepare", duplicate, root / "dup-out"], root / "dup-out", "invalidInput")
        oversized = rows("over-limit.jsonl", ({"_id": str(i), "title": "title", "text": "body"} for i in range(5001)))
        reject("5001 documents cannot silently become 5000", [args.preparer, "--retrieval-corpus-prepare", oversized, root / "limit-out"], root / "limit-out", "incompleteIndex")
        duplicate_native = rows("duplicate-native.jsonl", [{"id": "d", "documentID": "d", "text": "body"}] * 2)
        reject("duplicate native IDs", [args.encoder, args.model, args.vocabulary, duplicate_native, root / "native-dup", "passages"], root / "native-dup", "duplicateID")
        queries = rows("queries.jsonl", [{"id": "accepted", "text": "blood count"}, {"id": "long", "text": "blood " * 255}])
        subprocess.run(list(map(str, [args.encoder, args.model, args.vocabulary, queries, root / "query-out", "queries"])), check=True, capture_output=True)
        receipt = json.loads((root / "query-out/complete.json").read_text())
        if [(row["id"], row["status"], row["vectors"]) for row in receipt["rows"]] != [("accepted", "used", 1), ("long", "queryTooLong", 0)] or receipt["samples"] != 2 or receipt["rejectedQueries"] != 1:
            raise ValueError("Long query disappeared or was truncated")
        if {row["path"] for row in receipt["compiledModelFiles"]} != {str(p.relative_to(args.model.resolve())) for p in args.model.resolve().rglob("*") if p.is_file()}:
            raise ValueError("Canonical relative model paths differ")
        checks.append({"control": "accepted and overlong queries", "samples": 2, "accepted": 1, "explicitlyRejected": 1, "relativeModelPathsExact": True})
        inputs = [json.loads(line) for line in (args.prepared / "passages.jsonl").read_text().splitlines()]
        expected_sha = hashlib.sha256((args.prepared / "passages.jsonl").read_bytes()).hexdigest()
        report = json.loads((args.matrix / "complete.json").read_text())
        folder = root / "matrix-control"
        folder.mkdir()
        os.link(args.matrix / "vectors.f32le", folder / "vectors.f32le")
        for label, change in [("forged matrix digest", lambda r: r.update(matrixSHA256="0" * 64)), ("dropped mapping row", lambda r: r["rows"].pop())]:
            modified = json.loads(json.dumps(report))
            change(modified)
            (folder / "complete.json").write_text(json.dumps(modified))
            try:
                load_matrix(folder, "passages", expected_sha, inputs)
            except ValueError as error:
                checks.append({"control": label, "rejected": str(error)})
            else:
                raise ValueError(f"Accepted {label}")
        return {"checks": checks, "metricControls": metric_controls(), "fixtureRetention": "Synthetic inputs, hard links and control outputs removed after checks; original matrices are read only"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["preparer", "encoder", "model", "vocabulary", "prepared", "matrix", "workspace", "output"]:
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Output exists")
    outcome = run(args)
    args.output.write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n")
    print(json.dumps(outcome))
