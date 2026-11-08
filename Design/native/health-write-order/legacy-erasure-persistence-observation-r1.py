"""Read-only, finite observation of the two declared erased preference keys.

No preferences APIs, writes, synchronization, host repair or native producer.
"""
import base64
import os
from pathlib import Path
import plistlib
import time
import traceback

KEYS = {'meals': 'lumen.health.meals.v1', 'workouts': 'lumen.health.workouts.v1'}
BUDGET = 10.0
INTERVAL = 0.1
ABSENT_SEPARATION = 0.2


def acquire(path, sink, h):
    """Capture both known keys before any expected-value assertion."""
    sink['path'] = str(path)
    sink['exists'] = os.path.lexists(path)
    if sink['exists']:
        sink['identity'] = h.identity(path)
        raw = h.read(path)
        sink['plistBytes'] = len(raw)
        sink['plistSHA256'] = h.sha(raw)
        after = h.identity(path)
        sink['identityAfterRead'] = after
        assert after == sink['identity'], 'Preference file changed during acquisition'
        values = plistlib.loads(raw)
        sink['plistRootType'] = type(values).__name__
        assert type(values) is dict
    else:
        values = {}
    sink['fixed'] = {}
    for domain, key in KEYS.items():
        value = values.get(key)
        row = {'key': key, 'present': key in values, 'actualType': type(value).__name__}
        sink['fixed'][domain] = row
        if type(value) is bytes:
            row.update(type='data', actualBytes=len(value))
            if len(value) <= 4096:
                row.update(h.row(value))
        elif type(value) is str:
            encoded = value.encode('utf-16-le', errors='surrogatepass')
            row.update(type='stringUTF16LE', actualBytes=len(encoded))
            if len(encoded) <= 4096:
                row.update(h.row(encoded))
    sink['healthConnected'] = {'present': 'lumen.health.connected' in values,
                               'effectiveBool': bool(values.get('lumen.health.connected', False))}


def wait(path, original, native, sink, persist, h, *, clock=time.monotonic,
         wall=time.time, sleep=time.sleep):
    """Acknowledge nothing; caller must still run the full strict erased check."""
    started = clock()
    sink.update(status='OBSERVING read-only preference persistence', budgetSeconds=BUDGET,
                intervalSeconds=INTERVAL, absentSeparationSeconds=ABSENT_SEPARATION, samples=[])
    persist()
    try:
        assert original['kind'] in ['data', 'string']
        assert set(original['values']) == set(KEYS)
        assert set(native['fixed']) == set(KEYS)
        assert native['healthConnected'] is False and native['healthAuthorized'] is False
        expected_type = 'data' if original['kind'] == 'data' else 'stringUTF16LE'
        expected = {}
        for domain, key in KEYS.items():
            assert original['values'][domain]['key'] == key
            value = base64.b64decode(original['values'][domain]['payload'], validate=True)
            assert len(value) <= 4096
            expected[domain] = value
            row = native['fixed'][domain]
            assert row['key'] == key and row['persistedPresent'] is False and row['effectivePresent'] is False
        first_absent = None
        consecutive = 0
        while True:
            assert clock() - started <= BUDGET, 'Preference persistence observation deadline'
            sample = {'at': wall(), 'elapsedBeforeRead': clock() - started, 'status': 'ACQUIRING'}
            sink['samples'].append(sample)
            persist()
            try:
                acquire(Path(path), sample, h)
                sample['elapsedAfterRead'] = clock() - started
                persist()  # Both acquired key facts survive any rejection below.
                assert sample['elapsedAfterRead'] <= BUDGET, 'Preference persistence observation deadline'
                assert sample['healthConnected']['effectiveBool'] is False
                absent = True
                for domain, row in sample['fixed'].items():
                    if row['present']:
                        absent = False
                        assert row.get('type') == expected_type, 'Unexpected persisted fixed-key type'
                        assert row.get('actualBytes', 4097) <= 4096 and 'base64' in row
                        assert base64.b64decode(row['base64'], validate=True) == expected[domain], 'Unexpected persisted fixed-key value'
                sample['bothAbsent'] = absent
                sample['status'] = 'ABSENT' if absent else 'EXACT ORIGINAL STILL PRESENT'
                if absent:
                    consecutive += 1
                    if first_absent is None:
                        first_absent = sample['elapsedAfterRead']
                    if consecutive >= 2 and sample['elapsedAfterRead'] - first_absent >= ABSENT_SEPARATION:
                        sink.update(status='PASS bounded read-only stable absence; full erased check still required',
                                    elapsedSeconds=sample['elapsedAfterRead'], consecutiveAbsent=consecutive)
                        persist()
                        return
                else:
                    consecutive = 0
                    first_absent = None
            except BaseException:
                sample['status'] = 'FAILED'
                sample['error'] = traceback.format_exc()
                raise
            finally:
                persist()
            remaining = BUDGET - (clock() - started)
            assert remaining > 0, 'Preference persistence observation deadline'
            sleep(min(INTERVAL, remaining))
    except BaseException:
        sink['status'] = 'FAILED read-only preference observation; no acknowledgement'
        sink['error'] = traceback.format_exc()
        persist()
        raise


def validate_retained(sink, original, native):
    """Read-only verification of a completed wait; never acknowledges a test."""
    assert sink['status'] == 'PASS bounded read-only stable absence; full erased check still required'
    assert not sink.get('error')
    assert sink['budgetSeconds'] == BUDGET and sink['intervalSeconds'] == INTERVAL
    assert sink['absentSeparationSeconds'] == ABSENT_SEPARATION
    expected_type = 'data' if original['kind'] == 'data' else 'stringUTF16LE'
    assert original['kind'] in ['data', 'string'] and set(original['values']) == set(KEYS)
    assert native['healthConnected'] is False and native['healthAuthorized'] is False
    for domain, key in KEYS.items():
        assert original['values'][domain]['key'] == native['fixed'][domain]['key'] == key
        assert native['fixed'][domain]['persistedPresent'] is False and native['fixed'][domain]['effectivePresent'] is False
    previous = -1
    trailing = []
    for sample in sink['samples']:
        assert not sample.get('error')
        assert previous <= sample['elapsedBeforeRead'] <= sample['elapsedAfterRead'] <= BUDGET
        previous = sample['elapsedAfterRead']
        assert set(sample['fixed']) == set(KEYS) and sample['healthConnected']['effectiveBool'] is False
        absent = True
        for domain, key in KEYS.items():
            row = sample['fixed'][domain]
            assert row['key'] == key
            if row['present']:
                absent = False
                assert row.get('type') == expected_type and row['actualBytes'] <= 4096
                value = base64.b64decode(row['base64'], validate=True)
                assert value == base64.b64decode(original['values'][domain]['payload'], validate=True)
        assert sample['bothAbsent'] is absent
        assert sample['status'] == ('ABSENT' if absent else 'EXACT ORIGINAL STILL PRESENT')
        trailing = trailing + [sample] if absent else []
    assert len(trailing) >= 2 and sink['consecutiveAbsent'] == len(trailing)
    assert trailing[-1]['elapsedAfterRead'] - trailing[0]['elapsedAfterRead'] >= ABSENT_SEPARATION
    assert sink['elapsedSeconds'] == trailing[-1]['elapsedAfterRead']
