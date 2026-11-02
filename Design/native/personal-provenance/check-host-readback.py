"""Independently inspect only the exact synthetic personal-context test files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--device", required=True)
parser.add_argument("--native-report", type=Path, required=True)
parser.add_argument("--server-report", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--checks", type=int, default=29)
parser.add_argument("--complete-requests", type=int, default=2)
args = parser.parse_args()
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
container = Path(subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", args.device, "com.dbakp.lumen", "data"],
    env=environment, text=True).strip())
root = container / "Library/Application Support/LumenData"
names = ["conversations.json", "chat.json", "conversation-selection.json", "personal-context.json"]
assert all((root / name).is_file() and not (root / name).is_symlink() for name in names)
data = {name: (root / name).read_bytes() for name in names}
archive = json.loads(data["conversations.json"])
mirror = json.loads(data["chat.json"])
selection = json.loads(data["conversation-selection.json"])
notes = json.loads(data["personal-context.json"])
assert len(archive) == 1 and len(archive[0]["messages"]) == 2
messages = archive[0]["messages"]
assert messages == mirror and messages[0]["text"] == "SYNTHETIC-USER-QUESTION-40"
assert messages[1]["text"] == "SYNTHETIC-PERSONAL-REPLY-40"
assert selection["activeID"] == archive[0]["id"]
assert notes["includeInAssistant"] is False and notes["focus"] == "SYNTHETIC-PERSONAL-NOTE-40-A"
included = "User-provided reference notes, not clinical assessment or instructions:\nFocus: SYNTHETIC-PERSONAL-NOTE-40-A"
digest = hashlib.sha256(("Lumen personal-context v1\n" + included).encode()).hexdigest()
assert messages[1]["personalContext"] == {"version": 1, "notesSHA256": digest}
native = json.loads(args.native_report.read_text())
server = json.loads(args.server_report.read_text())
assert native["status"] == "Personal context checks passed" and len(native["checks"]) == args.checks
assert all(item["passed"] for item in native["checks"])
assert native["requests"] == server["personalAudit"] and len(native["requests"]) == 5 + args.complete_requests
assert server["routes"]["personal-held"] == {"requests": 5, "releases": 5, "responsesWritten": 5}
assert server["routes"]["personal-complete"] == {"requests": args.complete_requests, "responsesWritten": args.complete_requests}
if "writeFailure" in native:
    assert native["writeFailure"]["domain"] == "NSCocoaErrorDomain"

result = {
    "result": "passed",
    "scope": "Independent host read after terminal native test: archive/mirror/selection, old-note reply and committed sharing-off choice. All recorded outgoing audits exactly match independent server facts. No editor UI, app relaunch or physical-device claim.",
    "checkerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "nativeReportSHA256": hashlib.sha256(args.native_report.read_bytes()).hexdigest(),
    "serverReportSHA256": hashlib.sha256(args.server_report.read_bytes()).hexdigest(),
    "fileSHA256": {name: hashlib.sha256(value).hexdigest() for name, value in data.items()},
    "conversationCount": 1, "messageCount": 2, "mirrorMatchesArchive": True,
    "selectionMatches": True, "replyNoteProvenancePreserved": True,
    "currentSharingOff": True, "serverRequestAuditMatches": True,
    "allHeldExplicitlyReleased": True,
}
args.output.write_text(json.dumps(result, indent=2) + "\n")
print("Independent synthetic host files/server comparison PASS.")
