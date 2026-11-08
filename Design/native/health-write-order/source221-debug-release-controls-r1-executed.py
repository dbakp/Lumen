"""Bind predeclared marker arrays to the actual221Debug build before Release."""
import hashlib
import json
from pathlib import Path
import time
import traceback

base = Path(__file__).resolve().parent
predeclared = base / 'health-current-release-source221-r1-predeclared-plan.json'
plan = json.loads(predeclared.read_bytes())
receipt = json.loads((base / 'health-settings-erasure-source221-r1-build.json').read_bytes())
output = base / 'source221-current-debug-release-controls-r1.json'
resolved = base / 'health-current-release-source221-r1-plan.json'
assert not output.exists() and not resolved.exists(), 'Never overwrite a previous actual preflight'
assert receipt['source'] == plan['source'] == 'durable-source-r221.json' and receipt['buildExit'] == 0
data = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen').read_bytes()
sha = hashlib.sha256(data).hexdigest()
assert sha == receipt['sha256'] and len(data) == receipt['binaryBytes']
row = {'source': plan['source'], 'status': 'Checking actual Debug controls', 'debugSHA256': sha,
       'debugBytes': len(data), 'predeclaredSHA256': hashlib.sha256(predeclared.read_bytes()).hexdigest(),
       'missingDebugPositive': [value for value in plan['debugPositiveControls'] if value.encode() not in data],
       'negativeOnlyObserved': [value for value in plan['checkedDevelopmentMarkers'] if value.encode() not in data],
       'missingProductionControls': [value for value in plan['verifiedProductionMarkers'] if value.encode() not in data]}
try:
    assert [len(plan[key]) for key in ['checkedDevelopmentMarkers', 'debugPositiveControls',
        'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']] == [188, 172, 16, 20]
    assert not row['missingDebugPositive'] and not row['missingProductionControls']
    assert row['negativeOnlyObserved'] == plan['negativeMarkersWithoutDebugPositive']
    row['status'] = 'PASS actual221Debug172positive/16negative-only/20production,188predeclarednegative'
    row['counts'] = {'negative': 188, 'actualDebugPositive': 172, 'negativeOnly': 16, 'production': 20}
    plan['debugPositiveSHA256'] = sha
    plan['status'] = 'Actual221Debug172matched; allpredeclared188/172/16/20arrays unchanged before Release'
    plan['actualDebugPreflight'] = output.name
    plan['checkedAt'] = time.time()
    resolved.write_text(json.dumps(plan, indent=2) + '\n')
except BaseException:
    row['status'] = 'FAILED actual Debug controls; no Release preflight acceptance'
    row['failure'] = traceback.format_exc()
    raise
finally:
    row['checkedAt'] = time.time()
    output.write_text(json.dumps(row, indent=2) + '\n')
print(json.dumps(row), flush=True)
