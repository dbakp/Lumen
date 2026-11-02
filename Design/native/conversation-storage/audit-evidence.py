"""Validate retained identities without building or changing application data."""
import gzip
import hashlib
import json
from pathlib import Path
import struct
from datetime import datetime, timezone

evidence = Path(__file__).resolve().parent
repo = evidence.parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


sources = {}
for name in ["application-source-r27.json", "ui-source-r23.json", "logic-source-r8.json"]:
    inputs = json.loads((evidence / name).read_text())
    for relative, expected in inputs.items():
        path = repo / relative
        assert path.is_file() and not path.is_symlink(), relative
        assert digest(path) == expected, (name, relative)
    sources[name] = len(inputs)

reviewed = 0
for name in ["review-packet-r1.json", "review-packet-r2.json", "review-packet-r3.json", "review-packet-r4.json"]:
    if not (evidence / name).exists():
        continue
    packet = json.loads((evidence / name).read_text())
    for row in packet["images"]:
        path = Path(row["path"])
        assert path.is_relative_to(evidence) and not path.is_symlink(), path
        assert digest(path) == row["sha256"], path
        reviewed += 1

inventory = []
for path in sorted(evidence.rglob("*.png")):
    assert not path.is_symlink(), path
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    width, height = struct.unpack(">II", data[16:24])
    assert (width, height) in [(1206, 2622), (750, 1334)], (path, width, height)
    inventory.append(dict(path=str(path.relative_to(evidence)), bytes=len(data),
                          sha256=hashlib.sha256(data).hexdigest(), width=width, height=height))

logs = []
for path in sorted(evidence.rglob("*.gz")):
    assert not path.is_symlink(), path
    data = gzip.decompress(path.read_bytes())
    assert data, path
    logs.append(dict(path=str(path.relative_to(evidence)), uncompressedBytes=len(data),
                     uncompressedSHA256=hashlib.sha256(data).hexdigest()))

backend_name = "native-r26-report.json" if (evidence / "native-r26-report.json").exists() else "native-r25-report.json"
backend = json.loads((evidence / backend_name).read_text())
assert backend["status"] == "Conversation checks passed"
assert len(backend["checks"]) == 49 and all(row["passed"] for row in backend["checks"])
red = json.loads((evidence / "native-r23-report.json").read_text())
assert len(red["checks"]) == 48 and not red["checks"][-1]["passed"]
startup = json.loads((evidence / "startup-r2-readback.json").read_text())
assert len(startup["cases"]) == 4 and all(row["readbackPassed"] for row in startup["cases"])
assert json.loads((evidence / "small-r8-disk-readback.json").read_text())["result"] == "passed"
assert json.loads((evidence / "native-r20-disk-readback.json").read_text())["result"] == "passed"

result = dict(status="passed", generatedAtUTC=datetime.now(timezone.utc).isoformat(), currentSources=sources,
              backendReport=backend_name, reviewImageRecords=reviewed,
              retainedPNGFiles=len(inventory), uniquePNGHashes=len({row["sha256"] for row in inventory}),
              pngs=inventory, compactLogs=logs,
              scope="Current source identities, retained original PNG headers/hashes, selected review identities, complete compressed logs and explicit native red/green/read-back outcomes. Separate UI run boundaries remain in verification.json; no full-product or final combined-suite claim.")
(evidence / "evidence-audit.json").write_text(json.dumps(result, indent=2) + "\n")
print(sources)
print(len(inventory), "retained PNGs;", len(logs), "complete compressed logs;", reviewed, "review image records match")
