"""Portable controls for the one declared instruction, without changing repository pins."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from query_variant import instruction_queries


def checks(args):
    results = []
    rows = [{"id": "literal", "text": "No fever; TEST-AX1 0.5 mg; Århus 🧪\n  trailing  "}, {"id": "control", "text": "Leading\u0001control and −1.2 mmol/L"}]
    raw = "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows).encode()
    encoded, metadata = instruction_queries(raw)
    transformed = [json.loads(line) for line in encoded.decode().splitlines()]
    if any(after["id"] != before["id"] or after["text"] != metadata["queryPrefix"] + before["text"] for before, after in zip(rows, transformed)):
        raise ValueError("Original input changed")
    results.append({"control": "Unicode/control/negation/numbers/IDs and whitespace", "exactPrefixPlusOriginalText": True})
    original = Path(__file__).resolve().parent
    repository = original.parents[1]
    with tempfile.TemporaryDirectory(prefix="instruction-controls-", dir=args.workspace) as directory:
        root = Path(directory)
        code = root / "scripts/embedding-probe/query_variant.py"
        code.parent.mkdir(parents=True)
        shutil.copyfile(original / "query_variant.py", code)
        evidence = root / "Design/native/retrieval-quality"
        evidence.mkdir(parents=True)
        for name in ["instruction-protocol.json", "retrieval-protocol.json", "dev-decision.json"]:
            shutil.copyfile(repository / "Design/native/retrieval-quality" / name, evidence / name)
        spec = importlib.util.spec_from_file_location("isolated_variant", code)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        protocol = json.loads((evidence / "instruction-protocol.json").read_text())
        protocol["queryPrefix"] = "different "
        (evidence / "instruction-protocol.json").write_text(json.dumps(protocol))
        for name, expected in [("undeclared prefix", "Unknown instruction"), ("changed original protocol", "Original frozen protocol")]:
            if name == "changed original protocol":
                shutil.copyfile(repository / "Design/native/retrieval-quality/instruction-protocol.json", evidence / "instruction-protocol.json")
                (evidence / "retrieval-protocol.json").write_text("{}")
            try:
                module.instruction_queries(raw)
            except ValueError as error:
                if expected not in str(error):
                    raise
                results.append({"control": name, "rejected": str(error)})
            else:
                raise ValueError(f"Accepted {name}")
        query = root / "limits.jsonl"
        values = [{"id": "ordinary", "text": metadata["queryPrefix"] + "No fever was reported."}, {"id": "overlong", "text": metadata["queryPrefix"] + "blood " * 254}]
        query.write_text("".join(json.dumps(value) + "\n" for value in values))
        subprocess.run(list(map(str, [args.encoder, args.model, args.vocabulary, query, root / "native", "queries"])), check=True, capture_output=True)
        receipt = json.loads((root / "native/complete.json").read_text())
        if [(row["id"], row["status"], row["vectors"]) for row in receipt["rows"]] != [("ordinary", "used", 1), ("overlong", "queryTooLong", 0)]:
            raise ValueError("Overlong prefixed query disappeared or was clipped")
        results.append({"control": "Native prefix-plus-full-query limit", "samples": 2, "accepted": 1, "explicitlyRejected": 1})
    return {"checks": results, "temporaryControlsRemoved": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["encoder", "model", "vocabulary", "workspace", "output"]:
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Output exists")
    result = checks(args)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result))
