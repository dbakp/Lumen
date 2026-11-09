"""Pure expected command and exact file-fact bindings; no process queries on import."""
from pathlib import Path
import hashlib, json, stat

DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
SOURCE = 'durable-source-r260.json'
BUILD = 'health-target-change-source260-r1-build.json'
APP = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen')


def strict_json_equal(left, right):
    """Exact JSON value types, including Boolean/integer/float distinctions."""
    if type(left) is not type(right): return False
    if type(left) is dict:
        return (all(type(key) is str for key in left) and all(type(key) is str for key in right)
                and left.keys() == right.keys() and all(strict_json_equal(left[key], right[key]) for key in left))
    if type(left) is list:
        return len(left) == len(right) and all(strict_json_equal(a, b) for a, b in zip(left, right))
    if type(left) in [str, int, bool, type(None)]: return left == right
    if type(left) is float:
        import math
        return math.isfinite(left) and math.isfinite(right) and json.dumps(left) == json.dumps(right)
    return False


def require_int(value, minimum=0):
    assert type(value) is int and value >= minimum
    return value


def validate_receipt(receipt, manifest, expected_source):
    assert manifest['source'] == receipt['source'] == expected_source
    assert require_int(receipt['buildExit']) == 0
    assert require_int(receipt['sourceInputs'], 1) == len(manifest['files'])
    assert require_int(receipt['fixtureInputs']) == len(manifest['fixtureInputs'])
    require_int(receipt['binaryBytes'], 1); require_int(receipt['testBinaryBytes'], 1)
    return True


def proof_name(case):
    return {'children': 'source260-build-exact-github.json',
            'pending-back': 'source260-children-exact-github.json',
            'sheet-dismiss': 'source260-pending-back-exact-github.json'}[case]


def verify_checkpoint_facts(proof, facts, repository):
    """Anchor current acquired metadata to an already reviewed GitHub checkpoint."""
    assert proof['source'] == facts['source']
    rows = proof['proofs']; assert isinstance(rows, list)
    assert len({row['file'] for row in rows}) == len(rows)
    by_name = {row['file']: row for row in rows}
    import subprocess
    for key in ['manifest', 'archive', 'receipt']:
        fact = facts[key]; name = str(Path(fact['path']).relative_to(repository))
        row = by_name[name]
        assert strict_json_equal({'bytes': fact['bytes'], 'sha256': fact['sha256']},
                                 {'bytes': row['bytes'], 'sha256': row['sha256']})
        # The proof file itself is a local receipt. Anchor its selected rows to
        # actual Git blobs too, so an edited receipt+cache cannot self-validate.
        blob = subprocess.check_output(['git', 'cat-file', 'blob', proof['commit'] + ':' + name], cwd=repository)
        assert len(blob) == require_int(fact['bytes'], 1) and hashlib.sha256(blob).hexdigest() == fact['sha256']
    return True


def names(case):
    assert case in ['children', 'pending-back', 'sheet-dismiss']
    return 'retained-owner-source260-' + case + '-r1', 'RetainedOwnerSource260' + case.replace('-', '').title() + 'R1'


def command(case, raw):
    method = {'children': 'Children', 'pending-back': 'PendingBack', 'sheet-dismiss': 'SheetDismiss'}[case]
    return ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + DEVICE, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
        '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
        '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
        '-only-testing:LumenUITests/LumenSmokeTests/testHealthRetainedReviewOwner' + method,
        '-resultBundlePath', str(raw / (names(case)[1] + '.xcresult')), 'test-without-building']


def file_fact(path):
    path = Path(path); info = path.lstat()
    assert stat.S_ISREG(info.st_mode) and not path.is_symlink()
    raw = path.read_bytes(); after = path.lstat()
    fields = ['st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns']
    assert all(getattr(info, key) == getattr(after, key) for key in fields)
    return {'path': str(path), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
            'identity': {key: getattr(info, key) for key in fields}}


def preflight(base, source, verify_source):
    assert source == SOURCE
    count = verify_source()
    manifest_path = base / source; archive_path = base / (source + '.gz'); receipt_path = base / BUILD
    manifest = json.loads(manifest_path.read_bytes()); receipt = json.loads(receipt_path.read_bytes())
    assert validate_receipt(receipt, manifest, SOURCE)
    require_int(count, 1)
    test = Path(receipt['testBinary'])
    expected_test = Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/LumenUITests-Runner.app/PlugIns/LumenUITests.xctest/LumenUITests')
    assert test == expected_test
    result = {'source': source, 'build': BUILD, 'inputCount': count,
              'manifest': file_fact(manifest_path), 'archive': file_fact(archive_path),
              'receipt': file_fact(receipt_path), 'app': file_fact(APP), 'test': file_fact(test)}
    assert result['app']['sha256'] == receipt['sha256'] and result['app']['bytes'] == receipt['binaryBytes']
    assert result['test']['sha256'] == receipt['testBinarySHA256'] and result['test']['bytes'] == receipt['testBinaryBytes']
    return result


def validate_recorded(state, current, case, raw):
    assert state['case'] == case and state['source'] == SOURCE and state['build'] == BUILD
    assert state['prefix'] == names(case)[0] and state['stem'] == names(case)[1]
    assert state['command'] == command(case, raw)
    validate_preflight_replay(state['preflight'], current)
    assert current['source'] == SOURCE and current['build'] == BUILD
    return True


def validate_preflight_replay(recorded, current):
    """Exact replay of acquired facts; caller separately verifies current source/build."""
    assert type(recorded) is dict and strict_json_equal(recorded, current)
    assert set(current) == {'source', 'build', 'inputCount', 'manifest', 'archive', 'receipt', 'app', 'test'}
    import re
    match = re.fullmatch(r'durable-source-r([0-9]+)\.json', current['source']); assert match
    assert current['build'] == 'health-target-change-source' + match.group(1) + '-r1-build.json'
    assert type(current['inputCount']) is int and current['inputCount'] > 0
    for key in ['manifest', 'archive', 'receipt', 'app', 'test']:
        fact = current[key]
        assert set(fact) == {'path', 'bytes', 'sha256', 'identity'}
        assert isinstance(fact['path'], str) and Path(fact['path']).is_absolute()
        assert type(fact['bytes']) is int and fact['bytes'] > 0
        assert isinstance(fact['sha256'], str) and len(fact['sha256']) == 64 and all(c in '0123456789abcdef' for c in fact['sha256'])
        assert set(fact['identity']) == {'st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns'}
        assert all(type(value) is int for value in fact['identity'].values())
        assert fact['identity']['st_size'] == fact['bytes']
    assert Path(current['manifest']['path']).name == current['source']
    assert Path(current['archive']['path']).name == current['source'] + '.gz'
    assert Path(current['receipt']['path']).name == current['build']
    return True
