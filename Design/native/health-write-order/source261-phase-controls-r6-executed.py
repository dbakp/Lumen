"""Coordinator replay controls plus real host evidence/ack durability operations.

Persisted-state inputs are historical synthetic samples, never new native results.
Output namespaces are exclusive. Do not rerun an executed control recipe.
"""
from pathlib import Path
import base64
import copy
import gzip
import hashlib
import importlib.util
import json
import os
import tempfile
import time
import uuid

B = Path(__file__).resolve().parent
output = B / 'source261-phase-controls-r6.json'
raw_output = B / 'source261-phase-controls-r6-raw.json.gz'
assert not output.exists() and not raw_output.exists()
helper = B / 'retained-backend-phase-r2.py'; original = helper.read_bytes()
spec = importlib.util.spec_from_file_location('phase', helper)
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
historical = B / 'source261-backend-protocol-controls-r2-raw.json.gz'
samples = json.loads(gzip.decompress(historical.read_bytes()))['samples']
before = samples['before']
roots = {key: value['path'] for key, value in before['roots'].items()}
# The historical fixture had role-named roots. Rebind the recorded samples to
# canonical LumenData leaf roles for these pure-controller replay controls only.
parent = str(Path(roots['current']).parent)
roots['current'] = str(Path(parent) / 'LumenData')
roots['previous'] = str(Path(parent) / 'LumenData.previous')
for sample in samples.values():
    for label, path in roots.items(): sample['roots'][label]['path'] = path
copy_id = 'healthRecoveryCopy-' + next(name for name in before['roots']['current']['children']['.health-recovery']['children'] if name.startswith('discovered-'))
binding = {'schema': 'Lumen-retained-backend-ack-v1', 'runID': str(uuid.uuid4()).upper(),
           'runnerPID': str(os.getpid()), 'case': 'retained-meals-backend', 'phase': 'pre-recover',
           'nonce': str(uuid.uuid4()).upper(), 'copyID': copy_id,
           'sessionID': str(uuid.uuid4()).upper(), 'captureID': str(uuid.uuid4()).upper(),
           'selected': '', 'location': 'review-ready'}
checks = []; raw_files = {}; results = []
import sys
def failed(exc_type, value, tb):
    failure = {"status":"FAILED control acquisition; no acceptance", "error":repr(value), "results":results, "checks":checks, "partialSyntheticFiles":raw_files}
    if not raw_output.exists(): raw_output.write_bytes(gzip.compress(p.encoded(failure),mtime=0))
    if not output.exists(): output.write_text(json.dumps({"status":"FAILED control acquisition; no acceptance", "error":repr(value), "raw":raw_output.name},indent=2)+"\n")
    sys.__excepthook__(exc_type,value,tb)
sys.excepthook = failed


def fresh(sample):
    value = copy.deepcopy(sample)
    value['startedAt'] = time.time(); value['finishedAt'] = time.time()
    return value


def attempt(sample):
    value = fresh(sample)
    names = ['LumenData'] + ([] if value['roots']['previous']['absent'] else ['LumenData.previous'])
    entries = {name: value['roots']['current' if name == 'LumenData' else 'previous']['identityBefore'] for name in names}
    inv = {'status': 'SUPPORTED bounded task namespace inventory', 'path': parent, 'errors': [],
           'namesBefore': sorted(names), 'namesAfter': sorted(names), 'entries': entries,
           'inventoryBefore': {'names': sorted(names), 'overflow': False, 'scannedAtLeast': len(names)},
           'inventoryAfter': {'names': sorted(names), 'overflow': False, 'scannedAtLeast': len(names)}}
    return {'namespaceBefore': copy.deepcopy(inv), 'sample': value, 'namespaceAfter': copy.deepcopy(inv)}


with tempfile.TemporaryDirectory(prefix='lumen261-phase-controls-') as temporary:
    area = Path(temporary).resolve(); runner = area / 'runner'; runner.mkdir()
    def marker_for(expected):
        value = {'schema': 'Lumen-retained-backend-marker-v1', 'binding': expected,
                 'uiState': {'session': expected['sessionID'], 'capture': expected['captureID'], 'phase': 'ready', 'selected': ''},
                 'image': {'attachmentName': {'pre-recover':'retained-backend-fresh', 'post-success':'retained-backend-recovered', 'final-parent':'retained-backend-final-parent'}[expected['phase']],
                           'bytes': 1, 'sha256': hashlib.sha256(b'synthetic image identity only').hexdigest()}, 'at': time.time()}
        name = 'marker-' + str(uuid.uuid4()) + '.json'
        (runner / name).write_bytes(p.encoded(value))
        return p.transport.read(runner, name)
    def run(label, source=None, expected=None, baseline=None, prior_post=None, change=None, count=6):
        root = area / label; root.mkdir()
        expected = copy.deepcopy(expected or binding); marker = marker_for(expected)
        def acquire(unused_roots, unused_parent):
            value = attempt(source or before)
            if change: change(value)
            return value
        value = p.phase(root, label, marker, expected, {'scope': 'historical synthetic replay; no native provenance'},
                        roots, parent, baseline=baseline, prior_post=prior_post, acquire=acquire,
                        max_attempts=count, interval=0)
        results.append({'case': label, 'result': value})
        for path in sorted(root.glob('*')):
            if path.is_file(): raw_files[str(path.relative_to(area))] = p.transport.blob(path.read_bytes())
        return root, value
    def reject(label, **kwargs):
        root, result = run(label, **kwargs)
        assert result['ack'] is None and result['acceptedSample'] is None
        assert result['artifact']['status'] == 'SUPPORTED exclusive durable evidence'
        assert result['envelope']['errors']
        checks.append({'case': label, 'ackPrepared': False, 'attempts': len(result['envelope']['attempts'])})
        return root, result

    # The predicate checks the actual retained gzip before it can accept a sample.
    native_predicate = p.protocol.validate_pre
    observed = []
    def verify_order(sample, copy_id):
        candidates = sorted((area / 'positive-pre').glob('positive-pre-attempt-*.json.gz'))
        assert len(candidates) == len(observed) + 1
        saved = json.loads(gzip.decompress(candidates[-1].read_bytes()))
        assert p.protocol.same(saved['capture']['sample'], sample)
        observed.append(candidates[-1].name)
        return native_predicate(sample, copy_id)
    p.protocol.validate_pre = verify_order
    try: root, result = run('positive-pre')
    finally: p.protocol.validate_pre = native_predicate
    assert len(observed) == 2 and result['envelope']['acceptedIndices'] == [0, 1]
    assert result['ack']['snapshotSHA256'] == hashlib.sha256(Path(result['artifact']['file']).read_bytes()).hexdigest()
    immutable = p.encoded(result['envelope'])
    outcome = p.publish(root, 'positive-pre', runner, result)
    assert outcome['publication']['status'] == 'SUPPORTED exclusive durable publication'
    assert p.encoded(result['envelope']) == immutable
    assert outcome['outcomeArtifact']['status'] == 'SUPPORTED exclusive durable evidence'
    checks.append({'case':'persist-before-predicate; two stable pre samples; actual durable host ack; frozen envelope unchanged', 'ackPublished':True})

    post_binding = dict(binding, phase='post-success', nonce=str(uuid.uuid4()).upper(), location='review-success')
    root, post = run('positive-post', samples['after'], post_binding, before)
    assert post['ack'] is not None
    final_binding = dict(post_binding, phase='final-parent', nonce=str(uuid.uuid4()).upper(), location='parent')
    root, final = run('positive-final', samples['terminal'], final_binding, before, samples['after'])
    assert final['ack'] is not None
    checks.append({'case':'historical synthetic post and final endpoint predicates integrated; no new native transaction', 'ackPrepared':True})

    reject('failed-sample-retained', change=lambda v:v['sample'].update(status='FAILED sample; no acknowledgement', errors=[{'synthetic':'failed capture'}]))
    reject('wrong-bound-path', change=lambda v:v['sample']['roots']['current'].update(path='/wrong/LumenData'))
    reject('unknown-namespace', change=lambda v:v['namespaceAfter']['namesAfter'].append('LumenData.unknown'))
    reject('namespace-root-metadata-mismatch', change=lambda v:v['namespaceBefore']['entries']['LumenData'].update(st_ino=1))
    reject('post-missing-baseline', source=samples['after'], expected=post_binding)
    reject('final-missing-prior-post', source=samples['terminal'], expected=final_binding, baseline=before)

    calls = [0]
    def unstable(v):
        calls[0] += 1
        row = v['sample']['roots']['standardPreferences']['children']['com.dbakp.lumen.plist']
        for key in ('identityObserved','identityBefore','identityAfter','identityNamedAfter'): row[key]['st_ino'] += (calls[0] % 2) * 10000000
    root, value = reject('valid-but-never-settles', change=unstable)
    assert len(value['envelope']['attempts']) == 6 and all(row['predicateValid'] for row in value['envelope']['attempts'])
    calls[0] = 0
    def settles(v):
        calls[0] += 1
        if calls[0] == 1: return
        row = v['sample']['roots']['standardPreferences']['children']['com.dbakp.lumen.plist']
        for key in ('identityObserved','identityBefore','identityAfter','identityNamedAfter'): row[key]['st_ino'] += 10000000
    root, value = run('valid-then-settles', change=settles)
    assert value['envelope']['acceptedIndices'] == [1, 2] and value['ack'] is not None
    checks.append({'case':'fully valid differing samples may settle; all three attempts retained', 'attempts':3})

    # A real write fails after a partial byte sequence. The failed attempt remains
    # on disk; the later failure envelope is still retained and no ack is prepared.
    write = os.write; calls = [0]
    def broken_write(fd, data):
        calls[0] += 1
        if calls[0] == 1: return write(fd, data[:7])
        if calls[0] == 2: raise OSError('Synthetic actual partial evidence write failure')
        return write(fd, data)
    os.write = broken_write
    try: root, value = reject('partial-evidence-write')
    finally: os.write = write
    assert (root / 'partial-evidence-write-attempt-0.json.gz').stat().st_size == 7

    root, value = run('tampered-retained-artifact')
    path = Path(value['envelope']['attempts'][0]['artifact']['file']); path.write_bytes(b'tampered')
    try: p.publish(root, 'tampered-retained-artifact', runner, value)
    except AssertionError: pass
    else: raise AssertionError('Tampered evidence permitted publication')
    assert not (root / 'tampered-retained-artifact-ack-intention.json').exists()
    checks.append({'case':'changed actual retained file rejects before native transport intention', 'ackPublished':False})

    root, value = run('tampered-ack-binding')
    value['ack']['copyID'] = 'healthRecoveryCopy-discovered-' + '0'*64
    try: p.publish(root, 'tampered-ack-binding', runner, value)
    except AssertionError: pass
    else: raise AssertionError('Changed acknowledgement binding permitted publication')
    checks.append({'case':'changed ack binding rejected before transport', 'ackPublished':False})

    root, value = run('stale-ack-window')
    clock = p.time.time
    p.time.time = lambda: value['envelope']['markerReadback']['finishedAt'] + 50
    try:
        try: p.publish(root, 'stale-ack-window', runner, value)
        except AssertionError: pass
        else: raise AssertionError('Late native acknowledgement allowed')
    finally: p.time.time = clock
    checks.append({'case':'expired conservative native ack window rejects before transport', 'ackPublished':False})

    for label, mutate in (
        ('metadata-float-readback-bytes', lambda a:a['readback'].update(bytes=float(a['readback']['bytes']))),
        ('metadata-bool-link-count', lambda a:a['readback']['identityNamedAfter'].update(st_nlink=True)),
        ('metadata-float-expected-bytes', lambda a:a.update(expectedBytes=float(a['expectedBytes']))),
        ('metadata-float-mode', lambda a:a['readback']['identityNamedAfter'].update(st_mode=float(a['readback']['identityNamedAfter']['st_mode'])))):
        root, value = run(label)
        original_envelope = p.encoded(value['envelope'])
        mutate(value['artifact'])
        assert p.encoded(value['envelope']) == original_envelope
        try: p.publish(root, label, runner, value)
        except AssertionError: pass
        else: raise AssertionError('Recorded artifact metadata type alias permitted transport')
        assert not (root / (label + '-ack-intention.json')).exists()
        checks.append({'case':label + ' rejects in actual publish caller before intention', 'ackPublished':False})

    for delayed_stage in ('intention','staging-fsync'):
        label = 'deadline-after-' + delayed_stage
        expected = dict(binding, runID=str(uuid.uuid4()).upper())
        root, value = run(label, expected=expected)
        real_clock = p.time.time; real_retain = p.retain; real_fsync = os.fsync
        future = real_clock() + 50; fsync_calls = [0]
        def delayed_retain(*args):
            saved = real_retain(*args)
            if args[1].endswith('-ack-intention.json'): p.time.time = lambda: future
            return saved
        def delayed_fsync(fd):
            answer = real_fsync(fd); fsync_calls[0] += 1
            # Intention retention performs file+directory fsync first; the
            # transport's staging-file fsync is the third blocking call.
            if fsync_calls[0] == 3: p.time.time = lambda: future
            return answer
        if delayed_stage == 'intention': p.retain = delayed_retain
        else: os.fsync = delayed_fsync
        try: outcome = p.publish(root, label, runner, value)
        finally:
            p.retain = real_retain; os.fsync = real_fsync; p.time.time = real_clock
        publication = outcome['publication']
        assert publication['published'] is False and publication['mayHaveBeenObserved'] is False
        assert publication['status'] == 'FAILED publication'
        assert publication['temporaryReadback']['status'] == 'SUPPORTED stable transport file'
        assert publication['readback']['status'] == 'ABSENT anchored leaf'
        assert (root / (label + '-ack-intention.json')).exists()
        checks.append({'case':label + ' rejects immediately before rename and retains full staging/intention', 'ackPublished':False})

    # Complete small fixture artifacts survive cleanup inside this compact raw log.
    for path in sorted(area.rglob('*')):
        if path.is_file():
            data = path.read_bytes()
            raw_files[str(path.relative_to(area))] = p.transport.blob(data)

assert helper.read_bytes() == original
raw = {'scope':'Historical synthetic sample replay plus actual host evidence/transport files only; no native/backend acceptance',
       'historicalInput': {'file':historical.name, 'sha256':hashlib.sha256(historical.read_bytes()).hexdigest()},
       'results':results, 'syntheticFiles':raw_files}
raw_bytes = gzip.compress(p.encoded(raw), mtime=0)
raw_output.write_bytes(raw_bytes)
report = {'status':'PASS scoped phase coordination controls', 'helperBytes':len(original),
          'helperSHA256':hashlib.sha256(original).hexdigest(), 'sourceBeforeAfterExact':True,
          'checks':checks, 'checkCount':len(checks), 'raw':{'file':raw_output.name, 'bytes':len(raw_bytes), 'sha256':hashlib.sha256(raw_bytes).hexdigest()},
          'temporarySyntheticFixturesRemoved':True, 'scope':raw['scope'],
          'remaining':'Actual process/container/source/proof/trace provenance controller, complete producer/independent checker/finalizer, freeze/build/native audit remain pending.',
          'checkedAt':time.time()}
output.write_text(json.dumps(report,indent=2)+'\n')
print(len(checks),'phase coordinator controls passed; no simulator operation')
