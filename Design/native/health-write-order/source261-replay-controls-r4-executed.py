"""Actual durable host phase files and publication; historical synthetic data only."""
from pathlib import Path
import copy
import datetime
import gzip
import hashlib
import importlib.util
import json
import os
import plistlib
import tempfile
import time
import uuid

B = Path(__file__).resolve().parent
output = B / 'source261-replay-controls-r4.json'
raw_output = B / 'source261-replay-controls-r4-raw.json.gz'
assert not output.exists() and not raw_output.exists()
helper = B / 'retained-backend-replay-r1.py'; original = helper.read_bytes()
spec = importlib.util.spec_from_file_location('replay', helper)
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r); p = r.p
history = B / 'source261-backend-protocol-controls-r2-raw.json.gz'
data = json.loads(gzip.decompress(history.read_bytes()))['samples']
before = copy.deepcopy(data['before']); post = copy.deepcopy(data['after'])
roots = {key: row['path'] for key, row in before['roots'].items()}
parent = str(Path(roots['current']).parent)
roots['current'] = str(Path(parent) / 'LumenData')
roots['previous'] = str(Path(parent) / 'LumenData.previous')
for sample in (before, post):
    for key, path in roots.items(): sample['roots'][key]['path'] = path
copy_id = 'healthRecoveryCopy-' + next(n for n in before['roots']['current']['children']['.health-recovery']['children'] if n.startswith('discovered-'))
initial_shared = p.protocol.preferences(p.protocol.validate_sample(before), 'groupPreferences')
context = {'scope':'synthetic host replay only; no actual native provenance', 'source':'NOT_FROZEN_SOURCE261'}
base_binding = {'schema':'Lumen-retained-backend-ack-v1', 'runID':str(uuid.uuid4()).upper(),
                'runnerPID':str(os.getpid()), 'case':'retained-meals-backend', 'copyID':copy_id,
                'sessionID':str(uuid.uuid4()).upper(), 'captureID':str(uuid.uuid4()).upper(), 'selected':''}
checks = []; outcomes = []; records = []; bindings = []; files = {}; samples = []; initial_files = {}; negative_cases = {}


def row(sample, label, path):
    value = sample['roots'][label]
    for part in path.split('/'): value = value['children'][part]
    return value


def replace(sample, label, path, raw):
    value = row(sample, label, path)
    sample['totalReadBytes'] += len(raw) - value['raw']['bytes']
    value['raw'] = p.transport.blob(raw)
    for key in ('identityObserved','identityBefore','identityAfter','identityNamedAfter'): value[key]['st_size'] = len(raw)


def captured(template, pending=False):
    started = time.time(); value = copy.deepcopy(template)
    if pending:
        name = 'group.com.dbakp.lumen.plist'
        shared = plistlib.loads(p.protocol.raw(row(value,'groupPreferences',name)))
        for key in ('health.localStorageIssue','widget.evidence.v1'): shared[key] = initial_shared[key]
        replace(value,'groupPreferences',name,plistlib.dumps(shared,fmt=plistlib.FMT_BINARY))
    value['startedAt'] = time.time(); value['finishedAt'] = time.time()
    names = ['LumenData'] + ([] if value['roots']['previous']['absent'] else ['LumenData.previous'])
    entries = {n:copy.deepcopy(value['roots']['current' if n=='LumenData' else 'previous']['identityBefore']) for n in names}
    inventory = {'status':'SUPPORTED bounded task namespace inventory', 'path':parent, 'entries':entries,
                 'errors':[], 'namesBefore':sorted(names), 'namesAfter':sorted(names),
                 'inventoryBefore':{'names':sorted(names),'overflow':False,'scannedAtLeast':len(names)},
                 'inventoryAfter':{'names':sorted(names),'overflow':False,'scannedAtLeast':len(names)}}
    first = dict(inventory, startedAt=started, finishedAt=value['startedAt'])
    last = dict(inventory, startedAt=value['finishedAt'], finishedAt=time.time())
    return {'namespaceBefore':copy.deepcopy(first),'sample':value,'namespaceAfter':copy.deepcopy(last)}


def refreshed(template):
    result = copy.deepcopy(template)
    now = time.time(); iso = datetime.datetime.fromtimestamp(now,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    for name in p.protocol.validate_sample(result)['files']['current']:
        if name.startswith('.health-recovery-history/') or (name.startswith('.health-recovery/') and '/discovered-' not in name and name.endswith('/manifest.json')):
            value = json.loads(p.protocol.raw(row(result,'current',name)))
            key = 'recoveredAt' if 'recoveredAt' in value else 'createdAt'; value[key] = iso
            replace(result,'current',name,p.encoded(value))
    name = 'group.com.dbakp.lumen.plist'
    shared = plistlib.loads(p.protocol.raw(row(result,'groupPreferences',name)))
    packet = p.protocol.packet(shared['widget.evidence.v1']); packet['capturedAt'] = now - 978307200
    shared['widget.evidence.v1'] = p.encoded(packet)
    replace(result,'groupPreferences',name,plistlib.dumps(shared,fmt=plistlib.FMT_BINARY))
    return result


def current_artifact(path):
    value = p.transport.read(path.parent,path.name,limit=1024**2)
    assert value['status'] == 'SUPPORTED stable transport file'
    raw = value['raw']
    return {'file':str(path),'expectedBytes':raw['bytes'],'expectedSHA256':raw['sha256'],
            'status':'SUPPORTED exclusive durable evidence','errors':[],
            'readback':{'bytes':raw['bytes'],'sha256':raw['sha256'],
                        'identityBefore':value['identityBefore'],'identityAfter':value['identityAfter'],
                        'identityNamedAfter':value['identityNamedAfter']}}


with tempfile.TemporaryDirectory(prefix='lumen261-replay-') as temporary:
    root = Path(temporary).resolve(); runner = root / 'runner'; runner.mkdir()
    for index, phase in enumerate(p.PHASES):
        if index == 1: post = refreshed(post)
        label = 'phase-' + str(index)
        binding = dict(base_binding,phase=phase,nonce=str(uuid.uuid4()).upper(),location=('review-ready','review-success','parent')[index])
        marker = {'schema':'Lumen-retained-backend-marker-v1','binding':binding,
                  'uiState':{'session':binding['sessionID'],'capture':binding['captureID'],'phase':'ready','selected':''},
                  'image':{'attachmentName':('retained-backend-fresh','retained-backend-recovered','retained-backend-final-parent')[index],
                           'bytes':1,'sha256':p.sha(b'synthetic-only-image-identity')},'at':time.time()}
        marker_path = runner / (label + '-marker.json'); marker_path.write_bytes(p.encoded(marker))
        marker_readback = p.transport.read(runner,marker_path.name)
        # Marker observation must exist durably before phase() may parse it.
        marker_record = r.retain_marker(root,label,marker_readback)
        bound_context = r.context_for(context,records,bindings,marker_record)
        calls = [0]
        def acquire(unused_roots, unused_parent):
            calls[0] += 1
            return captured(before if index == 0 else post, pending=index == 1 and calls[0] <= 2)
        result = p.phase(root,label,marker_readback,binding,bound_context,roots,parent,
                         baseline=samples[0] if index else None, prior_post=samples[1] if index==2 else None,
                         acquire=acquire,max_attempts=8,interval=0)
        assert result['ack'] is not None, result['envelope']['errors']
        records.append(r.record_for(label,result)); bindings.append(binding)
        replayed = r.replay(root,records,bindings,context,roots)
        samples = replayed['samples']
        outcomes.append(r.publish_checked(root,label,runner,records,bindings,context,roots,result))
        assert outcomes[-1]['publicationOutcome']['publication']['status'] == 'SUPPORTED exclusive durable publication'
    assert replayed['phases'][1]['attempts'] == 4 and replayed['phases'][1]['acceptedIndices'] == [2,3]
    checks.append({'case':'three linked immutable phases and raw marker observations independently replay; pending cannot count toward acceptance; actual host ACK publication', 'accepted':True})
    for path in sorted(root.rglob('*')):
        if path.is_file():initial_files[str(path.relative_to(root))]=p.transport.blob(path.read_bytes())
    result['acceptedSample'] = {'forged':'mutable return is not authoritative'}
    assert len(r.replay(root,records,bindings,context,roots)['samples'][-1]['roots']) == 4
    checks.append({'case':'returned mutable acceptedSample replaced; independent replay still reconstructs retained sample', 'accepted':True})

    # Rewrite only known synthetic control files with coherent hashes/stat facts
    # to ensure rejection depends on semantics rather than a stale SHA alone.
    def rewrite(path, value):
        raw = p.encoded(value); packed = gzip.compress(raw,mtime=0)
        with path.open('wb') as stream: stream.write(packed); stream.flush(); os.fsync(stream.fileno())
        return current_artifact(path),len(raw),p.sha(raw)
    def reject_envelope(label, change, phase_index=2):
        record = records[phase_index]; path = Path(record['artifact']['file'])
        original_value = r.load(root,record['artifact'],record['decodedBytes'],record['decodedSHA256'])
        changed = copy.deepcopy(original_value); change(changed)
        artifact,count,digest = rewrite(path,changed)
        candidates = copy.deepcopy(records)
        candidates[phase_index].update(artifact=artifact,decodedBytes=count,decodedSHA256=digest)
        negative_cases[label]={'records':copy.deepcopy(candidates),'changedPhaseBytes':p.transport.blob(path.read_bytes())}
        invoked = []; actual_write = p.transport.write_once
        def prohibited(*args): invoked.append(True); raise AssertionError('Native transport must not be reached')
        p.transport.write_once = prohibited
        try:
            try: r.replay(root,candidates,bindings,context,roots)
            except (AssertionError,KeyError,ValueError,TypeError) as error: negative_cases[label]['replayError']=repr(error)
            else: raise AssertionError('Coherently altered envelope accepted: ' + label)
            try: r.publish_checked(root,records[-1]['label'],runner,candidates,bindings,context,roots,result)
            except (AssertionError,KeyError,ValueError,TypeError) as error: negative_cases[label]['callerError']=repr(error)
            else: raise AssertionError('Invalid replay reached successful publication caller: ' + label)
            assert invoked == []
        finally:
            p.transport.write_once = actual_write
            artifact,count,digest = rewrite(path,original_value)
            records[phase_index].update(artifact=artifact,decodedBytes=count,decodedSHA256=digest)
        checks.append({'case':label,'accepted':False,'actualPublishCallerRejectedBeforeTransport':True})
    reject_envelope('Boolean alias in accepted indices',lambda v:v.update(acceptedIndices=[False,True]))
    reject_envelope('integer alias in predicate-valid flag',lambda v:v['attempts'][0].update(predicateValid=1))
    reject_envelope('forged fingerprint despite actual complete sample',lambda v:v['attempts'][0].update(fingerprint='f'*64))
    reject_envelope('wrong prior snapshot digest despite coherent new current envelope hash',lambda v:v['context']['priorPhases'][0].update(snapshotSHA256='f'*64))
    reject_envelope('wrong fixed verification context',lambda v:v['context']['verificationContext'].update(source='different-source'))
    reject_envelope('wrong raw marker decoded digest',lambda v:v['context']['markerObservation'].update(decodedSHA256='f'*64))
    reject_envelope('pending old preferences falsely labelled valid',lambda v:v['attempts'][0].update(predicateValid=True),phase_index=1)
    wrong = copy.deepcopy(records); wrong[0]['decodedBytes'] = True
    try: r.replay(root,wrong,bindings,context,roots)
    except AssertionError: pass
    else: raise AssertionError('Boolean decoded count accepted')
    checks.append({'case':'Boolean decoded byte count rejects before read/decompression','accepted':False})
    # Coherent +41/+42 acquisitions, namespaces, samples and +44 completion.
    # Unlike a changed lone timestamp, every ordering field agrees; only the
    # producer's explicit +40 acquisition-start bound excludes this candidate.
    record=records[-1];path=Path(record['artifact']['file'])
    envelope=r.load(root,record['artifact'],record['decodedBytes'],record['decodedSHA256'])
    native_at=p.unique_json(p.protocol.raw(envelope['markerReadback']))['at']
    originals=[];changed_attempts=[]
    for index,item in enumerate(envelope['attempts']):
        attempt_path=Path(item['artifact']['file'])
        old_attempt=r.load(root,item['artifact'],item['decodedBytes'],item['decodedSHA256'])
        originals.append((attempt_path,old_attempt))
        late=copy.deepcopy(old_attempt);checked=native_at+41+index;late['acquisitionCheckedAt']=checked
        captured=late['capture']
        captured['namespaceBefore'].update(startedAt=checked+0.01,finishedAt=checked+0.02)
        captured['sample'].update(startedAt=checked+0.03,finishedAt=checked+0.04)
        captured['namespaceAfter'].update(startedAt=checked+0.05,finishedAt=checked+0.06)
        artifact,count,digest=rewrite(attempt_path,late);item.update(artifact=artifact,decodedBytes=count,decodedSHA256=digest)
        changed_attempts.append(p.transport.blob(attempt_path.read_bytes()))
    envelope['finishedAt']=native_at+44
    artifact,count,digest=rewrite(path,envelope)
    candidates=copy.deepcopy(records);candidates[-1].update(artifact=artifact,decodedBytes=count,decodedSHA256=digest)
    negative_cases['late-acquisition']={'records':copy.deepcopy(candidates),'changedPhaseBytes':p.transport.blob(path.read_bytes()),'changedAttempts':changed_attempts}
    try:r.replay(root,candidates,bindings,context,roots)
    except AssertionError as error:
        assert 'Acquisition guard outside its native window' in str(error)
        negative_cases['late-acquisition']['replayError']=repr(error)
    else:raise AssertionError('Late acquisitions accepted inside completion window')
    checks.append({'case':'coherent +41/+42 acquisition/namespace/sample times reject despite +44 completion and valid gzip/hash/stat facts','accepted':False})
    for item,(attempt_path,old_attempt) in zip(envelope['attempts'],originals):
        artifact,count,digest=rewrite(attempt_path,old_attempt);item.update(artifact=artifact,decodedBytes=count,decodedSHA256=digest)
    envelope['finishedAt']=result['envelope']['finishedAt']
    artifact,count,digest=rewrite(path,envelope);records[-1].update(artifact=artifact,decodedBytes=count,decodedSHA256=digest)
    # All restored envelopes still independently pass after the negative cases.
    r.replay(root,records,bindings,context,roots)
    checks.append({'case':'all restored actual host envelopes replay successfully after negative mutations','accepted':True})
    for path in sorted(root.rglob('*')):
        if path.is_file(): files[str(path.relative_to(root))] = p.transport.blob(path.read_bytes())

assert helper.read_bytes() == original
raw = {'scope':'Actual host evidence/ACK files and historical synthetic data replay only; no native transaction or source readiness',
       'historicalSource':{'file':history.name,'sha256':hashlib.sha256(history.read_bytes()).hexdigest()},
       'records':records,'bindings':bindings,'context':context,'roots':roots,'checks':checks,'publicationOutcomes':outcomes,'initialFiles':initial_files,'negativeCases':negative_cases,'files':files}
packed = gzip.compress(p.encoded(raw),mtime=0); raw_output.write_bytes(packed)
dependencies = []
for name in ('retained-backend-phase-r2.py','retained-backend-protocol-r3.py','retained-backend-transport-r3.py'):
    data = (B/name).read_bytes(); dependencies.append({'file':name,'bytes':len(data),'sha256':p.sha(data)})
report = {'status':'PASS scoped independent phase replay controls','helperBytes':len(original),'helperSHA256':p.sha(original),
          'sourceBeforeAfterExact':True,'dependencies':dependencies,'checkCount':len(checks),'checks':checks,
          'raw':{'file':raw_output.name,'bytes':len(packed),'sha256':p.sha(packed)},'temporarySyntheticFixturesRemoved':True,
          'scope':raw['scope'],'remaining':'Actual source/proof/process/container/provider/trace discovery, producer, native helper/ACK/original attachment linkage, mandatory full checker/finalizer and new test build/native run remain pending.','checkedAt':time.time()}
output.write_text(json.dumps(report,indent=2)+'\n')
print(len(checks),'independent replay controls passed; no simulator action')
