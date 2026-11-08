"""Additive actual-before-selection UI handshake; unchanged post-mutation rules."""
import importlib.util
from pathlib import Path
import time
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('target_prior',BASE/'target-string-evidence-base-r2.py')
parent=importlib.util.module_from_spec(spec);spec.loader.exec_module(parent)
for name in dir(parent):
    if not name.startswith('_'):globals()[name]=getattr(parent,name)
bootstrap=e.module('target_bootstrap','target-string-bootstrap-r1.py')
STATUSES=['before-selection']+parent.STATUSES[1:]

def check_state(value,started,run=None,pid=None):
    parent.check_state(value,started,run,pid)
    allowed=[['prepared','bootstrap-checking','before-selection'],['opened'],['capturing'],['ready'],['ready'],
             ['before-write'],['before-write'],['mutated'],['rejected'],['closed'],['opened'],['capturing'],['fresh-ready'],['closed']]
    assert value['status'] in allowed[value['sequence']]
    checked=value['bootstrapNativeChecked'];facts=value['bootstrapObservation']
    assert type(checked) is bool
    if value['status']=='prepared':
        assert value['sequence']==0 and checked is False and facts=={}
        return value
    assert facts['runID']==value['runID'] and facts['pid']==value['pid']
    assert started<=facts['at']<=value['at'] and facts['healthConnected'] is False
    obs.native_fixed(facts['fixed'],obs.OLD,h)
    for leaf in ['mealsLeaf','workoutsLeaf']:
        assert facts[leaf]=={'missing':True,'exists':False,'errno':2,'mode':0}
    if value['status']=='bootstrap-checking':assert value['sequence']==0 and checked is False
    else:assert checked is True
    return value
