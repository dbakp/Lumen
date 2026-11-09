"""Read current completed full build, exact pair, source/FileList and markers."""
from pathlib import Path
import base64, gzip, hashlib, json, re, shlex, time
B = Path(__file__).resolve().parent; R = B.parents[2]
load = lambda name: json.loads((B / name).read_bytes())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
m = load('durable-source-r260.json'); a = json.loads(gzip.decompress((B / 'durable-source-r260.json.gz').read_bytes()))
count = 0
for group, key in [('files', 'files'), ('fixtureInputs', 'binaryFiles')]:
    assert set(m[group]) == set(a[key])
    for name, fact in m[group].items():
        path = R / name; assert not path.is_symlink(); raw = path.read_bytes()
        assert len(raw) == fact['bytes'] and sha(raw) == fact['sha256']
        assert raw == (a[key][name].encode() if key == 'files' else base64.b64decode(a[key][name], validate=True)); count += 1
receipt = load('health-target-change-source260-r1-build.json'); out = load('source260-target-change-native-build-r1-outcome.json')
assert out['source'] == receipt['source'] == m['source']
assert type(out['exitCode']) is int and type(receipt['buildExit']) is int and out['exitCode'] == receipt['buildExit'] == 0
assert type(out['processPID']) is int and out['processPID'] > 0
assert receipt['sourceInputs'] == len(m['files']) and receipt['fixtureInputs'] == len(m['fixtureInputs'])
app_path = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen')
test_path = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/LumenUITests-Runner.app/PlugIns/LumenUITests.xctest/LumenUITests')
assert receipt['testBinary'] == str(test_path)
app = app_path.read_bytes(); test = test_path.read_bytes()
assert len(app) == receipt['binaryBytes'] and sha(app) == receipt['sha256']
assert len(test) == receipt['testBinaryBytes'] and sha(test) == receipt['testBinarySHA256']
raw = gzip.decompress((B / out['log']).read_bytes())
assert raw == Path('/tmp/LumenBatch44Checks/Source260TargetChangeNativeBuildR1.log').read_bytes()
assert len(raw) == out['logBytes'] and sha(raw) == out['logSHA256'] and b'** TEST BUILD SUCCEEDED **' in raw
for name in ['HealthRetainedRecoveryReviewSession.swift', 'HealthRetainedReviewUIFixture.swift', 'HealthRecoveryView.swift', 'SettingsView.swift', 'LumenApp.swift', 'LumenSmokeTests.swift']:
    assert name.encode() in raw, name
filelist = Path('/tmp/LumenBatch37Simulator/Build/Intermediates.noindex/Lumen.build/Debug-iphonesimulator/Lumen.build/Objects-normal/arm64/Lumen.SwiftFileList')
filelist_raw = filelist.read_bytes(); paths = [Path(name) for name in shlex.split(filelist_raw.decode())]
assert len(paths) == len(set(paths))
expected = {name for name in m['files'] if name.startswith(('Lumen/', 'Shared/')) and name.endswith('.swift')}
actual = {str(path.relative_to(R)) for path in paths if path.is_relative_to(R)}
generated = [path for path in paths if not path.is_relative_to(R)]
assert actual == expected and len(generated) == 1 and generated[0].name == 'GeneratedAssetSymbols.swift'
assert generated[0].is_relative_to('/tmp/LumenBatch37Simulator')
pre = load('health-current-release-source260-r1-predeclared-plan.json'); resolved = load('health-current-release-source260-r1-plan.json')
controls = load('source260-current-debug-release-controls-r1.json')
for key in ['checkedDevelopmentMarkers', 'debugPositiveControls', 'negativeMarkersWithoutDebugPositive', 'verifiedProductionMarkers']:
    assert pre[key] == resolved[key]
assert resolved['debugPositiveSHA256'] == controls['debugSHA256'] == sha(app)
assert all(value.encode() in app for value in pre['debugPositiveControls'] + pre['verifiedProductionMarkers'])
assert [value for value in pre['checkedDevelopmentMarkers'] if value.encode() not in app] == pre['negativeMarkersWithoutDebugPositive']
assert controls['counts'] == {'negative': 219, 'actualDebugPositive': 203, 'negativeOnly': 16, 'production': 21}
old = load('health-target-change-source257-r1-build.json')
assert sha(app) != old['sha256'] and sha(test) != old['testBinarySHA256']
proof = load('source260-source-exact-github.json'); assert proof['source'] == m['source'] and proof['commit'] == '3b4e88733919e3e806cb59815fd749e669449075'
target = B / 'source260-root-build-controls-r1.json'; assert not target.exists()
result = {'status': 'PASS current full app/test build, complete source/FileList and2192031621 actual markers; native pending',
          'source': m['source'], 'sourceBindings': count, 'buildPID': out['processPID'], 'buildExit': 0,
          'appBytes': len(app), 'appSHA256': sha(app), 'testBytes': len(test), 'testSHA256': sha(test),
          'logBytes': len(raw), 'logSHA256': sha(raw), 'swiftFileList': {'count': len(paths), 'frozen': len(actual), 'bytes': len(filelist_raw), 'sha256': sha(filelist_raw), 'generated': str(generated[0])},
          'markerCounts': [219, 203, 16, 21], 'warnings': [line for line in raw.decode().splitlines() if re.search(r'(?:^|\s)warning:', line)],
          'supportRecipeOutsideFrozen1162': {'file': Path(__file__).name, 'bytes': Path(__file__).stat().st_size, 'sha256': sha(Path(__file__).read_bytes())},
          'scope': 'Current full app/test compiled, including retained owner/Settings/fixture/wholeUI test. Both binaries differ257. Compilation only, no native navigation/recovery/backend/Release/global design/fullgoal acceptance. Historical cached257 pair/control paths now overwritten; never rerun those old namespaces.', 'checkedAt': time.time()}
target.write_text(json.dumps(result, indent=2) + '\n'); print(result['status'])
