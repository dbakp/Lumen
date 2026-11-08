"""Strict context, authority and protected-state predicates for Source226."""
import importlib.util
import json
import os
import re
from pathlib import Path
BASE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('target_parent', BASE/'legacy-settings-erase-evidence-r3.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)
h = e.h
obs = e.module('target_observation', 'legacy-target-change-observation-r1.py')
healthy = e.module('healthy_file_facts','healthy-target-protected-r2.py')
PROTOCOL = 'Lumen-healthy-target-change-verification-v1'
PHASES = ['before-selection', 'ready', 'target-changed', 'rejected', 'owners-closed', 'fresh-ready', 'final-closed']
STATUSES = ['prepared', 'ready', 'mutated', 'rejected', 'closed', 'fresh-ready', 'closed']
IMAGES = ['before-selection', 'ready-original', 'ready-choices', 'selected-meal', 'target-mutated', 'confirmation',
          'changed-error', 'owners-closed', 'owners-followup', 'fresh-original', 'fresh-off', 'final-closed', 'final-followup']
MESSAGE = 'Your saved data changed. Go back and review it again.'
EVENTS = ['open', 'capture-began', 'capture-ready', 'guard-observation', 'before-write', 'result-observation',
          'mutated', 'actual-recovery-error', 'closed', 'open', 'capture-began', 'capture-ready', 'closed']
COUNTS = [0, 3, 7, 8, 9, 12, 13]

def check_state(value, started, run=None, pid=None):
    from uuid import UUID
    assert value['verificationProtocol'] == PROTOCOL and value['at'] >= started
    assert value['originKind']=='data' and value['targetKind']=='healthy-current-file'
    assert str(UUID(value['runID'])) == value['runID'].lower()
    assert type(value['pid']) is int and value['pid'] > 0
    if run is not None: assert value['runID'] == run
    if pid is not None: assert value['pid'] == pid
    assert value['failed'] is False and value['healthConnected'] is False
    events = value['events']; n = len(events)
    assert value['sequence'] == n and n <= len(EVENTS)
    assert [r['event'] for r in events] == EVENTS[:n]
    assert value['singleUseConsumed'] is (n >= 5)
    assert value['knownFileWritten'] is (n >= 6)
    if n == 0:
        assert value['sessionID'] == value['captureID'] == ''
    else:
        owner = events[9]['sessionID'] if n >= 10 else events[0]['sessionID']
        assert value['sessionID'] == owner
        UUID(owner)
        for row in events[:9]:
            assert row['sessionID'] == events[0]['sessionID']
        for row in events[9:]: assert row['sessionID'] == owner
        if n >= 10: assert owner != events[0]['sessionID']
    for a,b in [(1,2),(10,11)]:
        if n > a:
            UUID(events[a]['captureID']); assert events[a]['actualControl'].startswith('ObjectIdentifier(')
        if n > b:
            assert events[b]['captureID'] == events[a]['captureID']
            assert events[b]['actualControl'] == events[a]['actualControl']
            assert events[b]['domains'] == (['workouts'] if a==10 else ['meals','workouts'])
    if n >= 2:
        assert value['captureID'] == (events[10]['captureID'] if n >= 11 else ('' if n == 10 else events[1]['captureID']))
    if n >= 12: assert events[10]['captureID'] != events[1]['captureID']
    for i in [3,4,5,6]:
        if n > i:
            assert events[i]['captureID'] == events[1]['captureID']
            obs.native_fixed(events[i]['fixed'], h.DATA, h)
            leaf=events[i]['mealFile'];root=Path(leaf['path']).parent
            healthy.native_leaf(leaf,root,i>=5,h)
            assert all(events[j]['mealFile']['path']==leaf['path'] for j in [3,4,5,6] if n>j)
    if n >= 5:
        assert events[4]['oldTokenVerified'] is True
        assert events[4]['guardAcquisitionControl'].startswith('ObjectIdentifier(')
    if n >= 8:
        row = events[7]
        assert row['changedClassification'] is True and row['publishedMessage'] == MESSAGE
        assert row['actualErrorType'] and row['actualRecoveryControl'].startswith('ObjectIdentifier(')
    return value

def protected(group, sink, original=None):
    root = group/'LumenData'
    for name,path in [('current',root),('prior',root.with_suffix('.previous'))]:
        sink[name] = {}; e.observe_tree(path, sink[name])
    sink['provider'] = h.provider()
    sink['residuals'] = {p: [str(x) for x in group.glob(p)] for p in ['LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*']}
    assert not any(sink['residuals'].values())
    assert not {'meals.json','workouts.json'} & set(sink['current']['files'])
    if original is None:
        assert len(sink['current']['files']) == len(sink['prior']['files']) == 13
        copies = {k:v for k,v in sink['current']['files'].items() if k.startswith('.health-recovery/')}
        assert len(copies) == 3 and all(sink['prior']['files'].get(k)==v for k,v in copies.items())
        manifest = json.loads(e.base64.b64decode(next(v['base64'] for k,v in copies.items() if k.endswith('/manifest.json'))))
        assert manifest['version']==1 and manifest['domains']==['today'] and manifest['photos'] is False and manifest['intent'] is True
        journal = h.load(root/'health-write-intent.json')
        assert {x['localID'] for x in journal['events']} == {'synthetic-reset-pending-removal','synthetic-reset-unstarted-save'}
    else:
        for name in ['current','prior']:
            for key in ['rootIdentity','files','metadata']:
                assert sink[name][key] == original[name][key], (name,key)
        assert sink['provider']==original['provider']
    return sink

def origin_trace(group, index, old=None, fresh=None):
    rows=h.events(group)
    expected=[[],['open','ready'],['open','ready','acquire'],['open','ready','acquire','acquire'],
              ['open','ready','acquire','acquire','closed'],
              ['open','ready','acquire','acquire','closed','open','ready'],
              ['open','ready','acquire','acquire','closed','open','ready','closed']][index]
    assert [r['event'] for r in rows]==expected
    if old:
        assert all(r['sessionID']==old for r in rows[:5])
    if fresh:
        assert all(r['sessionID']==fresh for r in rows[5:])
    for ordinal,row in enumerate(rows):
        if row['event']=='ready': assert row['domains']==(['workouts'] if ordinal==6 else ['meals','workouts'])
        if row['event']=='acquire': assert row['domains']==['meals']
    return rows
