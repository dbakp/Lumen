"""Finite metadata-only launch in the explicitly created, fresh test device.

No erasure, generic reset, credential removal or old-device fallback.
Run only after the reviewed Source223 full outcome backup is exact on GitHub.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid

BASE = Path(__file__).resolve().parent
REPO = BASE.parents[2]
DEVICE = '5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7'
OUT = BASE / 'source224-fresh-diagnostic-r1-outcome.json'
sha = lambda data: hashlib.sha256(data).hexdigest()


def call(arguments, timeout=120):
    result = subprocess.run(['xcrun', 'simctl', *arguments], capture_output=True, timeout=timeout)
    assert result.returncode == 0, (arguments[:2], result.returncode, result.stderr.decode())
    return result.stdout.decode().strip()


def run():
    assert not OUT.exists(), 'Never overwrite an actual run'
    assert shutil.disk_usage(REPO).free > 12 * 1024**3
    backup = json.loads((BASE / 'source223-completion-exact-github.json').read_text())
    assert backup['status'].startswith('PASS')
    creation = json.loads((BASE / 'source224-fresh-reset-simulator-creation.json').read_text())
    assert creation['device'] == DEVICE and DEVICE not in creation['existingSimulatorIDs']
    devices = json.loads(call(['list', 'devices', '--json']))['devices']
    matches = [d for runtime, rows in devices.items() for d in rows if d['udid'] == DEVICE
               and runtime == creation['runtime']]
    assert len(matches) == 1 and matches[0]['name'] == creation['name']
    receipt = json.loads((BASE / 'health-reset-diagnostic-source223-r1-build.json').read_text())
    spec = importlib.util.spec_from_file_location('fresh_diagnostic_schema', BASE / 'reset-preflight-diagnostic-evidence-r1.py')
    schema = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(schema)
    source = schema.h.verify_inputs('durable-source-r223.json', 'health-reset-diagnostic-source223-r1-build.json')
    app = Path(receipt['testBinary']).parents[3] / 'Lumen.app'
    state = {'status': 'RUNNING metadata-only fresh-context check', 'device': DEVICE,
             'source': source, 'started': time.time(), 'steps': [], 'physicalDeviceActions': False}

    def persist():
        OUT.write_text(json.dumps(state, indent=2) + '\n')

    persist()
    try:
        if matches[0]['state'] != 'Booted':
            call(['boot', DEVICE])
        call(['bootstatus', DEVICE, '-b'], timeout=240)
        state['steps'].append('dedicated device booted'); persist()
        # A newly created device must not already contain Lumen before installation.
        absent = subprocess.run(['xcrun', 'simctl', 'get_app_container', DEVICE, 'com.dbakp.lumen', 'app'], capture_output=True)
        assert absent.returncode != 0, 'Fresh context unexpectedly already contains the app'
        call(['install', DEVICE, str(app)])
        installed = Path(call(['get_app_container', DEVICE, 'com.dbakp.lumen', 'app'])) / 'Lumen'
        data = schema.h.read(installed, 64 * 1024 * 1024)
        assert len(data) == receipt['binaryBytes'] and sha(data) == receipt['sha256']
        group = Path(call(['get_app_container', DEVICE, 'com.dbakp.lumen', 'group.com.dbakp.lumen']))
        assert not (group / 'LumenData').exists() and not group.is_symlink()
        state['installed'] = {'bytes': len(data), 'sha256': sha(data)}
        run_id = str(uuid.uuid4()).upper()
        args = ['-resetForUITests', '-health-backup-ui-fixture', '-health-backup-case', 'legacy',
                '-health-backup-healthy-merge-ui', '-health-backup-empty-ui', '-health-legacy-origin-ui', 'data',
                '-health-legacy-reset-ui', '-health-legacy-reset-run', run_id, '-health-legacy-reset-diagnostic-only']
        state['launchArguments'] = args; persist()
        launched = call(['launch', DEVICE, 'com.dbakp.lumen', *args])
        pid = int(launched.rsplit(':', 1)[1].strip())
        path = group / (schema.PREFIX + run_id.lower() + '.json')
        deadline = time.monotonic() + 30
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        raw = schema.h.read(path)
        diagnostic = json.loads(raw)
        state['diagnostic'] = diagnostic
        state['rawDiagnostic'] = schema.h.row(raw); persist()
        assert diagnostic['pid'] == pid and diagnostic['runID'] == run_id
        assert schema.validate(diagnostic, state['started']) == 'approved-initial'
        assert diagnostic['credentialQueryOSStatus'] == -25300
        assert not (group / 'LumenData').exists() and not (group / 'LumenData.previous').exists()
        state['status'] = 'PASS actual fresh-context metadata-only guard approval; Settings erasure unexecuted'
        state['productDataAbsent'] = True
    except BaseException as error:
        state['status'] = 'FAILED fresh-context diagnostic; no erasure acceptance'
        state['error'] = repr(error)
        raise
    finally:
        state['finished'] = time.time()
        state['availableBytes'] = shutil.disk_usage(REPO).free
        persist()
    print(state['status'], flush=True)


if __name__ == '__main__':
    run()
