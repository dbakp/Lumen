"""Bind predeclared marker arrays to the actual219Debug build before Release."""
import hashlib
import json
from pathlib import Path
import time
import traceback

base = Path(__file__).resolve().parent
predeclared = base / 'health-current-release-source219-r1-predeclared-plan.json'
plan = json.loads(predeclared.read_bytes())
receipt = json.loads((base / 'health-capture-state-source219-r1-build.json').read_bytes())
output = base / 'source219-current-debug-release-controls-r1.json'
resolved = base / 'health-current-release-source219-r1-plan.json'
assert not output.exists() and not resolved.exists(), 'Never overwrite a previous actual preflight'
assert receipt['source'] == plan['source'] == 'durable-source-r219.json' and receipt['buildExit'] == 0
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
        'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']] == [181, 166, 15, 20]
    assert not row['missingDebugPositive'] and not row['missingProductionControls']
    assert row['negativeOnlyObserved'] == plan['negativeMarkersWithoutDebugPositive']
    row['status'] = 'PASS actual219Debug166positive/15negative-only/20production,181predeclarednegative'
    row['counts'] = {'negative': 181, 'actualDebugPositive': 166, 'negativeOnly': 15, 'production': 20}
    plan['debugPositiveSHA256'] = sha
    plan['status'] = 'Actual219Debug166matched; allpredeclared181/166/15/20arrays unchanged before Release'
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
