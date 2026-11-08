"""Retain the actual unchanged R2 nonmixed native producer outcome; no phone actions."""
from pathlib import Path
import gzip,hashlib,importlib.util,json,shutil,subprocess,time,traceback
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');base=repo/'Design/native/health-write-order';raw=Path('/tmp/LumenBatch44Checks')
prefix='health-error-state-legacy-source216r2';stem='HealthErrorStateLegacySource216R2';target=base/'source216-normal-origin-data-r2-outcome.json';log=raw/'Source216NormalOriginDataR2Driver.log'
assert not target.exists() and not log.exists() and not (raw/(stem+'.xcresult')).exists()
assert shutil.disk_usage(repo).free>8*1024**3
source=json.loads((base/'durable-source-r216.json').read_bytes());driver=base/'health-legacy-origin-state-driver-r2.py';want=source['files'][str(driver.relative_to(repo))]
assert len(driver.read_bytes())==want['bytes'] and hashlib.sha256(driver.read_bytes()).hexdigest()==want['sha256']
command=['python3',str(driver),'--source','durable-source-r216.json','--build','health-mixed-ineligible-source216-r1-build.json','--case','legacy','--origin','data','--fault','missing','--trial','Source216R2']
outcome={'status':'RUNNING unchangednonmixedR2 actualproducer','source':'durable-source-r216.json','build':'health-mixed-ineligible-source216-r1-build.json','command':command,'prefix':prefix,'stem':stem,'started':time.time(),'nativeSummary':None,'driverExit':None,'physicalDeviceActions':False}
target.write_text(json.dumps(outcome,indent=2)+'\n')
with log.open('xb') as stream:
 process=subprocess.Popen(command,cwd=repo,stdout=stream,stderr=subprocess.STDOUT);outcome['processPID']=process.pid
 target.write_text(json.dumps(outcome,indent=2)+'\n');print('Actual216normalDataregression PID',process.pid,flush=True)
 code=process.wait()
outcome['driverExit']=code
try:
 data=log.read_bytes();name='source216-normal-origin-data-r2-driver.log.gz';(base/name).write_bytes(gzip.compress(data,mtime=0));outcome['driverLog']={'retained':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
 if code:
  # Independent per-peer salvage supplements the unchanged old producer's
  # failure path; no partial result can become a successful native claim.
  spec=importlib.util.spec_from_file_location('retainer',base/'retain-mixed-ineligible-results-r1.py');retainer=importlib.util.module_from_spec(spec);spec.loader.exec_module(retainer)
  outcome['failedProducerSalvage']=retainer.retain(base,raw,stem,prefix,'durable-source-r216.json')
 summarypath=base/(prefix+'-summary.json')
 if summarypath.exists():outcome['nativeSummary']=json.loads(summarypath.read_bytes())
 assert code==0
 assert outcome['nativeSummary'] is not None and [outcome['nativeSummary'][k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
 assert (base/(prefix+'-host-audit.json')).is_file()
 outcome['status']='PASS actual unchangedR2native1/0/0 andstrictnonmixedhostproducer; original/readonly/root/criticreviewpending'
except Exception:
 outcome['status']='FAILED or incompleteactualnormalregression; no acceptance';outcome['failure']=traceback.format_exc();raise
finally:
 outcome['finished']=time.time();target.write_text(json.dumps(outcome,indent=2)+'\n')
print(outcome['status'],flush=True)
