"""Causal phase coordination only; callers must first verify native/source context.

Every attempt is retained before interpretation. Only two consecutive complete,
final-valid, identical samples permit acknowledgement. Declared pending refresh
or metadata-bound retired-root cleanup may retry; unsafe/unknown failures cannot. This module does not discover processes or establish provenance.
"""
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import time
import traceback

B = Path(__file__).resolve().parent


def module(name):
    spec = importlib.util.spec_from_file_location(name, B / name)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


transport = module('retained-backend-transport-r3.py')
protocol = module('retained-backend-protocol-r3.py')
sampler = module('retained-backend-snapshot-r2.py')
namespace = module('retained-backend-inventory-r2.py')
PHASES = ('pre-recover', 'post-success', 'final-parent')


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_json(data):
    def pairs(rows):
        result = {}
        for key, value in rows:
            assert key not in result, 'Duplicate JSON key'
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def retain(root, name, data):
    """Exclusive host evidence file; failed/partial files are deliberately kept.

    A host artifact becomes usable only after complete fsync and stable readback.
    Unlike native transport, its name is never a signal consumed by the app.
    """
    transport._name(name)
    assert type(data) is bytes and 0 < len(data) <= 128 * 1024**2
    result = {'file': str(Path(root) / name), 'expectedBytes': len(data),
              'expectedSHA256': sha(data), 'status': 'FAILED evidence retention', 'errors': []}
    opened = []; links = []; fd = None
    try:
        opened, links = transport._anchors(root)
        parent = opened[-1]
        fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=parent)
        written = 0
        while written < len(data):
            amount = os.write(fd, data[written:]); assert amount > 0
            written += amount
        os.fsync(fd); os.fsync(parent)
        before = os.fstat(fd)
        assert stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and before.st_size == len(data)
        os.lseek(fd, 0, os.SEEK_SET)
        count = 0; digest = hashlib.sha256()
        while count <= len(data):
            chunk = os.read(fd, min(65536, len(data) + 1 - count))
            if not chunk: break
            count += len(chunk); digest.update(chunk)
        after = os.fstat(fd); named = os.stat(name, dir_fd=parent, follow_symlinks=False)
        result['readback'] = {'bytes': count, 'sha256': digest.hexdigest(),
                              'identityBefore': transport.facts(before),
                              'identityAfter': transport.facts(after),
                              'identityNamedAfter': transport.facts(named)}
        assert count == len(data) and digest.hexdigest() == sha(data)
        assert transport.facts(before) == transport.facts(after) == transport.facts(named)
    except BaseException:
        result['errors'].append({'stage': 'retention', 'error': traceback.format_exc()})
    finally:
        if fd is not None:
            try: os.close(fd)
            except BaseException: result['errors'].append({'stage': 'close', 'error': traceback.format_exc()})
        transport._finish(opened, links, result)
    if not result['errors']: result['status'] = 'SUPPORTED exclusive durable evidence'
    return result


def marker_value(readback, expected):
    assert readback['status'] == 'SUPPORTED stable transport file' and readback['errors'] == []
    data = protocol.raw(readback)
    value = unique_json(data)
    assert set(value) == {'schema', 'binding', 'uiState', 'image', 'at'}
    assert value['schema'] == 'Lumen-retained-backend-marker-v1'
    binding = value['binding']
    assert set(binding) == {'schema','runID','runnerPID','case','phase','nonce','copyID',
                            'sessionID','captureID','selected','location'}
    assert all(type(v) is str for v in binding.values()) and protocol.same(binding, expected)
    assert binding['schema'] == 'Lumen-retained-backend-ack-v1'
    for key in ('runID','nonce','sessionID','captureID'): protocol.canonical_uuid(binding[key])
    assert re.fullmatch(r'[1-9][0-9]{0,9}', binding['runnerPID'])
    assert binding['case'] == 'retained-meals-backend' and binding['phase'] in PHASES
    assert binding['selected'] == ''
    index = PHASES.index(binding['phase'])
    assert binding['location'] == ('review-ready','review-success','parent')[index]
    assert re.fullmatch(r'healthRecoveryCopy-discovered-[0-9a-f]{64}', binding['copyID'])
    assert protocol.same(value['uiState'], {'session': binding['sessionID'], 'capture': binding['captureID'],
                                         'phase': 'ready', 'selected': ''})
    image = value['image']
    assert set(image) == {'attachmentName','bytes','sha256'}
    assert image['attachmentName'] == ('retained-backend-fresh','retained-backend-recovered',
                                       'retained-backend-final-parent')[index]
    protocol.integer(image['bytes'], 1)
    assert type(image['sha256']) is str and re.fullmatch(r'[0-9a-f]{64}', image['sha256'])
    protocol.number(value['at']); assert 0 < value['at'] <= time.time() + 1
    return value, sha(data)


def inventory_matches(inventory, sample, parent, baseline=None):
    assert inventory['status'] == 'SUPPORTED bounded task namespace inventory'
    assert inventory['errors'] == [] and inventory['path'] == str(parent)
    expected = {'LumenData'}
    if sample['roots']['previous']['absent'] is False: expected.add('LumenData.previous')
    names=inventory['namesBefore']
    assert type(names) is list and all(type(name) is str for name in names)
    assert names == sorted(set(names)) == inventory['namesAfter']
    assert set(inventory['entries']) == set(names) and expected.issubset(names)
    retired=set(names)-expected
    assert len(retired)<=1
    if retired:
        assert baseline is not None and sample['roots']['previous']['absent'] is True
        name=next(iter(retired));assert name.startswith('LumenData.retired-')
        protocol.canonical_uuid(name[len('LumenData.retired-'):])
        facts=inventory['entries'][name];assert set(facts)==protocol.FIELDS
        for key,value in facts.items():protocol.integer(value,0 if key in ('st_size','st_mtime_ns','st_ctime_ns') else 1)
        original=baseline['roots']['current']['identityBefore']
        assert all(protocol.same(facts[key],original[key]) for key in ('st_dev','st_ino','st_mode'))
        assert stat.S_ISDIR(facts['st_mode'])
    for name, label in (('LumenData','current'), ('LumenData.previous','previous')):
        if name in expected:
            assert protocol.same(inventory['entries'][name], sample['roots'][label]['identityBefore'])
    for key in ('inventoryBefore', 'inventoryAfter'):
        row = inventory[key]
        assert row['overflow'] is False and row['names'] == names
        assert type(row['scannedAtLeast']) is int and len(names) <= row['scannedAtLeast'] <= 2048
    return retired



def capture(roots, parent):
    # Always attempt the later inventory even when the sampler reports failure.
    before = namespace.inventory(parent)
    sample = sampler.capture(roots)
    after = namespace.inventory(parent)
    return {'namespaceBefore': before, 'sample': sample, 'namespaceAfter': after}


def phase(root, label, marker, expected, context, roots, parent, baseline=None, prior_post=None,
          acquire=capture, max_attempts=48, interval=0.5):
    """Retain a phase and prepare ack bytes; never publish them here.

    Context is preserved verbatim; upstream provenance verification is mandatory.
    Unsafe, malformed and unknown changes fail immediately. Only explicitly
    validated pending refresh/retirement or final-valid differing samples retry.
    Pending samples reset stability and can never permit acknowledgement.
    """
    transport._name(label)
    assert type(max_attempts) is int and 2 <= max_attempts <= 48
    assert type(interval) in (int, float) and 0 <= interval <= 0.5
    envelope = {'schema': 'Lumen-retained-backend-phase-v2', 'startedAt': time.time(),
                'markerReadback': marker, 'context': context, 'expectedBinding': expected,
                'roots': roots, 'namespaceParent': str(parent), 'attempts': [],
                'status': 'FAILED phase; no acknowledgement', 'errors': []}
    accepted = None; ack = None
    try:
        value, marker_sha = marker_value(marker, expected)
        assert type(context) is dict and context
        # The caller must supply exact paths derived from actual bound queries.
        assert set(roots) == {'current','previous','standardPreferences','groupPreferences'}
        assert roots['current'] == str(Path(parent) / 'LumenData')
        assert roots['previous'] == str(Path(parent) / 'LumenData.previous')
        current_phase = expected['phase']
        assert (baseline is None) == (current_phase == 'pre-recover')
        assert (prior_post is not None) == (current_phase == 'final-parent')
        previous_fingerprint = None
        for index in range(max_attempts):
            acquisition_checked_at=time.time()
            assert acquisition_checked_at < value['at'] + 40, 'Bounded capture window expired'
            attempt={'acquisitionCheckedAt':acquisition_checked_at,'capture':acquire(roots,parent)}
            raw = encoded(attempt); packed = gzip.compress(raw, mtime=0)
            retained = retain(root, label + '-attempt-' + str(index) + '.json.gz', packed)
            row = {'index': index, 'artifact': retained, 'decodedBytes': len(raw), 'decodedSHA256': sha(raw)}
            envelope['attempts'].append(row)
            assert retained['status'] == 'SUPPORTED exclusive durable evidence'
            assert set(attempt)=={'acquisitionCheckedAt','capture'}
            attempt=attempt['capture']
            assert set(attempt) == {'namespaceBefore','sample','namespaceAfter'}
            sample = attempt['sample']
            protocol.bind_roots(sample, roots)
            protocol.validate_sample(sample)
            assert sample['startedAt'] >= value['at'], 'Sample predates native barrier'
            retired=set()
            for key in ('namespaceBefore','namespaceAfter'):
                retired.update(inventory_matches(attempt[key],sample,parent,baseline))
            assert len(retired)<=1, 'Multiple retired-root identities observed'
            if current_phase == 'pre-recover':
                protocol.validate_pre(sample, expected['copyID'])
                observation={'observation':'VALID_ENDPOINT'}
            else:
                observation=protocol.validate_post(baseline,sample,expected['copyID'],prior_post,
                                                   allow_pending_refresh=current_phase=='post-success')
            pending=bool(retired) or observation['observation']=='OBSERVED_PENDING'
            row['observation']=observation
            row['pendingRetiredNames']=sorted(retired)
            row['predicateValid']=not pending
            if pending:
                previous_fingerprint=None
                if index+1<max_attempts:time.sleep(interval)
                continue
            fingerprint = sha(encoded({'roots': sample['roots'], 'entries': sample['entries'],
                                       'totalReadBytes': sample['totalReadBytes']}))
            row['fingerprint'] = fingerprint; row['predicateValid'] = True
            if previous_fingerprint == fingerprint:
                envelope['acceptedIndices'] = [index - 1, index]
                envelope['status'] = 'SUPPORTED two consecutive stable predicate-valid samples'
                accepted = sample
                ack = dict(expected, markerSHA256=marker_sha)
                break
            previous_fingerprint = fingerprint
            if index + 1 < max_attempts: time.sleep(interval)
        assert accepted is not None, 'No consecutive stable samples within attempt bound'
        assert time.time() < value['at'] + 45, 'Phase exceeded conservative native acknowledgement window'
    except BaseException:
        envelope['errors'].append({'stage': 'phase', 'error': traceback.format_exc()})
        accepted = None; ack = None
        envelope['status'] = 'FAILED phase; no acknowledgement'
    envelope['finishedAt'] = time.time()
    raw = encoded(envelope)
    artifact = retain(root, label + '-phase.json.gz', gzip.compress(raw, mtime=0))
    if artifact['status'] != 'SUPPORTED exclusive durable evidence': accepted = None; ack = None
    if ack is not None: ack['snapshotSHA256'] = artifact['readback']['sha256']
    return {'envelope': envelope, 'artifact': artifact, 'decodedBytes': len(raw),
            'decodedSHA256': sha(raw), 'acceptedSample': accepted, 'ack': ack}


def publish(root, label, runner_root, result):
    """Separate acknowledgement outcome; the frozen phase envelope stays unchanged."""
    assert result['ack'] is not None and result['acceptedSample'] is not None
    artifact = result['artifact']
    assert artifact['status'] == 'SUPPORTED exclusive durable evidence'
    assert result['ack']['snapshotSHA256'] == artifact['readback']['sha256']
    assert artifact['file'] == str(Path(root) / (label + '-phase.json.gz'))
    envelope = result['envelope']
    assert envelope['status'] == 'SUPPORTED two consecutive stable predicate-valid samples' and envelope['errors'] == []
    marker, marker_sha = marker_value(envelope['markerReadback'], envelope['expectedBinding'])
    assert time.time() < marker['at'] + 45, 'Native acknowledgement window expired'
    assert protocol.same(result['ack'], dict(envelope['expectedBinding'], markerSHA256=marker_sha,
                                            snapshotSHA256=artifact['readback']['sha256']))
    assert sha(gzip.compress(encoded(result['envelope']), mtime=0)) == artifact['readback']['sha256']
    for row in result['envelope']['attempts']: verify_artifact(root, row['artifact'])
    verify_artifact(root, artifact)
    binding = result['ack']
    name = 'Lumen-retained-backend-' + binding['runID'].lower() + '-' + binding['phase'] + '-ack.json'
    def intention(value):
        row = retain(root, label + '-ack-intention.json', encoded(value))
        assert row['status'] == 'SUPPORTED exclusive durable evidence', row
    def deadline():
        assert time.time() < marker['at'] + 45, 'Native acknowledgement window expired before rename'
    outcome = transport.write_once(runner_root, name, encoded(binding), intention, deadline)
    saved = retain(root, label + '-ack-outcome.json', encoded(outcome))
    return {'publication': outcome, 'outcomeArtifact': saved}


def verify_artifact(root, artifact):
    """Reopen retained evidence before sending a native-visible acknowledgement."""
    path = Path(artifact['file'])
    assert path.parent == Path(root) and artifact['status'] == 'SUPPORTED exclusive durable evidence'
    assert set(artifact) == {'file','expectedBytes','expectedSHA256','status','errors','readback'}
    assert artifact['errors'] == []
    recorded = artifact['readback']
    assert set(recorded) == {'bytes','sha256','identityBefore','identityAfter','identityNamedAfter'}
    assert protocol.integer(recorded['bytes'], 1) == protocol.integer(artifact['expectedBytes'], 1)
    assert type(recorded['sha256']) is str and re.fullmatch(r'[0-9a-f]{64}', recorded['sha256'])
    assert recorded['sha256'] == artifact['expectedSHA256']
    for key in ('identityBefore','identityAfter','identityNamedAfter'):
        identity = recorded[key]
        assert set(identity) == protocol.FIELDS
        for field, value in identity.items():
            protocol.integer(value, 0 if field in ('st_size','st_mtime_ns','st_ctime_ns') else 1)
        assert stat.S_ISREG(identity['st_mode']) and identity['st_nlink'] == 1
        assert identity['st_size'] == recorded['bytes']
        assert protocol.same(identity, recorded['identityNamedAfter'])
    opened = []; links = []; fd = None
    result = {'errors': []}
    try:
        opened, links = transport._anchors(root)
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                     dir_fd=opened[-1])
        before = os.fstat(fd)
        assert stat.S_ISREG(before.st_mode) and before.st_nlink == 1
        assert protocol.same(transport.facts(before), recorded['identityNamedAfter'])
        assert before.st_size == artifact['readback']['bytes'] <= 128 * 1024**2
        count = 0; digest = hashlib.sha256()
        while count <= before.st_size:
            chunk = os.read(fd, min(65536, before.st_size + 1 - count))
            if not chunk: break
            count += len(chunk); digest.update(chunk)
        after = os.fstat(fd); named = os.stat(path.name, dir_fd=opened[-1], follow_symlinks=False)
        assert transport.facts(before) == transport.facts(after) == transport.facts(named)
        assert count == before.st_size and digest.hexdigest() == artifact['readback']['sha256']
    finally:
        if fd is not None: os.close(fd)
        transport._finish(opened, links, result)
    assert result['errors'] == [], result
