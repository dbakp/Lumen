"""Finite read-only old→new observation for two known synthetic Data keys."""
import base64
import json
import plistlib
import time
import traceback
NEW = b'{synthetic newer persisted meals damaged'
KEYS = ['lumen.health.meals.v1', 'lumen.health.workouts.v1']

def native_fixed(facts, meals, h):
    assert set(facts) == set(KEYS)
    for key in KEYS:
        wanted = meals if key == KEYS[0] else h.DATA
        assert set(facts[key]) == {'persisted', 'effective'}
        for value in facts[key].values():
            assert value['present'] is True and value['bytes'] == len(wanted)
            assert value['sha256'] == h.sha(wanted)
            assert base64.b64decode(value['payload'], validate=True) == wanted
            assert 'Data' in value['type'] and not value.get('oversize')

def sample(path, h, sink, persist, allowed):
    """Actual bounded facts are persisted BEFORE any type/equality assertion."""
    try:
        raw = h.read(path, 256*1024)
        values = plistlib.loads(raw)
        sink.update(plistBytes=len(raw), plistSHA256=h.sha(raw), fixed={}, healthConnected=values.get('lumen.health.connected'))
        for key in KEYS:
            value = values.get(key)
            facts = {'present': key in values, 'type': type(value).__name__}
            sink['fixed'][key] = facts
            if type(value) is bytes:
                facts['bytes'] = len(value)
                if len(value) <= 4096:
                    facts['sha256'] = h.sha(value)
                    if value in [h.DATA, NEW]: facts['base64'] = base64.b64encode(value).decode()
                else: facts['oversize'] = True
        persist()
        assert sink['healthConnected'] is None or sink['healthConnected'] is False
        for key in KEYS:
            value = values.get(key)
            assert type(value) is bytes and len(value) <= 4096
            assert value in (allowed if key == KEYS[0] else [h.DATA]), key
        sink['classification'] = 'new' if values[KEYS[0]] == NEW else 'old'
        return sink['classification']
    except BaseException:
        sink['error'] = traceback.format_exc(); persist(); raise
    finally: persist()

def wait(path, h, sink, persist, clock=time.monotonic, sleep=time.sleep):
    start = clock(); sink.update(budgetSeconds=10, intervalSeconds=0.1, stableSamples=3, stableSpanSeconds=0.2, samples=[])
    streak = []
    while True:
        row = {'elapsed': clock()-start}; sink['samples'].append(row); persist()
        kind = sample(path, h, row, persist, [h.DATA, NEW])
        now = clock(); row['completedElapsed'] = now-start
        if kind == 'new': streak.append(now)
        else: streak = []
        persist()
        assert now-start < 10, 'Finite target-persistence observation deadline'
        if len(streak) >= 3 and now-streak[0] >= 0.2:
            sink.update(status='PASS bounded exact new-value observations', acceptedElapsed=now-start); persist(); return
        sleep(min(0.1, max(0, 10-(clock()-start))))
