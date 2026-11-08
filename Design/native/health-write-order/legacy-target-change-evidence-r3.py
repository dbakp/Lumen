"""Extend the exact old rejection prefix with a genuine fresh recovery commit."""
import importlib.util
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('fresh_target_parent',BASE/'legacy-target-change-evidence-r2.py')
parent=importlib.util.module_from_spec(spec);spec.loader.exec_module(parent)
for name in dir(parent):
    if not name.startswith('_'):globals()[name]=getattr(parent,name)
v=e.module('fresh_target_validator','legacy-target-change-validation-r3.py')
success=e.module('fresh_target_success','legacy-target-fresh-success-r1.py')
PHASES=parent.PHASES[:-1]+['fresh-committed','final-closed']
STATUSES=parent.STATUSES[:-1]+['fresh-recovery-committed','closed']
COUNTS=parent.COUNTS[:-1]+[13,14]
IMAGES=parent.IMAGES[:-2]+['fresh-selected','fresh-confirmation','fresh-committed']+parent.IMAGES[-2:]
EVENTS=parent.EVENTS[:-1]+['actual-recovery-success','closed']

def check_state(value,started,run=None,pid=None):
    count=value['sequence']
    if count<=12:
        parent.check_state(value,started,run,pid)
        return value
    assert count in [13,14] and len(value['events'])==count
    assert [row['event'] for row in value['events']]==EVENTS[:count]
    # Revalidate the entire unchanged prefix with its original strict schema.
    # This local projection never changes/publishes the actual retained record.
    projected=dict(value)
    projected['events']=value['events'][:12]+(value['events'][13:] if count==14 else [])
    projected['sequence']=len(projected['events'])
    projected['status']='closed' if count==14 else 'fresh-ready'
    parent.check_state(projected,started,run,pid)
    committed=value['events'][12]
    assert set(committed)=={'event','sessionID','captureID'}
    assert committed['sessionID']==value['events'][9]['sessionID']==value['sessionID']
    assert committed['captureID']==value['events'][10]['captureID']==value['captureID']
    assert value['status']==('fresh-recovery-committed' if count==13 else 'closed')
    return value

def origin_trace(group,index,old=None,fresh=None):
    if index<6:return parent.origin_trace(group,index,old,fresh)
    rows=h.events(group)
    expected=['open','ready','acquire','acquire','closed','open','ready','acquire']+(['closed'] if index==7 else [])
    assert index in [6,7] and [row['event'] for row in rows]==expected
    assert all(row['sessionID']==old for row in rows[:5])
    assert all(row['sessionID']==fresh for row in rows[5:]) and old!=fresh
    for ordinal,row in enumerate(rows):
        if row['event']=='ready':assert row['domains']==['meals','workouts']
        if row['event']=='acquire':assert row['domains']==(['meals','workouts'] if ordinal==7 else ['meals'])
    return rows
