"""Check the actual unsigned Release bundle and its recorded source boundary."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--bundle", type=Path, required=True)
parser.add_argument("--debug-bundle", type=Path, required=True)
parser.add_argument("--application-sources", default="application-source-r6.json")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
inputs = json.loads((base / args.application_sources).read_text())
for name, digest in inputs.items():
    path = repo / name
    assert path.is_file() and not path.is_symlink(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name

legacy = json.loads((base.parent / "conversation-storage/release-audit-r3.json").read_text())["checkedDevelopmentMarkers"]
added = [
    "-personal-provenance-probe", "-personal-provenance-ui", "-personal-provenance-history-fixture",
    "PersonalContextNativeProbe", "PersonalContextUIFixture", "PersonalContextSearchFixture", "PersonalContextRouteFixture",
    "LUMEN_PERSONAL_TEST_NONCE", "Lumen-synthetic-personal-context-ui-receipt.json",
    "SYNTHETIC-PERSONAL-NOTE-40-A", "SYNTHETIC-PERSONAL-REPLY-40",
    "Synthetic provenance passphrase 40", "Synthetic context change failed.",
]
markers = list(dict.fromkeys(legacy + added))
info = plistlib.loads((args.bundle / "Info.plist").read_bytes())
executable = args.bundle / info["CFBundleExecutable"]
assert executable.is_file() and not executable.is_symlink()
data = executable.read_bytes()
found = [marker for marker in markers if marker.encode() in data]
assert not found, found
debug_info = plistlib.loads((args.debug_bundle / "Info.plist").read_bytes())
debug_data = (args.debug_bundle / debug_info["CFBundleExecutable"]).read_bytes()
debug_found = [marker for marker in added if marker.encode() in debug_data]
assert debug_found == added, ("Debug positive controls missing", sorted(set(added) - set(debug_found)))
production = ["PersonalContextProvenance", "Used earlier personal notes.", "Whether this reply used personal notes"]
assert all(marker.encode() in data for marker in production), "Production provenance behavior must remain in Release"
models = [str(path.relative_to(args.bundle)) for path in args.bundle.rglob("*") if path.suffix in {".mlmodelc", ".mlpackage", ".mlmodel"}]
assert not models, models
assert info["MinimumOSVersion"] == "18.0", info["MinimumOSVersion"]
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(executable)], env=environment, text=True).strip()
assert set(architectures.split()) == {"arm64", "x86_64"}, architectures
result = dict(
    status="passed", checkedAtUTC=datetime.now(timezone.utc).isoformat(), applicationSources=args.application_sources,
    sourceInputs=len(inputs), minimumOSVersion=info["MinimumOSVersion"], architectures=architectures,
    executableSHA256=hashlib.sha256(data).hexdigest(), executableBytes=len(data),
    checkedDevelopmentMarkers=markers, foundDevelopmentMarkers=found, verifiedProductionMarkers=production,
    debugPositiveControlSHA256=hashlib.sha256(debug_data).hexdigest(), debugPositiveControls=debug_found,
    bundledModelPackages=models,
    scope="Unsigned generic iOS Simulator Release main executable, minimum OS and bundled-model audit. New synthetic markers also detected in the Debug positive control. Not signed-device, live-provider, privacy governance or distribution approval.",
)
args.output.write_text(json.dumps(result, indent=2) + "\n")
print(len(markers), "development markers absent; production provenance present; Debug positive controls pass.")
