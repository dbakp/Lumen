"""Separate cancellation case: no origin acquisition or recovery commit allowed."""
import importlib.util
from pathlib import Path
from uuid import UUID
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('lifecycle_prior',BASE/'confirmation-target-evidence-r1.py')
_parent=importlib.util.module_from_spec(spec);spec.loader.exec_module(_parent)
for name in dir(_parent):
    if not name.startswith('_'):globals()[name]=getattr(_parent,name)
PHASES=['before-selection','ready','owners-closed','fresh-ready','final-closed']
COUNTS=[0,3,4,7,8]
STATUSES=['before-selection','ready','closed','fresh-ready','closed']
EVENTS=['open','capture-began','capture-ready','closed','open','capture-began','capture-ready','closed']
IMAGES=['before-selection','ready-original','ready-choices','selected-meal','presented',
        'not-now-dismissed','not-now-choices','checked','owners-closed','owners-followup',
        'fresh-original','fresh-off','final-closed','final-followup']

def canonical_uuid(value):
    assert type(value) is str and UUID(value).hex.upper()==value.replace('-','') and str(UUID(value)).upper()==value

def check_state(value,started,run=None,pid=None):
    assert value['verificationProtocol']==PROTOCOL and value['originKind']=='data'
    assert type(value['at']) in [int,float] and value['at']>=started
    canonical_uuid(value['runID'])
    assert type(value['pid']) is int and value['pid']>0
    if run is not None:assert value['runID']==run
    if pid is not None:assert value['pid']==pid
    for key in ['failed','healthConnected','singleUseConsumed','knownKeyWritten']:assert value[key] is False
    events=value['events'];n=len(events)
    assert type(value['sequence']) is int and value['sequence']==n and n<=8
    assert [r['event'] for r in events]==EVENTS[:n]
    statuses=[['prepared','bootstrap-checking','before-selection'],['opened'],['capturing'],['ready'],
              ['closed'],['opened'],['capturing'],['fresh-ready'],['closed']]
    assert value['status'] in statuses[n]
    for offset in [0,4]:
        subset=events[offset:offset+4]
        if not subset:continue
        owner=subset[0]['sessionID'];canonical_uuid(owner)
        assert all(r['sessionID']==owner for r in subset)
        assert set(subset[0])=={'event','sessionID'}
        if len(subset)>1:
            capture=subset[1]['captureID'];canonical_uuid(capture)
            assert set(subset[1])=={'event','sessionID','captureID','actualControl'}
            assert subset[1]['actualControl'].startswith('ObjectIdentifier(')
        if len(subset)>2:
            assert set(subset[2])=={'event','sessionID','captureID','actualControl','domains'}
            assert subset[2]['captureID']==capture and subset[2]['actualControl']==subset[1]['actualControl']
            assert subset[2]['domains']==['meals','workouts']
        if len(subset)>3:assert set(subset[3])=={'event','sessionID'}
    if n==0:assert value['sessionID']==value['captureID']==''
    else:
        offset=4 if n>=5 else 0
        assert value['sessionID']==events[offset]['sessionID']
        assert value['captureID']==(events[offset+1]['captureID'] if n>=offset+2 else '')
    if n>=5:assert events[0]['sessionID']!=events[4]['sessionID']
    if n>=6:assert events[1]['captureID']!=events[5]['captureID']
    checked=value['bootstrapNativeChecked'];facts=value['bootstrapObservation']
    assert type(checked) is bool
    if value['status']=='prepared':assert checked is False and facts=={}
    else:
        assert facts['runID']==value['runID'] and facts['pid']==value['pid']
        assert started<=facts['at']<=value['at'] and facts['healthConnected'] is False
        obs.native_fixed(facts['fixed'],h.DATA,h)
        for leaf in ['mealsLeaf','workoutsLeaf']:assert facts[leaf]=={'missing':True,'exists':False,'errno':2,'mode':0}
        assert checked is (value['status']!='bootstrap-checking')
    return value

def origin_trace(group,index,old=None,fresh=None):
    rows=h.events(group)
    expected=[[],['open','ready'],['open','ready','closed'],
              ['open','ready','closed','open','ready'],['open','ready','closed','open','ready','closed']][index]
    assert [r['event'] for r in rows]==expected
    if old:assert all(r['sessionID']==old for r in rows[:3])
    if fresh:assert old!=fresh and all(r['sessionID']==fresh for r in rows[3:])
    for row in rows:
        if row['event']=='ready':assert row['domains']==['meals','workouts']
    return rows
