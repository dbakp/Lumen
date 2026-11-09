"""Actual pure R4 builder: distinct case/host manifests and safe reviewed checker selection."""
from pathlib import Path
import copy,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent;queries=[]
def denied(*a,**kw):queries.append(str(a));raise AssertionError('Process calls denied')
for k in ['Popen','run','check_call','check_output','call']:setattr(subprocess,k,denied)
s=importlib.util.spec_from_file_location('actual_finalizer_r4',B/'confirmation-expiry-finalization-r1.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
plan=json.loads((B/'source257-expiry-execution-r1-plan.json').read_bytes());state=json.loads((B/'health-confirmation-notnow-data-source255r1-driver-observations.json').read_bytes());out=json.loads((B/'health-confirmation-notnow-data-source255r1-outcome.json').read_bytes());
for d in [state,out,state['preflight']]:d.update(source=plan['caseSource'],build=plan['build'])
state['hostSource']=plan['source'];state['hostSourceVerification']['source']=plan['source'];state['command'][state['command'].index('-resultBundlePath')+1]='/tmp/LumenBatch44Checks/'+plan['rawStem']+'.xcresult';rows=[]
def check(label,p,s,o,wanted):
 error=None;command=None
 try:command=m.checker_command(B,p,s,o)
 except AssertionError as e:error=str(e)
 assert (error is None)==wanted,label
 rows.append({'case':label,'accepted':error is None,'command':command,'status':'PASS'})
check('synthetic future mixed case255 host256 coherence only',plan,state,out,True);assert rows[-1]['command']==['python3',str(B/plan['checker']),plan['prefix'],'--checker-source',plan['source'],'--case-source',plan['caseSource'],'--build',plan['build'],'--trial',plan['checkerTrial']]
for label,path,value in [('case source',['source'],'durable-source-r254.json'),('host source',['hostSource'],'durable-source-r255.json'),('preflight source',['preflight','source'],'durable-source-r254.json'),('host source verification',['hostSourceVerification','source'],'durable-source-r255.json'),('case build',['build'],'health-target-change-source254-r1-build.json'),('preflight build',['preflight','build'],'health-target-change-source254-r1-build.json'),('resultbundle',['command'],['xcodebuild','-resultBundlePath','/tmp/wrong.xcresult']),('duplicate bundle',['command'],state['command']+['-resultBundlePath','/tmp/wrong.xcresult'])]:
 x=copy.deepcopy(state);target=x
 for key in path[:-1]:target=target[key]
 target[path[-1]]=value;check('reject '+label,plan,x,out,False)
for field,value in [('source','durable-source-r255.json'),('caseSource','durable-source-r254.json'),('build','health-target-change-source254-r1-build.json'),('prefix','health-confirmation-notnow-data-source255r1'),('rawStem','HealthConfirmationNotNowDataSource255R1'),('nativeTrial','Source255R1'),('checkerTrial','../unsafe'),('checker','../check-confirmation-lifecycle-r3.py'),('checker','other.py'),('checkerOutcomeProtocol','expiry-r2')]:
 p=dict(plan);p[field]=value;check('reject plan '+field+' '+value,p,state,out,False)
for field,value in [('source','durable-source-r254.json'),('build','health-target-change-source254-r1-build.json')]:
 o=dict(out);o[field]=value;check('reject outcome '+field,plan,state,o,False)
assert not queries;raw=(B/'confirmation-expiry-finalization-r1.py').read_bytes();r={'status':'PASS actual pure mixed case/host manifest and checker-name/protocol argument builder','count':len(rows),'cases':rows,'source':{'file':'confirmation-expiry-finalization-r1.py','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()},'processQueries':queries,'scope':'Retained failed255 state only as fixture, host source/resultbundle synthetically rebound256; current schema command construction only. No native/currentchecker/realprocess/Release acceptance.','checkedAt':time.time()};p=B/'source257-finalizer-argument-controls-r1.json';assert not p.exists();p.write_text(json.dumps(r,indent=2)+'\n');print(r['status'],r['count'])
