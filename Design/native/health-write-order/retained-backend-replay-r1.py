"""Independent phase replay from durable files, never returned mutable samples.

Callers supply independently bound native bindings, container roots and provenance.
This is not process discovery, source approval, or proof that native accepted ACKs.
"""
import gzip
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import stat

B = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('phase', B / 'retained-backend-phase-r2.py')
p = importlib.util.module_from_spec(spec); spec.loader.exec_module(p)


def reference(record, binding):
    return {'phase': record['phase'], 'label': record['label'],
            'file': record['artifact']['file'],
            'snapshotSHA256': record['artifact']['readback']['sha256'],
            'decodedSHA256': record['decodedSHA256'],
            'runID': binding['runID'], 'nonce': binding['nonce']}


def context_for(context, records, bindings, marker_record):
    assert len(records) == len(bindings) and type(context) is dict and context
    return {'verificationContext': context,
            'priorPhases': [reference(record, binding) for record, binding in zip(records, bindings)],
            'markerObservation': marker_record}


def retain_marker(root, label, readback):
    """Retain even failed marker observations before interpreting native JSON."""
    raw = p.encoded(readback)
    artifact = p.retain(root, label + '-marker-observation.json.gz', gzip.compress(raw, mtime=0))
    assert artifact['status'] == 'SUPPORTED exclusive durable evidence', artifact
    return {'artifact': artifact, 'decodedBytes': len(raw), 'decodedSHA256': p.sha(raw)}


def record_for(label, result):
    return {'phase': result['envelope']['expectedBinding']['phase'], 'label': label,
            'artifact': result['artifact'], 'decodedBytes': result['decodedBytes'],
            'decodedSHA256': result['decodedSHA256']}


def load(root, artifact, decoded_bytes, decoded_sha):
    """Typed identity verification plus bounded second read, hash and gzip decode."""
    p.protocol.integer(decoded_bytes, 1)
    assert decoded_bytes <= 192 * 1024**2
    assert type(decoded_sha) is str
    p.verify_artifact(root, artifact)
    opened = []; links = []; fd = None; result = {'errors': []}; data = bytearray()
    try:
        opened, links = p.transport._anchors(root)
        fd = os.open(Path(artifact['file']).name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                     dir_fd=opened[-1])
        before = os.fstat(fd)
        assert stat.S_ISREG(before.st_mode)
        assert p.protocol.same(p.transport.facts(before), artifact['readback']['identityNamedAfter'])
        while len(data) <= before.st_size:
            chunk = os.read(fd, min(65536, before.st_size + 1 - len(data)))
            if not chunk: break
            data.extend(chunk)
        after = os.fstat(fd)
        named = os.stat(Path(artifact['file']).name, dir_fd=opened[-1], follow_symlinks=False)
        assert p.protocol.same(p.transport.facts(before), p.transport.facts(after))
        assert p.protocol.same(p.transport.facts(after), p.transport.facts(named))
        assert len(data) == artifact['readback']['bytes']
        assert hashlib.sha256(data).hexdigest() == artifact['readback']['sha256']
    finally:
        if fd is not None: os.close(fd)
        p.transport._finish(opened, links, result)
    assert result['errors'] == [], result
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
        raw = stream.read(decoded_bytes + 1)
    assert len(raw) == decoded_bytes and p.sha(raw) == decoded_sha
    value = p.unique_json(raw)
    assert p.encoded(value) == raw, 'Noncanonical or duplicate-key evidence JSON'
    return value


def replay(root, records, bindings, context, roots):
    """Recompute every earlier/current phase, including all pending samples.

    This runs both before publication and in the mandatory post-native checker.
    Host record digest must additionally match native marker/ACK/helper originals
    in that checker; this function does not claim native acceptance by itself.
    """
    assert type(records) is list and type(bindings) is list
    assert 1 <= len(records) <= 3 and len(records) == len(bindings)
    accepted = []; summaries = []; seen_nonces = set()
    for phase_index, (record, binding) in enumerate(zip(records, bindings)):
        assert set(record) == {'phase','label','artifact','decodedBytes','decodedSHA256'}
        assert record['phase'] == binding['phase'] == p.PHASES[phase_index]
        p.transport._name(record['label'])
        assert record['artifact']['file'] == str(Path(root) / (record['label'] + '-phase.json.gz'))
        envelope = load(root, record['artifact'], record['decodedBytes'], record['decodedSHA256'])
        assert set(envelope) == {'schema','startedAt','finishedAt','markerReadback','context',
                                 'expectedBinding','roots','namespaceParent','attempts','status',
                                 'errors','acceptedIndices'}
        assert envelope['schema'] == 'Lumen-retained-backend-phase-v2'
        assert envelope['status'] == 'SUPPORTED two consecutive stable predicate-valid samples'
        assert envelope['errors'] == []
        assert set(envelope['context']) == {'verificationContext','priorPhases','markerObservation'}
        observation_record = envelope['context']['markerObservation']
        assert set(observation_record) == {'artifact','decodedBytes','decodedSHA256'}
        assert observation_record['artifact']['file'] == str(Path(root) / (record['label'] + '-marker-observation.json.gz'))
        marker_observation = load(root, observation_record['artifact'], observation_record['decodedBytes'],
                                  observation_record['decodedSHA256'])
        assert p.protocol.same(marker_observation, envelope['markerReadback'])
        assert p.protocol.same(envelope['context'], context_for(context, records[:phase_index],
                                                              bindings[:phase_index], observation_record))
        assert p.protocol.same(envelope['roots'], roots)
        parent = str(Path(roots['current']).parent)
        assert roots['current'] == str(Path(parent) / 'LumenData')
        assert roots['previous'] == str(Path(parent) / 'LumenData.previous')
        assert envelope['namespaceParent'] == parent
        assert p.protocol.same(envelope['expectedBinding'], binding)
        marker, marker_sha = p.marker_value(envelope['markerReadback'], binding)
        assert binding['nonce'] not in seen_nonces
        seen_nonces.add(binding['nonce'])
        if phase_index:
            for key in ('runID','runnerPID','case','copyID','sessionID','captureID','selected'):
                assert p.protocol.same(binding[key], bindings[0][key]), ('Prior native identity differs', key)
            assert marker['at'] >= summaries[-1]['finishedAt']
        assert 0 < p.protocol.number(envelope['startedAt']) <= p.protocol.number(envelope['finishedAt'])
        assert marker['at'] <= envelope['startedAt'] + 1
        assert envelope['finishedAt'] < marker['at'] + 45
        attempts = envelope['attempts']
        assert type(attempts) is list and 2 <= len(attempts) <= 48
        previous_fingerprint = None; chosen = None; last_finished = marker['at']
        for index, row in enumerate(attempts):
            common = {'index','artifact','decodedBytes','decodedSHA256','observation','pendingRetiredNames','predicateValid'}
            assert set(row) in (common, common | {'fingerprint'})
            assert p.protocol.integer(row['index']) == index
            assert row['artifact']['file'] == str(Path(root) / (record['label'] + '-attempt-' + str(index) + '.json.gz'))
            attempt = load(root, row['artifact'], row['decodedBytes'], row['decodedSHA256'])
            assert set(attempt)=={'acquisitionCheckedAt','capture'}
            checked=p.protocol.number(attempt['acquisitionCheckedAt'])
            assert last_finished<=checked<marker['at']+40, 'Acquisition guard outside its native window'
            attempt=attempt['capture']
            assert set(attempt) == {'namespaceBefore','sample','namespaceAfter'}
            assert checked<=p.protocol.number(attempt['namespaceBefore']['startedAt']), 'Guard follows acquisition'
            sample = attempt['sample']
            p.protocol.bind_roots(sample, roots); p.protocol.validate_sample(sample)
            assert last_finished <= sample['startedAt'] <= sample['finishedAt'] <= envelope['finishedAt']
            previous_finished = last_finished
            retired = set()
            baseline = accepted[0] if phase_index else None
            for key in ('namespaceBefore','namespaceAfter'):
                inventory = attempt[key]
                assert set(inventory) == {'status','path','startedAt','finishedAt','entries','errors',
                                           'namesBefore','namesAfter','inventoryBefore','inventoryAfter'}
                assert 0 < p.protocol.number(inventory['startedAt']) <= p.protocol.number(inventory['finishedAt'])
                if key == 'namespaceBefore':
                    assert previous_finished <= inventory['startedAt'] <= inventory['finishedAt'] <= sample['startedAt']
                else: assert sample['finishedAt'] <= inventory['startedAt'] <= inventory['finishedAt'] <= envelope['finishedAt']
                retired.update(p.inventory_matches(inventory, sample, parent, baseline))
            last_finished = attempt['namespaceAfter']['finishedAt']
            assert len(retired) <= 1
            if phase_index == 0:
                p.protocol.validate_pre(sample, binding['copyID'])
                observation = {'observation':'VALID_ENDPOINT'}
            else:
                observation = p.protocol.validate_post(accepted[0], sample, binding['copyID'],
                                                      accepted[1] if phase_index == 2 else None,
                                                      allow_pending_refresh=phase_index == 1)
            pending = bool(retired) or observation['observation'] == 'OBSERVED_PENDING'
            assert p.protocol.same(row['observation'], observation)
            assert p.protocol.same(row['pendingRetiredNames'], sorted(retired))
            assert row['predicateValid'] is (not pending)
            if pending:
                assert set(row) == common
                previous_fingerprint = None
                continue
            fingerprint = p.sha(p.encoded({'roots':sample['roots'], 'entries':sample['entries'],
                                           'totalReadBytes':sample['totalReadBytes']}))
            assert row['fingerprint'] == fingerprint
            if previous_fingerprint == fingerprint:
                assert index == len(attempts) - 1, 'Acquisition continued after stable acceptance'
                assert p.protocol.same(envelope['acceptedIndices'], [index - 1, index])
                chosen = sample
            previous_fingerprint = fingerprint
        assert chosen is not None
        accepted.append(chosen)
        summaries.append({'phase':record['phase'], 'finishedAt':envelope['finishedAt'],
                          'markerSHA256':marker_sha, 'snapshotSHA256':record['artifact']['readback']['sha256'],
                          'acceptedIndices':envelope['acceptedIndices'], 'attempts':len(attempts)})
    return {'samples':accepted, 'phases':summaries,
            'scope':'Replayed bound persisted endpoints only; native ACK acceptance and actual provenance remain separate mandatory checks.'}


def publish_checked(root, label, runner_root, records, bindings, context, roots, result):
    """Replay every immutable phase before invoking native-visible publication."""
    verified = replay(root, records, bindings, context, roots)
    assert records[-1]['label'] == label
    assert p.protocol.same(records[-1], record_for(label, result))
    checked_result = dict(result, acceptedSample=verified['samples'][-1])
    outcome = p.publish(root, label, runner_root, checked_result)
    return {'phaseReplay': verified['phases'], 'publicationOutcome': outcome}
