#!/usr/bin/env python3
"""Run explicit synthetic startup UI cases; independently inspect their files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--device", required=True)
parser.add_argument("--derived-data", required=True)
parser.add_argument("--packages", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
cases = [("corrupt", "testConversationStartupCorrupt"),
         ("unreadable", "testConversationStartupUnreadable"),
         ("legacy", "testConversationStartupLegacyRetry"),
         ("empty", "testConversationStartupEmptyArchive")]
report = {"scope": "Actual synthetic iOS startup UI and host file read-back after each terminal test; no physical-device or power-loss claim.",
          "runnerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "cases": []}

def save():
    (args.output / "startup-readback.json").write_text(json.dumps(report, indent=2) + "\n")

for mode, method in cases:
    result = args.output / (mode + ".xcresult")
    if result.exists():
        raise SystemExit("Refusing to replace an existing result bundle: " + str(result))
    command = ["xcodebuild", "-project", "Lumen.xcodeproj", "-scheme", "Lumen",
               "-destination", "id=" + args.device, "-derivedDataPath", args.derived_data,
               "-clonedSourcePackagesDirPath", args.packages, "-disableAutomaticPackageResolution",
               "-resultBundlePath", str(result), "-collect-test-diagnostics", "never",
               "-only-testing:LumenUITests/LumenSmokeTests/" + method,
               "CODE_SIGNING_ALLOWED=NO", "-jobs", "2", "test-without-building"]
    with (args.output / (mode + ".log")).open("w") as log:
        completed = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
    entry = {"mode": mode, "method": method, "exitCode": completed.returncode}
    report["cases"].append(entry)
    if completed.returncode:
        save()
        raise SystemExit(completed.returncode)
    container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", args.device,
                                              "com.dbakp.lumen", "data"], env=environment, text=True).strip())
    root = container / "Library/Application Support/LumenData"
    fixture = json.loads((root / "conversation-fixture-mode.json").read_text())
    assert fixture == {"mode": mode}, "Wrong fixture or unexpected app storage location"
    archive = root / "conversations.json"
    original = (root / "conversation-fixture-original.bin").read_bytes()
    attributes = archive.lstat()
    assert stat.S_ISREG(attributes.st_mode), "Refusing a nonregular fixture archive"
    permissions = stat.S_IMODE(attributes.st_mode)
    if mode == "unreadable":
        assert permissions == 0, "Expected actual denied archive permissions"
        try:
            archive.read_bytes()
        except PermissionError:
            entry["hostReadDeniedBeforeInspection"] = True
        else:
            raise AssertionError("Unreadable fixture was readable")
        # This exact reset-created synthetic file is inspected only after the
        # UI test is terminal. Return its permissions immediately afterward.
        archive.chmod(0o600)
        try:
            archive_bytes = archive.read_bytes()
        finally:
            archive.chmod(permissions)
        assert archive_bytes == original, "Unreadable history changed"
        entry["temporarySyntheticReadPermissionRestored"] = True
    else:
        archive_bytes = archive.read_bytes()
    mirror_bytes = (root / "chat.json").read_bytes()
    mirror = json.loads(mirror_bytes)
    selection = json.loads((root / "conversation-selection.json").read_bytes())
    if mode in ("corrupt", "unreadable"):
        assert archive_bytes == original, "Unavailable archive was overwritten"
        assert len(mirror) == 1 and mirror[0]["id"] == "synthetic-startup-message-39"
        entry["exactOriginalArchiveRetained"] = True
    elif mode == "legacy":
        saved = json.loads(archive_bytes)
        assert len(saved) == 1 and saved[0]["messages"] == json.loads(original) == mirror
        assert selection.get("activeID") == saved[0]["id"]
        entry["legacyLiteralMessagesAndSelectionRetained"] = True
    else:
        assert json.loads(archive_bytes) == [] and selection.get("activeID") is None
        assert len(mirror) == 1 and mirror[0]["id"] == "synthetic-startup-message-39"
        entry["emptyArchiveRetainedDespiteStaleLegacyMirror"] = True
    entry["files"] = {name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                      for name, data in [("conversations.json", archive_bytes), ("chat.json", mirror_bytes)]}
    entry["archivePermissions"] = oct(permissions)
    entry["readbackPassed"] = True
    save()
    print(mode + ": native UI and independent file read-back passed", flush=True)

sys.exit(0)
