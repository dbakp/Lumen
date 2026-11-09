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
import plistlib
import tempfile
import time
import uuid

B = Path(__file__).resolve().parent
output = B / 'source261-pending-phase-controls-r3.json'
raw_output = B / 'source261-pending-phase-controls-r3-raw.json.gz'
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

    post_binding = dict(binding, phase='post-success', nonce=str(uuid.uuid4()).upper(), location='review-success')
    pre_parsed=p.protocol.validate_sample(before)
    old_shared=p.protocol.preferences(pre_parsed,'groupPreferences')
    def replace_bytes(sample,label,path,data):
        row=sample['roots'][label]
        for part in path.split('/'):row=row['children'][part]
        delta=len(data)-row['raw']['bytes'];row['raw']=p.transport.blob(data);sample['totalReadBytes']+=delta
        for key in ('identityObserved','identityBefore','identityAfter','identityNamedAfter'):row[key]['st_size']=len(data)
    def prefs(v,old_issue=True,old_packet=True,extra=None):
        sample=v['sample'];row=sample['roots']['groupPreferences']['children']['group.com.dbakp.lumen.plist']
        shared=plistlib.loads(p.protocol.raw(row))
        if old_issue:shared['health.localStorageIssue']=old_shared['health.localStorageIssue']
        if old_packet:shared['widget.evidence.v1']=old_shared['widget.evidence.v1']
        if extra:extra(shared)
        replace_bytes(sample,'groupPreferences','group.com.dbakp.lumen.plist',plistlib.dumps(shared,fmt=plistlib.FMT_BINARY))
    def retired(v,kind='good'):
        name='LumenData.retired-'+str(uuid.uuid4()).upper()
        if kind=='restore':name=name.replace('.retired-','.restore-')
        if kind=='malformed':name='LumenData.retired-not-a-uuid'
        facts=copy.deepcopy(before['roots']['current']['identityBefore'])
        if kind=='wrong-inode':facts['st_ino']+=10000000
        for key in ('namespaceBefore','namespaceAfter'):
            inv=v[key];inv['entries'][name]=facts
            inv['namesBefore']=inv['namesAfter']=sorted(inv['entries'])
            for peer in ('inventoryBefore','inventoryAfter'):
                inv[peer]['names']=inv['namesBefore'];inv[peer]['scannedAtLeast']=len(inv['entries'])
    def post_run(label,change,count=6):
        return run(label,samples['after'],post_binding,before,change=change,count=count)
    def post_reject(label,change,count=6):
        return reject(label,source=samples['after'],expected=post_binding,baseline=before,change=change,count=count)

    for mode in ('both','only-storage-issue','only-widget-packet'):
        calls=[0]
        def settles(v):
            calls[0]+=1
            if calls[0]<=3:prefs(v,old_issue=mode!='only-widget-packet',old_packet=mode!='only-storage-issue')
        root,value=post_run('pending-'+mode,settles)
        assert value['ack'] is not None and value['envelope']['acceptedIndices']==[3,4]
        assert all(row['predicateValid'] is False and row['observation']['observation']=='OBSERVED_PENDING' and 'fingerprint' not in row for row in value['envelope']['attempts'][:3])
        checks.append({'case':'known old/new combination '+mode+' waits without acknowledging pending; two final-valid stable samples', 'attempts':5,'ackPrepared':True})

    calls=[0]
    def valid_pending_valid(v):
        calls[0]+=1
        if calls[0]==2:prefs(v)
    root,value=post_run('pending-resets-valid-stability',valid_pending_valid)
    assert value['ack'] is not None and value['envelope']['acceptedIndices']==[2,3]
    checks.append({'case':'valid then pending resets consecutive-stability requirement', 'attempts':4,'ackPrepared':True})

    calls=[0];began=time.monotonic()
    def multi_second(v):
        calls[0]+=1
        if calls[0]<=3:
            time.sleep(1.1);prefs(v)
    root,value=post_run('actual-multi-second-pending-wait',multi_second)
    elapsed=time.monotonic()-began
    assert elapsed>=3.3 and value['ack'] is not None and value['envelope']['acceptedIndices']==[3,4]
    checks.append({'case':'actual unshortened multi-second coordinator wait over historical synthetic prefs; not native defaults timing', 'elapsedSeconds':elapsed,'ackPrepared':True})

    root,value=post_reject('pending-through-bound',lambda v:prefs(v),count=8)
    assert len(value['envelope']['attempts'])==8 and all(row['predicateValid'] is False for row in value['envelope']['attempts'])
    post_reject('pending-with-unexpected-shared-key',lambda v:prefs(v,extra=lambda d:d.update(unexpected=True)))
    def changed_water(v):
        prefs(v);replace_bytes(v['sample'],'current','water.json',b'changed protected leaf')
    post_reject('pending-with-changed-protected-water',changed_water)
    post_reject('pending-with-invented-widget-zero',lambda v:prefs(v,old_packet=False,extra=lambda d:d.update({'widget.evidence.v1':p.encoded(dict(p.protocol.packet(d['widget.evidence.v1']),values={'calories':0}))})))
    def equal_packet_bytes_changed(v):
        prefs(v,old_packet=False)
        def altered(d):d['widget.evidence.v1']=json.dumps(json.loads(old_shared['widget.evidence.v1']),indent=2).encode()
        prefs(v,old_packet=False,extra=altered)
    post_reject('changed-packet-bytes-without-advanced-capture',equal_packet_bytes_changed)

    def stale_advanced_packet(v):
        def changed(d):
            packet=p.protocol.packet(d['widget.evidence.v1'])
            # This advances the stale old packet but remains before the actual
            # pre-action boundary; source-declared refresh must reject it.
            packet['capturedAt']=(before['startedAt']-10)-978307200
            d['widget.evidence.v1']=p.encoded(packet)
        # Make the synthetic old baseline packet older so the candidate advances
        # it; rejection must be from the pre-action lower bound, not monotonicity.
        prefs(v,old_issue=False,old_packet=False,extra=changed)
    # Historical source packet can already be close to its old baseline. Use a
    # fresh baseline time for these direct predicate boundary controls only.
    boundary_before=copy.deepcopy(before);boundary_before['startedAt']=time.time();boundary_before['finishedAt']=time.time()
    a=attempt(samples['after'])
    def boundary_packet(at,packet_time):
        row=at['sample']['roots']['groupPreferences']['children']['group.com.dbakp.lumen.plist']
        shared=plistlib.loads(p.protocol.raw(row));packet=p.protocol.packet(shared['widget.evidence.v1'])
        packet['capturedAt']=packet_time-978307200
        shared['widget.evidence.v1']=p.encoded(packet)
        replace_bytes(at['sample'],'groupPreferences','group.com.dbakp.lumen.plist',plistlib.dumps(shared,fmt=plistlib.FMT_BINARY))
        # Coherent fixture receipt/incident times inside the new synthetic bound.
        for path in p.protocol.validate_sample(at['sample'])['files']['current']:
            if path.startswith('.health-recovery-history/') or (path.startswith('.health-recovery/') and not '/discovered-' in path and path.endswith('/manifest.json')):
                entry=at['sample']['roots']['current']
                for part in path.split('/'):entry=entry['children'][part]
                value=json.loads(p.protocol.raw(entry));key='recoveredAt' if 'recoveredAt' in value else 'createdAt'
                import datetime
                value[key]=datetime.datetime.fromtimestamp(boundary_before['startedAt'],datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
                replace_bytes(at['sample'],'current',path,p.encoded(value))
    boundary_packet(a,boundary_before['startedAt']-10)
    try:p.protocol.validate_post(boundary_before,a['sample'],copy_id,allow_pending_refresh=True)
    except AssertionError as error:assert 'predates pre-action boundary' in str(error)
    else:raise AssertionError('Advanced but pre-action packet accepted')
    checks.append({'case':'packet advances stale baseline capture but predates actual pre-action boundary; explicit lower-bound rejection','ackPrepared':False})
    boundary_packet(a,boundary_before['startedAt']-1)
    p.protocol.validate_post(boundary_before,a['sample'],copy_id,allow_pending_refresh=True)
    checks.append({'case':'explicit one-second clock tolerance lower boundary accepted for otherwise valid synthetic endpoint','accepted':True})
    boundary_packet(a,boundary_before['startedAt']-1.01)
    try:p.protocol.validate_post(boundary_before,a['sample'],copy_id,allow_pending_refresh=True)
    except AssertionError as error:assert 'predates pre-action boundary' in str(error)
    else:raise AssertionError('Outside lower clock tolerance accepted')
    checks.append({'case':'outside one-second lower clock tolerance rejected','accepted':False})

    calls=[0]
    def retirement_settles(v):
        calls[0]+=1
        if calls[0]<=2:retired(v)
    root,value=post_run('baseline-bound-retired-root-settles',retirement_settles)
    assert value['ack'] is not None and value['envelope']['acceptedIndices']==[2,3]
    assert all(row['predicateValid'] is False and len(row['pendingRetiredNames'])==1 for row in value['envelope']['attempts'][:2])
    checks.append({'case':'only exact baseline old-root device/inode/mode and UUID retired leaf may wait; gone twice before ack', 'ackPrepared':True})
    for kind in ('restore','malformed','wrong-inode'):
        post_reject('unexpected-retired-'+kind,lambda v,kind=kind:retired(v,kind))
    def multiple_retired(v):retired(v);retired(v)
    post_reject('multiple-retired-root-names',multiple_retired)
    root,value=post_reject('retired-through-bound',lambda v:retired(v),count=8)
    assert len(value['envelope']['attempts'])==8
    final_binding=dict(post_binding,phase='final-parent',nonce=str(uuid.uuid4()).upper(),location='parent')
    root,value=reject('final-parent-cannot-regress-prefs',source=samples['terminal'],expected=final_binding,baseline=before,prior_post=samples['after'],change=lambda v:prefs(v))
    assert len(value['envelope']['attempts'])==1

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
          'remaining':'Actual provenance controller, raw marker durability and prior-phase artifact binding/independent replay, producer/checker/finalizer, freeze/build/native audit remain pending. Unsafe or within-sample mutation still fails immediately; no arbitrary-error retry.',
          'checkedAt':time.time()}
output.write_text(json.dumps(report,indent=2)+'\n')
print(len(checks),'phase coordinator controls passed; no simulator operation')
