"""Repair only the first encoder's /tmp-alias relative paths, proving bytes equal."""
import argparse
import hashlib
import json
from pathlib import Path


def normalize(report_path, compiled):
    original = report_path.read_bytes()
    report = json.loads(original)
    if "metadataCorrection" in report:
        raise ValueError("Receipt already corrected")
    files = []
    for path in sorted(compiled.resolve().rglob("*")):
        if path.is_symlink():
            raise ValueError("Symlink in compiled artifact")
        if path.is_file():
            data = path.read_bytes()
            files.append({"path": str(path.relative_to(compiled.resolve())), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    identity = lambda rows: sorted((row["bytes"], row["sha256"]) for row in rows)
    if identity(files) != identity(report["compiledModelFiles"]):
        raise ValueError("Model bytes differ; metadata-only repair refused")
    backup = report_path.with_suffix(".original.json")
    if backup.exists():
        raise ValueError("Original receipt backup exists")
    backup.write_bytes(original)
    report["compiledModelFiles"] = files
    report["metadataCorrection"] = {"originalSHA256": hashlib.sha256(original).hexdigest(), "change": "Correct /tmp versus /private/tmp relative model paths; complete multiset of file sizes and SHA256 values matches current artifact; no vector, row, timing or input changed"}
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report["metadataCorrection"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("compiled", type=Path)
    args = parser.parse_args()
    print(json.dumps(normalize(args.report, args.compiled)))
