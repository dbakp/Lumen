import json,gzip,hashlib,subprocess,time,shutil,base64
from pathlib import Path
repo=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen');base=repo/'Design/native/health-write-order';raw=Path('/tmp/LumenBatch44Checks');manifest=json.loads((base/'durable-source-r260.json').read_text());sha=lambda b:hashlib.sha256(b).hexdigest()
def verify():
 for group in ['files','fixtureInputs']:
  for name,r in manifest[group].items():
   p=repo/name;assert p.is_file() and not p.is_symlink();b=p.read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],name
verify()
# Require exact publication of all three current native navigation cases before build.
import importlib.util
spec=importlib.util.spec_from_file_location('current_release_driver',base/'retained-owner-driver-r3.py');driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver)
e=driver.module('retained-owner-evidence-r2.py');facts=e.preflight(base,e.SOURCE,driver.verify_source)
proof=json.loads((base/'source260-sheet-dismiss-exact-github.json').read_bytes());assert e.verify_checkpoint_facts(proof,facts,repo)
native_gate=driver.module('source260-native-release-gate-r1.py').require_native_checkpoint(base,repo,proof)
archive=json.loads(gzip.decompress((base/'durable-source-r260.json.gz').read_bytes()))
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(manifest[group])==set(archive[key])
 for name in manifest[group]:assert (archive[key][name].encode() if group=='files' else base64.b64decode(archive[key][name],validate=True))==(repo/name).read_bytes()
plan=json.loads((base/'health-current-release-source260-r1-plan.json').read_bytes())
assert manifest['source']==plan['source']=='durable-source-r260.json'
assert sha(Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen').read_bytes())==plan['debugPositiveSHA256']
assert not (base/'health-current-release-source260-r1-outcome.json').exists()
assert not (base/'health-current-release-source260-r1-audit.json').exists()
assert not (base/'source260-unsigned-release-r1-build.log.gz').exists()
assert shutil.disk_usage(repo).free>8*1024**3;log=raw/'Source260UnsignedReleaseR1.log';assert not log.exists()
command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Release','-destination','generic/platform=iOS','-derivedDataPath','/tmp/LumenBatch37Release','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-jobs','2','CODE_SIGNING_ALLOWED=NO','build']
with log.open('xb') as f:
 proc=subprocess.Popen(command,cwd=repo,stdout=f,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-i','-w',str(proc.pid)]);print('Current260 unsigned Release running PID',proc.pid,flush=True);code=proc.wait()
verify();assert e.strict_json_equal(e.preflight(base,e.SOURCE,driver.verify_source),facts);b=log.read_bytes();(base/'source260-unsigned-release-r1-build.log.gz').write_bytes(gzip.compress(b,mtime=0));out={'source':'durable-source-r260.json','buildExitCode':code,'buildPID':proc.pid,'command':command,'logBytes':len(b),'logSHA256':sha(b),'log':'source260-unsigned-release-r1-build.log.gz','checkedAt':time.time(),'availableBytes':shutil.disk_usage(repo).free,'status':'Compile passed; executable audit pending' if code==0 else 'FAILED compile; no Release acceptance','physicalDeviceActions':False,'nativePrerequisiteGate':native_gate,'nativePrerequisiteExactCommit':proof['commit'],'nativePrerequisiteProof':'source260-sheet-dismiss-exact-github.json','executionHelperSHA256':sha(Path(__file__).read_bytes())}
if code==0:
 auditlog=raw/'Source260UnsignedReleaseR1Audit.log';auditcommand=['python3',str(base/'health-current-release-source210-r1-auditor.py'),'--plan',str(base/'health-current-release-source260-r1-plan.json'),'--bundle','/tmp/LumenBatch37Release/Build/Products/Release-iphoneos/Lumen.app','--debug-bundle','/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app','--output',str(base/'health-current-release-source260-r1-audit.json')]
 with auditlog.open('xb') as f:r=subprocess.run(auditcommand,cwd=repo,stdout=f,stderr=subprocess.STDOUT)
 out['auditExitCode']=r.returncode;out['auditOutput']=auditlog.read_text();out['status']='PASS unsigned compilation and bounded executable/bundle audit' if r.returncode==0 else 'Compile passed; FAILED executable audit; no audit acceptance';code=r.returncode
(base/'health-current-release-source260-r1-outcome.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out),flush=True);raise SystemExit(code)
