"""Injected process enumeration/lifecycle controls; no actual process/device query."""
import copy,gzip,hashlib,importlib.util,json,subprocess,traceback
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('process_control_subject',BASE/'target-postrun-process-r1.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
PID=1972;EXE='/synthetic/Lumen.app/Lumen'
other=b'1 /sbin/launchd\n23 /bin/ps\n'
live=other+str(PID).encode()+b' '+EXE.encode()+b'\n'
cases=[('absent',[other],True,'absent'),('live',[live],True,'live'),
 ('reused-pid',[other+str(PID).encode()+b' /synthetic/Other.app/Other\n'],False,None),
 ('relaunched-new-pid',[other+b'999 '+EXE.encode()+b'\n'],False,None),
 ('extra-app-instance',[live+b'999 '+EXE.encode()+b'\n'],False,None),
 ('query-exit1',[b''],False,None),('empty-successful-query',[b''],False,None),
 ('malformed-row',[other+b'not-a-pid /synthetic/unknown\n'],False,None),
 ('duplicate-pid',[live+str(PID).encode()+b' '+EXE.encode()+b'\n'],False,None),
 ('invalid-utf8',[other+b'\xff\n'],False,None),('query-timeout',[other],False,None),
 ('protected-check-failed',[other],False,None),('live-lsof-failed',[live],False,None),
 ('live-to-absent',[live,other],False,None),('absent-to-live',[other,live],False,None),
 ('persistence-failed',[other],False,None),('oversized-stderr',[other],False,None),
 ('invalid-bound-pid',[other],False,None),('invalid-executable',[other],False,None)]
rows=[]
for name,outputs,wanted,mode in cases:
 sink={};clock=[0.0];queries=[];collects=[];lsofs=[];persists=[];write_count=[0]
 def persist():
  write_count[0]+=1
  if name=='persistence-failed' and write_count[0]==3:raise OSError('synthetic outcome persistence failure')
  persists.append(json.dumps(sink,sort_keys=True))
 def run(command,**options):
  assert command==['/bin/ps','-axo','pid=,comm='] and options=={'capture_output':True,'timeout':10}
  ordinal=len(queries);queries.append({'command':command,'options':options})
  if name=='query-timeout':raise subprocess.TimeoutExpired(command,10)
  stderr=b'synthetic query failure' if name=='query-exit1' else b'x'*16385 if name=='oversized-stderr' else b''
  return subprocess.CompletedProcess(command,1 if name=='query-exit1' else 0,outputs[min(ordinal,len(outputs)-1)],stderr)
 def collect(row,observed):
  collects.append(observed);row['syntheticProtectedCheck']='attempted'
  if name=='protected-check-failed':row['syntheticProtectedCheck']='changed';raise AssertionError('synthetic protected bytes changed')
  row['syntheticProtectedCheck']='exact synthetic comparator'
 def paths(row):
  lsofs.append(True);row['syntheticLiveOpenPaths']='attempted'
  if name=='live-lsof-failed':raise AssertionError('synthetic live lsof failure')
  row['syntheticLiveOpenPaths']='no synthetic case paths'
 try:
  m.audit('1972' if name=='invalid-bound-pid' else PID,'relative/Lumen' if name=='invalid-executable' else EXE,
   sink,persist,collect,paths,run=run,clock=lambda:clock[0],sleep=lambda dt:clock.__setitem__(0,clock[0]+dt))
  actual=True;error=None
 except BaseException:actual=False;error=traceback.format_exc()
 assert actual==wanted,name
 if wanted:
  assert sink['mode']==mode and len(sink['samples'])==len(collects)==2
  assert len(lsofs)==(2 if mode=='live' else 0)
 else:assert sink['status'].startswith('FAILED') and error
 rows.append({'case':name,'expectedAccept':wanted,'actualAccept':actual,'expectedMode':mode,'outcome':sink,'queries':queries,
  'collectModes':collects,'liveOpenPathCalls':len(lsofs),'persistCalls':write_count[0],'successfulPersistedSnapshots':len(persists),'error':error,
  'syntheticRawQueryOutputs':[x.decode('utf-8',errors='backslashreplace') for x in outputs]})
archive=BASE/'source231-process-controls-r1-fixtures.json.gz';data=json.dumps({'scope':'Injected synthetic process output and callbacks only; no actual process/OS/device query','trials':rows},sort_keys=True).encode();archive.write_bytes(gzip.compress(data,mtime=0))
r={'status':'PASS19isolated process/lifecycle/failure controls; no native/liveprocess proof','count':len(rows),'cases':[{k:x[k] for k in ['case','expectedAccept','actualAccept','expectedMode']} for x in rows],
 'runnerSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'fixtureArchive':archive.name,'decodedBytes':len(data),'decodedSHA256':hashlib.sha256(data).hexdigest(),'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
(BASE/'source231-process-controls-r1.json').write_text(json.dumps(r,indent=2)+'\n');print(r['status'])
