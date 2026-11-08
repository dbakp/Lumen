"""Finite read-only old→new observation for two known synthetic String keys."""
import base64
import json
import plistlib
import time
import traceback
import importlib.util
from pathlib import Path
_codec_spec=importlib.util.spec_from_file_location('strict_string_codec',Path(__file__).resolve().parent/'target-string-codec-r1.py')
_codec=importlib.util.module_from_spec(_codec_spec);_codec_spec.loader.exec_module(_codec)
OLD=_codec.OLD
NEW=_codec.NEW

KEYS = ['lumen.health.meals.v1', 'lumen.health.workouts.v1']

def native_fixed(facts, meals, h):
    assert set(facts) == set(KEYS)
    for key in KEYS:
        wanted = meals if key == KEYS[0] else OLD
        assert set(facts[key]) == {'persisted', 'effective'}
        for value in facts[key].values():
            assert value['present'] is True and value['bytes'] == len(wanted)
            assert value['sha256'] == h.sha(wanted)
            assert base64.b64decode(value['payload'], validate=True) == wanted
            assert value['type'] in ['Swift.String','Foundation.NSString','__NSCFString','__NSCFConstantString'] and not value.get('oversize')
            assert value['utf16Units']*2 == len(wanted)

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
            if type(value) is str:
                value = _codec.encode(value)
                facts['bytes'] = len(value)
                if len(value) <= 4096:
                    facts['sha256'] = h.sha(value)
                    if value in [OLD, NEW]: facts['base64'] = base64.b64encode(value).decode()
                else: facts['oversize'] = True
        persist()
        assert sink['healthConnected'] is None or sink['healthConnected'] is False
        for key in KEYS:
            value = values.get(key)
            assert type(value) is str
            value = _codec.encode(value)
            assert value in (allowed if key == KEYS[0] else [OLD]), key
        sink['classification'] = 'new' if _codec.encode(values[KEYS[0]]) == NEW else 'old'
        return sink['classification']
    except BaseException:
        sink['error'] = traceback.format_exc(); persist(); raise
    finally: persist()

def wait(path, h, sink, persist, clock=time.monotonic, sleep=time.sleep):
    start = clock(); sink.update(budgetSeconds=10, intervalSeconds=0.1, stableSamples=3, stableSpanSeconds=0.2, samples=[])
    streak = []
    while True:
        row = {'elapsed': clock()-start}; sink['samples'].append(row); persist()
        kind = sample(path, h, row, persist, [OLD, NEW])
        now = clock(); row['completedElapsed'] = now-start
        if kind == 'new': streak.append(now)
        else: streak = []
        persist()
        assert now-start < 10, 'Finite target-persistence observation deadline'
        if len(streak) >= 3 and now-streak[0] >= 0.2:
            sink.update(status='PASS bounded exact new-value observations', acceptedElapsed=now-start); persist(); return
        sleep(min(0.1, max(0, 10-(clock()-start))))
