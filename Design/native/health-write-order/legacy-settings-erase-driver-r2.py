"""Finite native Settings erasure producer; only dedicated synthetic simulator."""
import argparse
import gzip
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import traceback
import importlib.util

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('settings_erase_evidence', BASE / 'legacy-settings-erase-evidence-r2.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
h = e.h
f = e.module('settings_erase_finalization', 'capture-state-finalization-r2.py')
terminal = e.module('settings_erase_terminal', 'legacy-settings-erase-finalization-r1.py')
p = argparse.ArgumentParser(); p.add_argument('--source', required=True); p.add_argument('--build', required=True)
p.add_argument('--case', choices=['data', 'string'], required=True); p.add_argument('--trial', required=True)
a = p.parse_args(); assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
raw = Path('/tmp/LumenBatch44Checks'); raw.mkdir(exist_ok=True)
stem = 'HealthLegacySettingsErase' + a.case.title() + a.trial
prefix = 'health-legacy-settings-erase-' + a.case + '-' + a.trial.lower()
result, log = raw / (stem + '.xcresult'), raw / (stem + '.log')
outpath = BASE / (prefix + '-outcome.json')
assert not result.exists() and not log.exists() and not any(BASE.glob(prefix + '-*')), 'Never overwrite a trial'
assert shutil.disk_usage(h.REPO).free > 8 * 1024**3
state = {'source': a.source, 'build': a.build, 'case': a.case, 'device': h.DEVICE, 'started': time.time(),
         'boundaries': [], 'messages': [], 'status': 'RUNNING actual synthetic Settings erasure; no acceptance'}
process = None; native_code = None; error = None

def persist():
    (BASE / (prefix + '-driver-observations.json')).write_text(json.dumps(state, indent=2) + '\n')


def message(group, observation, phase):
    path = group / ('Lumen-legacy-reset-' + observation['runID'].lower() + '-ack.json')
    if path.exists(): assert h.load(path) == state['messages'][-1]['value']
    else: assert not state['messages']
    value = {key: observation[key] for key in ['runID', 'pid', 'sequence']}; value['phase'] = 'host-' + phase
    temporary = path.with_suffix('.tmp'); descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        data = json.dumps(value, sort_keys=True).encode(); assert os.write(descriptor, data) == len(data); os.fsync(descriptor)
    finally: os.close(descriptor)
    state['messageIntended'] = {'file': str(path), 'value': value, 'phase': phase}; persist()
    temporary.replace(path)
    state['messages'].append({'file': str(path), 'value': value, 'phase': phase, 'at': time.time()})
    state['messageIntended'] = None; persist()


try:
    state['preflight'] = h.verify_inputs(a.source, a.build); state['provider'] = h.provider(); persist()
    test = 'testHealthBackupFileRecoverySettingsEraseOrigin' + a.case.title()
    command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + h.DEVICE, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
        '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
        '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
        '-only-testing:LumenUITests/LumenSmokeTests/' + test, '-resultBundlePath', str(result), 'test-without-building']
    state['command'] = command
    with log.open('xb') as stream:
        process = subprocess.Popen(command, cwd=h.REPO, stdout=stream, stderr=subprocess.STDOUT)
        subprocess.Popen(['caffeinate', '-i', '-w', str(process.pid)])
        state['nativePID'] = process.pid; persist(); print('Actual Settings erase native PID', process.pid, flush=True)
        deadline = time.monotonic() + 750
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Finite producer deadline'
            group = h.container('group.com.dbakp.lumen'); root = group / 'LumenData'
            candidates = [x for x in group.glob('Lumen-legacy-reset-*-checkpoint.json') if x.stat().st_mtime >= state['started']]
            if not candidates: time.sleep(0.2); continue
            assert len(candidates) == 1
            raw_checkpoint = h.read(candidates[0])
            observation = json.loads(raw_checkpoint)
            index = len(state['boundaries'])
            if index and observation == state['boundaries'][-1]['observation']:
                time.sleep(0.2); continue
            assert index < len(e.PHASES), 'Unexpected additional checkpoint'
            mode, sequence, phase = e.PHASES[index]
            row = {'phase': phase, 'at': time.time(), 'observation': observation,
                   'rawCheckpoint': {'file': str(candidates[0]), **h.row(raw_checkpoint)}, 'status': 'OBSERVING'}
            state['boundaries'].append(row); persist()
            try:
                checked = e.checkpoint(group, candidates[0], state['started'], state.get('runID'))
                assert checked == observation
                assert (observation['mode'], observation['sequence']) == (mode, sequence), 'Out-of-order actual checkpoint'
                state['runID'] = observation['runID']
                command_path = subprocess.check_output(['ps', '-p', str(observation['pid']), '-o', 'comm='], text=True).strip()
                assert Path(command_path) == h.container('app') / 'Lumen'
                row['installed'] = h.installed(a.build)
                row['provider'] = h.provider(); assert row['provider'] == state['provider']
                if index == 0:
                    state['initialPID'] = observation['pid']; state['appExecutable'] = command_path
                    state['rawBaseline'] = h.row(h.read(group / 'Lumen-health-backup-baseline.json'))
                    baseline = json.loads(h.read(group / 'Lumen-health-backup-baseline.json')); state['baseline'] = baseline
                    assert baseline['case'] == 'legacy' and baseline['legacyOrigins']['kind'] == a.case
                    state['initialJournal'] = observation['journal']
                    assert {x['localID'] for x in observation['journal']['events']} == {'synthetic-reset-pending-removal', 'synthetic-reset-unstarted-save'}
                    deletion = next(x for x in observation['journal']['events'] if x['action'] == 'delete')
                    assert deletion['identity'] == 'sync' and deletion['components'][0]['value'] == 257 and deletion['components'][0]['date'] != -978307200
                if index in [0, 1, 2]:
                    row['currentTree'] = {}; e.observe_tree(root, row['currentTree'])
                    row['files'] = row['currentTree']['files']; row['metadata'] = row['currentTree']['metadata']
                    row['priorTree'] = {}; e.observe_tree(root.with_suffix('.previous'), row['priorTree'])
                    row['prior'] = row['priorTree']['files']; row['priorMetadata'] = row['priorTree']['metadata']
                    row['fixed'] = {}; e.fixed(state['baseline']['legacyOrigins'], row['fixed'])
                    row['originEvents'] = h.events(group)
                    if index == 0:
                        copies = {k:v for k,v in row['files'].items() if k.startswith('.health-recovery/')}
                        state['initialPrivateCopies'] = copies
                        assert len(copies) == 3 and all(row['prior'].get(k) == v for k,v in copies.items())
                        manifest_name = next(k for k in copies if k.endswith('/manifest.json'))
                        manifest = json.loads(e.base64.b64decode(copies[manifest_name]['base64']))
                        assert manifest['version'] == 1 and manifest['domains'] == ['today'] and manifest['photos'] is False and manifest['intent'] is True
                        assert not {'meals.json', 'workouts.json'} & set(row['files'])
                        assert observation['onboardingDone'] and observation['profileName'] == 'Synthetic backup baseline'
                        assert observation['stepGoal'] == 6543 and h.events(group) == []
                    else:
                        first = state['boundaries'][0]
                        for key in ['files', 'metadata', 'prior', 'priorMetadata']:
                            assert row[key] == first[key], 'Pre-erasure protected files/metadata changed: ' + key
                        assert observation['pid'] == state['initialPID'] and observation['onboardingDone']
                        assert all(x['persistedPresent'] and x['effectivePresent'] for x in observation['fixed'].values())
                        assert not any(x['event'] == 'acquire' for x in row['originEvents'])
                        if index == 1:
                            state['selection'] = h.selected(state['started']); row['selection'] = state['selection']
                            assert state['selection']['source']['owner']['pid'] == observation['pid']
                            assert [x['event'] for x in row['originEvents']] == ['open', 'ready']
                            assert row['originEvents'][1]['domains'] == ['meals', 'workouts']
                        else:
                            assert [x['event'] for x in row['originEvents']] == ['open', 'ready', 'closed']
                            stop = time.monotonic() + 5
                            while h.owned(observation['pid']) and time.monotonic() < stop: time.sleep(0.1)
                            row['cleanup'] = e.no_owned(state['selection'], observation['pid'])
                else:
                    assert (observation['pid'] == state['initialPID']) if index == 3 else (observation['pid'] != state['initialPID'])
                    if index == 5: assert observation['pid'] == state['boundaries'][4]['observation']['pid']
                    stop = time.monotonic() + 5
                    while any(group.glob('LumenData.retired-*')) and time.monotonic() < stop: time.sleep(0.1)
                    row['erased'] = {}
                    e.erased(group, observation, state['initialJournal'], state['boundaries'][0]['files'], row['erased'])
                    if index >= 4:
                        for key in ['event', 'generation', 'lifecycle']:
                            assert row['erased']['intent'][key] == state['boundaries'][3]['erased']['intent'][key]
                    if index == 5: assert observation['at'] - state['boundaries'][4]['observation']['at'] >= 3
                    assert not h.owned(observation['pid'])
                row['status'] = 'PASS'
            except BaseException:
                row['status'] = 'FAILED'; row['error'] = traceback.format_exc(); raise
            finally:
                persist()
            message(group, observation, phase)
            print('Actual strict boundary', phase, 'PASS', flush=True)
            time.sleep(0.15)
        native_code = process.wait()
        assert native_code == 0 and len(state['boundaries']) == len(e.PHASES)
        state['status'] = 'PASS actual Settings erasure and clean-relaunch host boundaries; retention/root/critic pending'
except BaseException:
    error = traceback.format_exc(); state['hostError'] = error; state['status'] = 'FAILED or incomplete actual Settings erasure; no acceptance'
finally:
    def accept(retained):
        assert not retained['errors']
        assert [retained['summary'][x] for x in ['passedTests', 'failedTests', 'skippedTests']] == [1, 0, 0]
        assert len(retained['images']) == len(e.IMAGES) and len(retained['readbacks']) == 1
        assert len(state['boundaries']) == 6 and all(x['status'] == 'PASS' for x in state['boundaries'])
        helper = h.load(BASE / retained['readbacks'][0]['file']); assert helper['phase'] == 'completed'
        assert [x['phase'] for x in helper['observations'] if 'probeValue' in x] == [x[2] for x in e.PHASES]
        (BASE / (prefix + '-host-audit.json')).write_text(json.dumps(state, indent=2) + '\n')
    outcome = terminal.finalize(process, state, persist, outpath,
        lambda: e.module('settings_erase_retainer', 'retain-mixed-ineligible-results-r1.py'),
        BASE, raw, stem, prefix, a.source, accept, f, host_error=error)
    print(outcome['status'], flush=True)
raise SystemExit(outcome['driverExit'])
