"""Finite synthetic pending-capture/real-root-error producer. Review before use."""
import argparse
import gzip
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
import traceback

BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('capture_evidence', BASE / 'capture-state-evidence-r1.py')
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)
h, ns = e.h, e.ns
p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--build', required=True)
p.add_argument('--case', choices=list(e.CASES), required=True)
p.add_argument('--trial', required=True)
a = p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9-]+', a.trial)
raw = Path('/tmp/LumenBatch44Checks')
raw.mkdir(exist_ok=True)
stem = 'HealthCaptureState' + ''.join(word.title() for word in a.case.split('-')) + a.trial
prefix = 'health-capture-state-' + a.case + '-' + a.trial.lower()
ui = 'health-capture-pending-back' if a.case == 'pending-back' else 'health-capture-failure-retry'
result, log = raw / (stem + '.xcresult'), raw / (stem + '.log')
outpath = BASE / (prefix + '-outcome.json')
assert not result.exists() and not log.exists() and not outpath.exists(), 'Never restart a trial'
assert not any(BASE.glob(prefix + '-*')), 'Preserve even a partial preflight/retention from an interrupted trial'
assert shutil.disk_usage(h.REPO).free > 8 * 1024**3
started = time.time()
state = {'source': a.source, 'build': a.build, 'case': a.case, 'device': h.DEVICE,
         'started': started, 'boundaries': [], 'messages': {}, 'messageHistory': [], 'status': 'RUNNING unaccepted capture case'}
fault = None
process = None
native_code = None
host_error = None


def persist():
    (BASE / (prefix + '-driver-observations.json')).write_text(json.dumps(state, indent=2) + '\n')


def message(group, name, record, phase=None):
    path = group / name
    expected = state['messages'].get(name)
    if os.path.lexists(path):
        assert expected is not None and h.load(path) == expected
    else:
        assert expected is None
    value = {key: record[key] for key in ['runID', 'nonce', 'ordinal']}
    if phase is not None:
        value['phase'] = phase
    temporary = path.with_name(name + '.' + record['nonce'] + '.tmp')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        data = json.dumps(value, sort_keys=True).encode()
        assert os.write(descriptor, data) == len(data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    state['messageIntended'] = {'path': str(path), 'value': value, 'at': time.time()}
    persist()
    temporary.replace(path)
    assert h.load(path) == value
    state['messages'][name] = value
    state['messageHistory'].append({'file': str(path), 'value': value, 'at': time.time(),
                                   'afterBoundary': state['boundaries'][-1]['phase']})
    state['messageIntended'] = None
    persist()


def boundary(phase, group, *, selection=None, physical_root=None):
    root = group / 'LumenData'
    row = {'phase': phase, 'at': time.time(), 'physicalRoot': str(physical_root or root)}
    state['boundaries'].append(row)
    persist()
    try:
        row['current'] = h.snapshot(physical_root or root)
        row['currentMetadata'] = ns.tree(physical_root or root)
        row['prior'] = h.snapshot(root.with_suffix('.previous'))
        row['priorMetadata'] = ns.tree(root.with_suffix('.previous'))
        row['fixed'] = {}
        e.fixed(state['checkpoint']['legacyOrigins'], row['fixed'])
        row['provider'] = h.provider()
        row['installed'] = h.installed(a.build)
        row['capture'] = e.capture(group, started, a.case)
        row['originEvents'] = h.events(group)
        if selection is not None:
            row['source'] = selection
            e.source_exact(selection)
        persist()
        assert row['current'] == state['before'] and row['currentMetadata'] == state['beforeMetadata']
        assert row['prior'] == state['prior'] and row['priorMetadata'] == state['priorMetadata']
        assert row['fixed'] == state['fixed'] and row['provider'] == state['provider']
        assert not row['currentMetadata']['directories'] and not row['priorMetadata']['directories']
        assert not list(group.glob('LumenData.restore-*')) and not list(group.glob('LumenData.retired-*'))
        assert not any(event['event'] == 'acquire' for event in row['originEvents'])
        row['status'] = 'PASS'
    except BaseException:
        row['status'] = 'FAILED'
        row['error'] = traceback.format_exc()
        raise
    finally:
        persist()
    return row


def cleanup(selection, group, phase):
    value = e.clean_no_open(selection)
    state[phase] = value
    boundary(phase, group)


try:
    state['preflight'] = h.verify_inputs(a.source, a.build)
    persist()
    test = ('testHealthBackupFileRecoveryCapturePendingBackLegacyOriginData' if a.case == 'pending-back'
            else 'testHealthBackupFileRecoveryCaptureFailureRetryLegacyOriginData')
    command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
        '-destination', 'platform=iOS Simulator,id=' + h.DEVICE, '-derivedDataPath', '/tmp/LumenBatch37Simulator',
        '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages', '-disableAutomaticPackageResolution',
        '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
        '-only-testing:LumenUITests/LumenSmokeTests/' + test, '-resultBundlePath', str(result), 'test-without-building']
    state['command'] = command
    with log.open('xb') as stream:
        process = subprocess.Popen(command, cwd=h.REPO, stdout=stream, stderr=subprocess.STDOUT)
        subprocess.Popen(['caffeinate', '-i', '-w', str(process.pid)])
        state['nativePID'] = process.pid
        persist()
        print('Actual capture native PID', process.pid, flush=True)
        deadline = time.monotonic() + 800
        while process.poll() is None:
            assert time.monotonic() < deadline, 'Finite producer deadline'
            group = h.container('group.com.dbakp.lumen')
            root = group / 'LumenData'
            text = log.read_text()
            captured = lambda suffix: ("Added attachment named '" + ui + '-' + suffix + "'") in text
            if 'checkpoint' not in state:
                baseline = group / 'Lumen-health-backup-baseline.json'
                if not baseline.exists() or baseline.stat().st_mtime < started or 'Tap "chooseBackup" Button' not in text:
                    time.sleep(0.2)
                    continue
                checkpoint = h.load(baseline)
                assert checkpoint['case'] == 'legacy' and checkpoint['missing'] == ['meals.json', 'workouts.json']
                protocol = e.capture(group, started, a.case)
                assert protocol['events'] == [] and h.events(group) == []
                executable = subprocess.check_output(['ps', '-p', str(protocol['pid']), '-o', 'comm='], text=True).strip()
                assert Path(executable) == h.container('app') / 'Lumen'
                for name in ['Lumen-legacy-capture-release.json', 'Lumen-legacy-capture-host-ack.json']:
                    assert not os.path.lexists(group / name), 'Prior known metadata must be backed/cleaned before next case'
                before = h.snapshot(root)
                for name, encoded in checkpoint['originals'].items():
                    if name == 'profile.json':
                        assert json.loads(h.base64.b64decode(before[name]['base64'])) == json.loads(h.base64.b64decode(encoded))
                    else:
                        assert before[name]['base64'] == encoded
                assert len(before) == 10 and not {'meals.json', 'workouts.json'} & set(before)
                state.update(checkpoint=checkpoint, before=before, beforeMetadata=ns.tree(root),
                    prior=h.snapshot(root.with_suffix('.previous')), priorMetadata=ns.tree(root.with_suffix('.previous')),
                    fixed={}, provider=h.provider(), initialCapture=protocol)
                e.fixed(checkpoint['legacyOrigins'], state['fixed'])
                assert len(state['prior']) == 10
                boundary('initial-before-selection', group)
            current = e.capture(group, started, a.case)
            e.same_protocol(current, state['initialCapture'])
            state['latestCapture'] = current
            first_event = 'held-after-read' if a.case == 'pending-back' else 'held-before-read'
            progress_name = 'pending-progress' if a.case == 'pending-back' else 'before-read-progress'
            if 'held' not in state and captured(progress_name):
                held = e.unique(current, 1, first_event)
                assert held['leaseState'] == 'capturing' and not held['metadataAvailable']
                assert held['controlAlive'] and not held['controlCancelled'] and not held['taskCancelled']
                assert not any(event['event'] != 'open' for event in h.events(group))
                state['selection'] = e.selected(started)
                assert state['selection']['source']['owner']['pid'] == current['pid']
                state['held'] = held
                boundary('held-before-action', group, selection=state['selection'])
                if a.case == 'retry-failure':
                    protected = {'current': state['beforeMetadata'], 'prior': state['priorMetadata'],
                        'fixed': state['fixed'], 'provider': state['provider'], 'selection': state['selection']}
                    fault = ns.SyntheticRootFileFault(root, run_id=current['runID'], nonce=held['nonce'], protected=protected)
                    state['faultDescriptor'] = fault.recovery_descriptor()
                    persist()
                    # Persist the independently retained descriptor before namespace mutation.
                    descriptor_path = BASE / (prefix + '-fault-descriptor.json')
                    with descriptor_path.open('x') as descriptor_stream:
                        json.dump(state['faultDescriptor'], descriptor_stream, indent=2)
                        descriptor_stream.flush(); os.fsync(descriptor_stream.fileno())
                    parent_descriptor = os.open(BASE, os.O_RDONLY | os.O_DIRECTORY)
                    try:
                        os.fsync(parent_descriptor)
                    finally:
                        os.close(parent_descriptor)
                    fault.install()
                    boundary('sentinel-before-real-read-release', group, selection=state['selection'], physical_root=fault.moved)
                    fault.assert_sentinel()
                    message(group, 'Lumen-legacy-capture-release.json', held)
            if a.case == 'pending-back' and 'held' in state:
                held = state['held']
                if 'choicesChecked' not in state and captured('pending-choices'):
                    boundary('pending-choices-before-back', group, selection=state['selection'])
                    assert not e.records(current, 1, 'finish-accepted')
                    state['choicesChecked'] = True
                    message(group, 'Lumen-legacy-capture-host-ack.json', held, 'pending-choices-checked')
                if 'backHeld' not in state and captured('parent-old-worker-held'):
                    closed = e.records(current, 1, 'owner-closed')
                    if not closed:
                        time.sleep(0.1); continue
                    assert all(row['leaseState'] == 'closed' and row['controlCancelled'] and not row['metadataAvailable'] for row in closed)
                    assert not e.records(current, 1, 'capture-returned-error')
                    boundary('back-old-worker-still-held', group, selection=state['selection'])
                    state['backHeld'] = closed
                    message(group, 'Lumen-legacy-capture-release.json', held)
                if 'backHeld' in state and 'oldTerminal' not in state:
                    terminal = e.records(current, 1, 'capture-returned-error')
                    wrapper = e.records(current, 1, 'ui-wrapper-cleanup')
                    if terminal and wrapper:
                        rejection = e.unique(current, 1, 'capture-threw-finish')
                        assert rejection['controlCancelled'] and rejection['leaseState'] == 'closed' and not rejection['metadataAvailable']
                        assert terminal[0]['controlCancelled'] and not e.records(current, 1, 'finish-accepted')
                        assert not any(event['event'] in ['ready', 'acquire'] for event in h.events(group))
                        state['oldTerminal'] = {'rejection': rejection, 'afterReturn': terminal, 'uiWrapperCleanup': wrapper}
                        cleanup(state['selection'], group, 'oldWorkerTerminalCleanup')
                        message(group, 'Lumen-legacy-capture-host-ack.json', held, 'old-worker-terminal')
                if 'freshSelection' not in state and captured('fresh-review'):
                    ready = e.unique(current, 2, 'finish-accepted')
                    assert ready['leaseState'] == 'ready' and ready['metadataAvailable'] and not ready['controlCancelled']
                    assert ready['sessionID'] != held['sessionID'] and ready['controlID'] != held['controlID']
                    selection = e.selected(started)
                    assert set(selection['workspaces']).isdisjoint(state['selection']['workspaces'])
                    assert selection['source']['owner'] != state['selection']['source']['owner']
                    state['freshSelection'] = selection
                    boundary('fresh-ready', group, selection=selection)
                    message(group, 'Lumen-legacy-capture-host-ack.json', ready, 'fresh-ready-checked')
                if 'finalCleanup' not in state and captured('fresh-parent'):
                    cleanup(state['freshSelection'], group, 'finalCleanup')
                    message(group, 'Lumen-legacy-capture-host-ack.json', e.unique(current, 2, 'registered'), 'final-cleanup-checked')
            if a.case == 'retry-failure' and fault is not None:
                if 'genuineFailure' not in state and captured('genuine-failure'):
                    failed = e.unique(current, 1, 'capture-threw-capture')
                    assert not failed['controlCancelled'] and not failed['taskCancelled'] and not failed['metadataAvailable']
                    assert failed['leaseState'] == 'capturing' and 'HealthLocalFiles.Failure' in failed['errorType']
                    assert not e.records(current, 1, 'finish-accepted')
                    assert e.records(current, 1, 'capture-returned-error') and e.records(current, 1, 'ui-wrapper-cleanup')
                    fault.assert_sentinel()
                    boundary('real-operational-failure-before-restore', group, selection=state['selection'], physical_root=fault.moved)
                    state['genuineFailure'] = failed
                    fault.record('capture-failed', originalError=failed,
                        afterReturn=e.records(current, 1, 'capture-returned-error'),
                        uiWrapperCleanup=e.records(current, 1, 'ui-wrapper-cleanup'))
                    fault.restore()
                    state['faultRestored'] = True
                    boundary('root-restored-before-retry', group, selection=state['selection'])
                    message(group, 'Lumen-legacy-capture-host-ack.json', state['held'], 'root-restored')
                if 'retryReady' not in state and captured('retry-off-choices'):
                    ready = e.unique(current, 2, 'finish-accepted')
                    first = state['held']
                    assert ready['sessionID'] == first['sessionID'] and ready['controlID'] != first['controlID']
                    assert ready['nonce'] != first['nonce'] and ready['leaseState'] == 'ready' and ready['metadataAvailable']
                    assert not ready['controlCancelled'] and not ready['taskCancelled']
                    state['retryReady'] = ready
                    boundary('actual-check-again-ready', group, selection=state['selection'])
                    message(group, 'Lumen-legacy-capture-host-ack.json', ready, 'retry-ready-checked')
                if 'finalCleanup' not in state and captured('retry-parent'):
                    cleanup(state['selection'], group, 'finalCleanup')
                    message(group, 'Lumen-legacy-capture-host-ack.json', e.unique(current, 2, 'registered'), 'final-cleanup-checked')
            persist()
            time.sleep(0.15)
        native_code = process.wait()
        assert native_code == 0 and 'finalCleanup' in state
        state['finalCapture'] = e.capture(group, started, a.case)
        state['finalOriginEvents'] = h.events(group)
        state['after'] = h.snapshot(root)
        state['afterMetadata'] = ns.tree(root)
        assert state['after'] == state['before'] and state['afterMetadata'] == state['beforeMetadata']
        state['status'] = 'PASS strict host capture-state observations; native retention/root/critic pending'
except BaseException:
    host_error = traceback.format_exc()
    state['status'] = 'FAILED or incomplete actual capture case; no acceptance'
    state['hostError'] = host_error
    persist()
finally:
    if process is not None and process.poll() is None:
        process.send_signal(signal.SIGINT)
        state['interruptSentAt'] = time.time(); persist()
        for attempt in range(3):
            try:
                native_code = process.wait(timeout=60)
                break
            except subprocess.TimeoutExpired:
                state['nativeGraceWaits'] = attempt + 1; persist()
        if process.poll() is None:
            process.kill(); native_code = process.wait()
            state['nativeForcedTermination'] = True
    if fault is not None:
        try:
            if not state.get('faultRestored'):
                # Only this verified synthetic app/device, after native producer termination.
                termination = subprocess.run(['xcrun', 'simctl', 'terminate', h.DEVICE, 'com.dbakp.lumen'], capture_output=True, text=True)
                state['failureAppTermination'] = {'exit': termination.returncode, 'stdout': termination.stdout, 'stderr': termination.stderr}
                fault.restore()
                state['faultRestoredOnFailure'] = True
            state['faultJournal'] = {'file': str(fault.journal), 'bytes': fault.journal.stat().st_size,
                                     'sha256': h.sha(fault.journal.read_bytes())}
            (BASE / (prefix + '-fault-journal.jsonl.gz')).write_bytes(gzip.compress(fault.journal.read_bytes(), mtime=0))
        except BaseException:
            state['faultRestorationOrRetentionError'] = traceback.format_exc()
            host_error = host_error or state['faultRestorationOrRetentionError']
        finally:
            fault.close()
    state['nativeExit'] = native_code
    state['finished'] = time.time()
    persist()
    retainer = e.module('capture_retainer', 'retain-mixed-ineligible-results-r1.py')
    retained = retainer.retain(BASE, raw, stem, prefix, a.source)
    outcome = {'source': a.source, 'build': a.build, 'case': a.case, 'nativeExit': native_code,
               'hostError': host_error, 'retention': retained, 'summary': retained['summary'], 'physicalDeviceActions': False}
    try:
        assert host_error is None and native_code == 0 and not retained['errors']
        assert [retained['summary'][key] for key in ['passedTests', 'failedTests', 'skippedTests']] == [1, 0, 0]
        assert len(retained['images']) == 6 and len(retained['readbacks']) == 1
        helper = h.load(BASE / retained['readbacks'][0]['file'])
        e.native_helper(helper, a.case, state['finalCapture']['runID'])
        e.completed_state(state)
        outcome['status'] = 'PASS actual native1/0/0 and strict host; independent readonly/root/original review pending'
        (BASE / (prefix + '-host-audit.json')).write_text(json.dumps(state, indent=2) + '\n')
    except BaseException:
        outcome['status'] = 'FAILED or incomplete capture case; no acceptance'
        outcome['failure'] = traceback.format_exc()
        host_error = host_error or outcome['failure']
    outcome['driverExit'] = 0 if host_error is None else 1
    outpath.write_text(json.dumps(outcome, indent=2) + '\n')
    print(outcome['status'], flush=True)
raise SystemExit(0 if host_error is None else 1)
