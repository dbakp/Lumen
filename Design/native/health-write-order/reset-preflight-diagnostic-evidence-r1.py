"""Read-only narrow reset preflight diagnostic schema; no producer on import."""
import importlib.util,json,time,uuid
from pathlib import Path
BASE=Path(__file__).resolve().parent

def module(name,file):
 spec=importlib.util.spec_from_file_location(name,BASE/file);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

e=module('preflight_parent_evidence','legacy-settings-erase-evidence-r2.py');h=e.h
PROTOCOL='Lumen-legacy-reset-preflight-diagnostic-v1'
PREFIX='Lumen-legacy-reset-preflight-diagnostic-'
FLAGS=['-health-legacy-reset-ui','-health-legacy-reset-observer','-health-legacy-reset-run','-health-legacy-reset-diagnostic-only']
LEGACY=['lumen.llm.key','lumen.llm.oauth.token','lumen.llm.oauth.refresh','lumen.llm.oauth.account.v2','lumen.llm.connection.v3','strava.clientID','strava.clientSecret','strava.token','strava.refresh']
CLASSES={'approved-initial','blocked-context','blocked-health-connected','blocked-credentials-present','blocked-credential-query-status','blocked-legacy-provider-setting'}
ALLOWED={'verificationProtocol','runID','pid','at','diagnosticOnly','knownFlagPresence','credentialQueryPerformed','contextMode','contextValid','localHealthConnected','credentialQueryOSStatus','credentialAttributeMatchCount','knownLegacyProviderKeysPresent','classification','guardApproved'}


def validate(row,started):
 assert set(row)<=ALLOWED
 assert row['verificationProtocol']==PROTOCOL and row['pid']>0 and row['at']>=started
 assert row['runID']==str(uuid.UUID(row['runID'])).upper() and row['diagnosticOnly'] is True
 assert row['knownFlagPresence']==dict(zip(FLAGS,[True,False,True,True]))
 cls=row['classification'];assert cls in CLASSES
 assert row['guardApproved'] is (cls=='approved-initial')
 if cls=='blocked-context':
  assert row['credentialQueryPerformed'] is False and 'credentialQueryOSStatus' not in row
  return cls
 assert row['contextMode']=='initial-fixture' and row['contextValid'] is True
 if cls=='blocked-health-connected':
  assert row['localHealthConnected'] is True and row['credentialQueryPerformed'] is False
  return cls
 assert row['localHealthConnected'] is False and row['credentialQueryPerformed'] is True
 status=row['credentialQueryOSStatus'];assert type(status) is int and -2**31<=status<2**31
 if 'credentialAttributeMatchCount' in row:assert type(row['credentialAttributeMatchCount']) is int and row['credentialAttributeMatchCount']>=0
 if cls=='blocked-credentials-present':
  assert status==0
  if 'credentialAttributeMatchCount' in row:assert row['credentialAttributeMatchCount']>0
 elif cls=='blocked-credential-query-status':assert status not in [0,-25300]
 else:
  assert status==-25300 and set(row['knownLegacyProviderKeysPresent'])<=set(LEGACY)
  assert bool(row['knownLegacyProviderKeysPresent']) is (cls=='blocked-legacy-provider-setting')
 return cls


def snapshot(group,sink,legacy):
 root=group/'LumenData'
 sink['currentTree']={};e.observe_tree(root,sink['currentTree'])
 sink['priorTree']={};e.observe_tree(root.with_suffix('.previous'),sink['priorTree'])
 sink['fixed']={};e.fixed(legacy,sink['fixed'])
 sink['provider']=h.provider();sink['originEvents']=h.events(group)
 sink['stages']={p:[str(x) for x in group.glob(p)] for p in ['LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*']}
 assert not any(sink['stages'].values())
 return sink


def unchanged(before,after):
 for tree in ['currentTree','priorTree']:
  for field in ['files','metadata']:assert before[tree][field]==after[tree][field],(tree,field)
 for key in ['fixed','provider','originEvents']:assert before[key]==after[key],key
 return True
