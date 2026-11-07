"""Check a frozen current Release against its predeclared, task-specific plan."""
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
plan_path = base / 'health-current-release-source191-r1-plan.json'
plan = json.loads(plan_path.read_text())
source_path = base / plan['source']
source = json.loads(source_path.read_text())
sha = lambda data: hashlib.sha256(data).hexdigest()
for group in ('files', 'fixtureInputs'):
    for name, facts in source[group].items():
        path = repo / name
        assert path.is_file() and not path.is_symlink(), name
        data = path.read_bytes()
        assert len(data) == facts['bytes'] and sha(data) == facts['sha256'], name

def executable(bundle):
    assert bundle.is_dir() and not bundle.is_symlink()
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    path = bundle / info['CFBundleExecutable']
    assert path.is_file() and not path.is_symlink()
    return info, path, path.read_bytes()

info, path, data = executable(args.bundle)
_, _, debug = executable(args.debug_bundle)
assert sha(debug) == plan['debugPositiveSHA256'], 'Debug boundary changed'
found = [m for m in plan['checkedDevelopmentMarkers'] if m.encode() in data]
assert not found, ('Release contains development markers', found)
missing = [m for m in plan['debugPositiveControls'] if m.encode() not in debug]
assert not missing, ('Debug positive controls missing', missing)
assert all(m.encode() in data for m in plan['verifiedProductionMarkers']), 'Production controls missing'
models = [str(p.relative_to(args.bundle)) for p in args.bundle.rglob('*')
          if p.suffix in {'.mlmodelc', '.mlpackage', '.mlmodel'}]
assert not models, models
assert info['MinimumOSVersion'] == plan['minimumOSVersion'], info['MinimumOSVersion']
architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', str(path)], text=True).split()
assert sorted(architectures) == sorted(plan['architectures']), architectures
resolved = repo / 'Lumen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
pins = json.loads(resolved.read_text())['pins']
assert len(pins) == 1, pins
pin = pins[0]
assert {'identity': pin['identity'], **pin['state']} == plan['packagePin'], pin
result = {
    'status': 'passed', 'checkedAtUTC': datetime.now(timezone.utc).isoformat(),
    'source': plan['source'], 'sourceManifestSHA256': sha(source_path.read_bytes()),
    'auditorSHA256': sha(Path(__file__).read_bytes()), 'planSHA256': sha(plan_path.read_bytes()),
    'sourceInputs': len(source['files']), 'fixtureInputs': len(source['fixtureInputs']),
    'executableSHA256': sha(data), 'executableBytes': len(data),
    'bundleIdentifier': info['CFBundleIdentifier'], 'minimumOSVersion': info['MinimumOSVersion'],
    'architectures': architectures, 'bundledModelPackages': models,
    'checkedDevelopmentMarkers': plan['checkedDevelopmentMarkers'], 'foundDevelopmentMarkers': found,
    'debugPositiveControls': plan['debugPositiveControls'], 'debugPositiveControlSHA256': sha(debug),
    'verifiedProductionMarkers': plan['verifiedProductionMarkers'],
    'packagePin': plan['packagePin'], 'packageResolvedSHA256': sha(resolved.read_bytes()),
    'scope': plan['scope'], 'unmatchedNegativeControls': plan['unmatchedNegativeControls'],
}
args.output.write_text(json.dumps(result, indent=2) + '\n')
print('Passed:', len(plan['checkedDevelopmentMarkers']), 'absent development markers;',
      len(plan['debugPositiveControls']), 'Debug positives;', len(plan['verifiedProductionMarkers']),
      'production controls; arm64; minimum iOS18; no bundled models; pinned dependency.')
