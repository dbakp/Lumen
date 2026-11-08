"""Extend the exact old rejection prefix with a genuine fresh recovery commit."""
import importlib.util
from pathlib import Path
BASE=Path(__file__).resolve().parent
_spec=importlib.util.spec_from_file_location('fresh_target_stable_base',BASE/'healthy-target-evidence-prefix-r2.py')
_base=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_base)
for name in dir(_base):
    if not name.startswith('_'):globals()[name]=getattr(_base,name)
v=e.module('fresh_target_validator','legacy-target-change-validation-r3.py')
success=e.module('fresh_target_success','healthy-target-success-r1.py')
retirement=e.module('fresh_target_retirement','legacy-target-retirement-r1.py')
PHASES=_base.PHASES[:-1]+['fresh-committed','final-closed']
STATUSES=_base.STATUSES[:-1]+['fresh-recovery-committed','closed']
COUNTS=_base.COUNTS[:-1]+[13,14]
IMAGES=_base.IMAGES[:-2]+['fresh-healthy-region','fresh-selected','fresh-confirmation','fresh-committed']+_base.IMAGES[-2:]
EVENTS=_base.EVENTS[:-1]+['actual-recovery-success','closed']

def check_state(value,started,run=None,pid=None):
    count=value['sequence']
    if count<=12:
        _base.check_state(value,started,run,pid)
        return value
    assert count in [13,14] and len(value['events'])==count
    assert [row['event'] for row in value['events']]==EVENTS[:count]
    # Revalidate the entire unchanged prefix with its original strict schema.
    # This local projection never changes/publishes the actual retained record.
    projected=dict(value)
    projected['events']=value['events'][:12]+(value['events'][13:] if count==14 else [])
    projected['sequence']=len(projected['events'])
    projected['status']='closed' if count==14 else 'fresh-ready'
    _base.check_state(projected,started,run,pid)
    committed=value['events'][12]
    assert set(committed)=={'event','sessionID','captureID'}
    assert committed['sessionID']==value['events'][9]['sessionID']==value['sessionID']
    assert committed['captureID']==value['events'][10]['captureID']==value['captureID']
    assert value['status']==('fresh-recovery-committed' if count==13 else 'closed')
    return value

def origin_trace(group,index,old=None,fresh=None):
    if index<6:return _base.origin_trace(group,index,old,fresh)
    rows=h.events(group)
    expected=['open','ready','acquire','acquire','closed','open','ready','acquire']+(['closed'] if index==7 else [])
    assert index in [6,7] and [row['event'] for row in rows]==expected
    assert all(row['sessionID']==old for row in rows[:5])
    assert all(row['sessionID']==fresh for row in rows[5:]) and old!=fresh
    for ordinal,row in enumerate(rows):
        if row['event']=='ready':assert row['domains']==(['workouts'] if ordinal==6 else ['meals','workouts'])
        if row['event']=='acquire':assert row['domains']==(['workouts'] if ordinal==7 else ['meals'])
    return rows


def verify_host_source(name):
    """Bind corrected host inputs independently from the actual compiled case."""
    import base64,gzip,json
    assert Path(name).name==name and name.endswith('.json')
    source=h.load(BASE/name)
    archive=json.loads(gzip.decompress(h.read(BASE/(name+'.gz'),8*1024*1024)))
    count=0
    for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
        assert set(source[group])==set(archive[key])
        for path,wanted in source[group].items():
            raw=h.read(h.REPO/path,4*1024*1024)
            saved=archive[key][path].encode() if key=='files' else base64.b64decode(archive[key][path],validate=True)
            assert raw==saved and len(raw)==wanted['bytes'] and h.sha(raw)==wanted['sha256'],path
            count+=1
    return {'source':name,'exactCurrentArchiveBindings':count,'manifestSHA256':h.sha(h.read(BASE/name))}
