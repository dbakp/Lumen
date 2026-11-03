"""Audit the shipping configuration against the predeclared marker plan."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--debug-bundle', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
plan_path = base / 'release-audit-plan-r1.json'
plan = json.loads(plan_path.read_text())
source_path = base / plan['source']
source = json.loads(source_path.read_text())
for name, facts in source['files'].items():
    path = repo / name
    assert path.is_file() and not path.is_symlink(), name
    data = path.read_bytes()
    assert len(data) == facts['bytes'] and hashlib.sha256(data).hexdigest() == facts['sha256'], name

def executable(bundle):
    assert bundle.is_dir() and not bundle.is_symlink()
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    path = bundle / info['CFBundleExecutable']
    assert path.is_file() and not path.is_symlink()
    return info, path, path.read_bytes()

info, path, data = executable(args.bundle)
debug_info, debug_path, debug = executable(args.debug_bundle)
assert hashlib.sha256(debug).hexdigest() == plan['debugPositiveSHA256'], 'Debug boundary changed'
found = [marker for marker in plan['checkedDevelopmentMarkers'] if marker.encode() in data]
assert not found, ('Release contains development markers', found)
missing = [marker for marker in plan['debugPositiveControls'] if marker.encode() not in debug]
assert not missing, ('Debug positive controls missing', missing)
assert all(marker.encode() in data for marker in plan['verifiedProductionMarkers']), 'Production controls missing'
models = [str(item.relative_to(args.bundle)) for item in args.bundle.rglob('*')
          if item.suffix in {'.mlmodelc', '.mlpackage', '.mlmodel'}]
assert not models, models
assert info['MinimumOSVersion'] == plan['minimumOSVersion'], info['MinimumOSVersion']
architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', str(path)], text=True).split()
assert sorted(architectures) == sorted(plan['architectures']), architectures
result = {
    'status': 'passed', 'checkedAtUTC': datetime.now(timezone.utc).isoformat(),
    'source': plan['source'], 'applicationSource': plan['applicationSource'],
    'sourceManifestSHA256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
    'auditorSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'planSHA256': hashlib.sha256(plan_path.read_bytes()).hexdigest(),
    'sourceInputs': len(source['files']), 'executableSHA256': hashlib.sha256(data).hexdigest(),
    'executableBytes': len(data), 'minimumOSVersion': info['MinimumOSVersion'],
    'architectures': architectures, 'bundledModelPackages': models,
    'checkedDevelopmentMarkers': plan['checkedDevelopmentMarkers'], 'foundDevelopmentMarkers': found,
    'debugPositiveControls': plan['debugPositiveControls'],
    'debugPositiveControlSHA256': hashlib.sha256(debug).hexdigest(),
    'verifiedProductionMarkers': plan['verifiedProductionMarkers'],
    'scope': 'Unsigned generic iOS Simulator Release executable, minimum OS and model-bundle checks. '
             'Current Debug positive controls detected at the frozen binary. '
             'No signed-device, live-provider, privacy governance or distribution approval.',
}
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(len(plan['checkedDevelopmentMarkers']), 'development markers absent;',
      len(plan['debugPositiveControls']), 'Debug positive controls present; production controls retained.')
