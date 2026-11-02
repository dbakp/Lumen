"""Verify the current source/evidence identities without building or UI access."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import struct

base = Path(__file__).resolve().parent
repo = base.parents[2]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

sources = {}
for name in ["application-source-r6.json", "logic-source-r2.json", "ui-source-r12.json", "server-source-r1.json"]:
    entries = json.loads((base / name).read_text())
    for relative, digest in entries.items():
        path = repo / relative
        assert path.is_file() and not path.is_symlink(), relative
        assert sha(path) == digest, (name, relative)
    sources[name] = len(entries)

# Runtime scopes keep their original sources even when later test-only edits
# are prepared while an already-compiled run is still active.
historical_sources = {}
for bundle, manifests in [
    ("app5-ui4-before-dispatch-sources.json.gz", ["application-source-r5.json", "ui-source-r4.json"]),
    ("ui5-before-frame-capture-sources.json.gz", ["ui-source-r5.json"]),
    ("ui6-before-plan-warning-reveal-sources.json.gz", ["ui-source-r6.json"]),
    ("ui7-before-goal-capture-sources.json.gz", ["ui-source-r7.json"]),
    ("ui8-before-goal-key-capture-sources.json.gz", ["ui-source-r8.json"]),
    ("ui9-before-physical-key-capture-sources.json.gz", ["ui-source-r9.json"]),
    ("ui10-before-supported-done-capture-sources.json.gz", ["ui-source-r10.json"]),
    ("ui11-before-software-key-capture-sources.json.gz", ["ui-source-r11.json"]),
]:
    preserved = json.loads(gzip.decompress((base / bundle).read_bytes()))
    for manifest in manifests:
        entries = json.loads((base / manifest).read_text())
        for relative, digest in entries.items():
            data = preserved[relative].encode() if relative in preserved else (repo / relative).read_bytes()
            assert hashlib.sha256(data).hexdigest() == digest, (bundle, manifest, relative)
        historical_sources[manifest] = len(entries)

reviewed = 0
for packet in sorted(base.glob("review-packet-r*.json")):
    for row in json.loads(packet.read_text())["images"]:
        # Absolute paths preserve the original review identity; use the retained
        # repository path when verifying a clone at another location.
        relative = Path(row["repositoryPath"])
        assert not relative.is_absolute() and ".." not in relative.parts, relative
        path = repo / relative
        assert path.is_relative_to(base) and not path.is_symlink(), path
        assert sha(path) == row["sha256"], path
        reviewed += 1

images = []
for path in sorted(base.rglob("*.png")):
    assert not path.is_symlink()
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack(">II", data[16:24])
    assert (width, height) in [(1206, 2622), (750, 1334)], path
    images.append(dict(path=str(path.relative_to(base)), sha256=sha(path), width=width, height=height))
logs = []
for path in sorted(base.glob("*.log.gz")):
    data = gzip.decompress(path.read_bytes())
    assert data and not path.is_symlink()
    logs.append(dict(path=path.name, uncompressedBytes=len(data), uncompressedSHA256=hashlib.sha256(data).hexdigest()))

# Check actual exported outcomes, including the original failed scopes. These
# remain separate runs; a later passing repeat never relabels a failed run.
summary_outcomes = {}
expected_ui = {1: (2, 0), 2: (1, 0), 3: (1, 1), 4: (4, 0), 5: (6, 0),
               6: (1, 2), 7: (2, 0), 8: (2, 0), 9: (5, 0), 10: (5, 1), 11: (1, 0), 12: (0, 1), 13: (0, 1), 14: (0, 1), 15: (0, 1), 16: (1, 0)}
expected = {f"native-r{run}-summary.json": (1, 0) for run in range(1, 6)}
expected.update({f"ui-r{run}-summary.json": counts for run, counts in expected_ui.items()})
for name, counts in expected.items():
    outcome = json.loads((base / name).read_text())
    actual = (outcome["passedTests"], outcome["failedTests"])
    assert actual == counts and outcome["skippedTests"] == 0, (name, actual, counts)
    summary_outcomes[name] = dict(passed=actual[0], failed=actual[1], skipped=0)

logic_outcomes = {}
for name in ["logic-r2.log.gz", "logic-r3.log.gz"]:
    output = gzip.decompress((base / name).read_bytes()).decode()
    passed = len(re.findall(r"^PASS:", output, re.MULTILINE))
    assert passed == 1610 and not re.search(r"^FAIL:", output, re.MULTILINE), name
    assert "All import, model, totals, history, plan, conversation, evidence, document and reminder checks passed." in output
    logic_outcomes[name] = dict(passedLines=passed, failedLines=0)

release = json.loads((base / "release-audit-r1.json").read_text())
assert release["status"] == "passed" and release["applicationSources"] == "application-source-r6.json"
assert release["sourceInputs"] == 208 and release["minimumOSVersion"] == "18.0"
assert set(release["architectures"].split()) == {"arm64", "x86_64"}
assert len(release["checkedDevelopmentMarkers"]) == 58 and not release["foundDevelopmentMarkers"]
assert len(release["debugPositiveControls"]) == 13

personal = json.loads((base / "native-r2-report.json").read_text())
assert personal["status"] == "Personal context checks passed"
assert len(personal["checks"]) == 29 and all(row["passed"] for row in personal["checks"])
assert personal["writeFailure"]["domain"] == "NSCocoaErrorDomain"
assert personal["requests"] == json.loads((base / "native-r2-server-audit.json").read_text())["personalAudit"]
conversation = json.loads((base / "native-r3-conversation-report.json").read_text())
assert len(conversation["checks"]) == 49 and all(row["passed"] for row in conversation["checks"])
assert json.loads((base / "native-r2-host-readback.json").read_text())["result"] == "passed"
current_personal = json.loads((base / "native-r4-report.json").read_text())
assert current_personal["status"] == "Personal context checks passed"
assert len(current_personal["checks"]) == 33 and all(row["passed"] for row in current_personal["checks"])
assert current_personal["requests"] == json.loads((base / "native-r4-server-audit.json").read_text())["personalAudit"]
assert json.loads((base / "native-r4-host-readback.json").read_text())["result"] == "passed"
latest_personal = json.loads((base / "native-r5-report.json").read_text())
assert latest_personal["status"] == "Personal context checks passed"
assert len(latest_personal["checks"]) == 43 and all(row["passed"] for row in latest_personal["checks"])
assert latest_personal["requests"] == json.loads((base / "native-r5-server-audit.json").read_text())["personalAudit"]
assert len(latest_personal["requests"]) == 8
assert json.loads((base / "native-r5-host-readback.json").read_text())["result"] == "passed"
assert json.loads((base / "ui-r1-host-readback.json").read_text())["result"] == "passed"
observation = json.loads((base / "ui-r2-observation/observation.json").read_text())
assert observation["status"] == "captured"
assert sha(base / "ui-r2-observation" / observation["capture"]) == observation["captureSHA256"]

result = dict(status="passed", checkedAtUTC=datetime.now(timezone.utc).isoformat(), currentSources=sources,
              preservedRuntimeSources=historical_sources,
              retainedPNGFiles=len(images), selectedReviewImageRecords=reviewed, pngs=images, completeCompressedLogs=logs,
              scopedSummaryOutcomes=summary_outcomes,
              logicLogOutcomes=logic_outcomes, releaseAudit="release-audit-r1.json",
              scope="Exact current source, retained pixels/logs, selected review identities and explicitly scoped native/host outcomes. No full visual, combined final-source runtime suite, performance, device or publication acceptance.")
(base / "evidence-audit.json").write_text(json.dumps(result, indent=2) + "\n")
print(sources)
print(len(images), "retained PNGs,", len(logs), "complete compressed logs,", reviewed, "selected review identities match")
