"""Capture the owned native screen when the quote/relaunch AX query begins."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--log", type=Path, required=True)
parser.add_argument("--device", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(exist_ok=True)
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
report = {"scope": "Observation only. Native simulator pixels at the first post-quote/relaunch coach-message AX query. No additional AX request, app mutation, startup latency or physical-device claim.",
          "monitorSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          "device": args.device, "sourceLog": str(args.log), "status": "waiting for exact query"}
output = args.output / "observation.json"
output.write_text(json.dumps(report, indent=2) + "\n")
deadline = time.monotonic() + 600
while time.monotonic() < deadline:
    text = args.log.read_text() if args.log.exists() else ""
    if "1084-earlier-personal-reply-unsent-quote" in text:
        tail = text.rsplit("1084-earlier-personal-reply-unsent-quote", 1)[1]
        if 'Waiting 10.0s for "coachMessage" Any to exist' in tail:
            report["queryObservedUTC"] = datetime.now(timezone.utc).isoformat()
            capture = args.output / "1092-relaunch-query-native-screen.png"
            completed = subprocess.run(["xcrun", "simctl", "io", args.device, "screenshot", str(capture)],
                                       env=environment, capture_output=True, text=True, timeout=20)
            report["captureExitCode"] = completed.returncode
            report["captureFinishedUTC"] = datetime.now(timezone.utc).isoformat()
            report["status"] = "captured" if completed.returncode == 0 else "capture failed"
            if completed.returncode == 0:
                report["capture"] = capture.name
                report["captureSHA256"] = hashlib.sha256(capture.read_bytes()).hexdigest()
            else:
                report["captureDiagnostic"] = completed.stderr[-1000:]
            break
    if "** TEST EXECUTE" in text:
        report["status"] = "test terminal before exact query was observed"
        break
    time.sleep(1)
else:
    report["status"] = "observation deadline reached; no capture accepted"
output.write_text(json.dumps(report, indent=2) + "\n")
print(report["status"], flush=True)
