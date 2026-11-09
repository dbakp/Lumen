import json,gzip,hashlib,subprocess,time,shutil,base64
from pathlib import Path
p=Path('Design/native/health-write-order');raw=Path('/tmp/LumenBatch44Checks');m=json.loads((p/'durable-source-r260.json').read_text());sha=lambda b:hashlib.sha256(b).hexdigest()
def verify():
 for group in ['files','fixtureInputs']:
  for name,r in m[group].items():
   f=Path(name);assert not f.is_symlink();b=f.read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],name
verify()
assert m['source']=='durable-source-r260.json'
review_name='health-retained-review-owner-source260-round2-part181-source.json'
review=json.loads((p/review_name).read_bytes())
assert review['source']==m['source'] and review['sourceReady'] is True
proof=json.loads((p/'source260-source-exact-github.json').read_bytes())
assert proof['source']==m['source']
for ref in ['HEAD','origin/main']:
 assert subprocess.check_output(['git','rev-parse',ref],text=True).strip()==proof['commit']
proofs={r['file']:r for r in proof['proofs']}
for name in [review_name,'source260-root-preparation-r1.json']:
 f=p/name;r=proofs[str(f)];b=f.read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256']

plan=json.loads((p/'health-current-release-source260-r1-predeclared-plan.json').read_bytes())
assert plan['source']==m['source']
archive=json.loads(gzip.decompress((p/'durable-source-r260.json.gz').read_bytes()))
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(archive[key])
 for name in m[group]:assert (archive[key][name].encode() if key=='files' else base64.b64decode(archive[key][name],validate=True))==Path(name).read_bytes()
assert shutil.disk_usage(Path.cwd()).free>8*1024**3;log=raw/'Source260TargetChangeNativeBuildR1.log';assert not log.exists();command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','id=5C4C4A6C-4D9E-4181-8794-E3925C1A7EA7','-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-jobs','2','build-for-testing']
with log.open('xb') as out:
 proc=subprocess.Popen(command,stdout=out,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-i','-w',str(proc.pid)]);print('Current260nativebuild running PID',proc.pid,flush=True);code=proc.wait()
verify();b=log.read_bytes();name='source260-target-change-native-build-r1.log.gz';(p/name).write_bytes(gzip.compress(b,mtime=0));d={'status':'PASS simulator compile; currentnative runtime pending' if code==0 else 'FAILED current260native build; no runtime acceptance','source':'durable-source-r260.json','exitCode':code,'processPID':proc.pid,'command':command,'log':name,'logBytes':len(b),'logSHA256':sha(b),'checkedAt':time.time(),'availableBytes':shutil.disk_usage(Path.cwd()).free,'physicalDeviceActions':False}
if code==0:
 app=Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen');test=Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/LumenUITests-Runner.app/PlugIns/LumenUITests.xctest/LumenUITests');receipt={'source':'durable-source-r260.json','buildExit':0,'sha256':sha(app.read_bytes()),'binaryBytes':app.stat().st_size,'testBinary':str(test),'testBinarySHA256':sha(test.read_bytes()),'testBinaryBytes':test.stat().st_size,'sourceInputs':len(m['files']),'fixtureInputs':len(m['fixtureInputs']),'buildLog':name,'status':'Source260nativecompilePASS; Retainedowner/Settingslifetime/currentUIharness compiled; actual native runtime pending','checkedAt':time.time()};(p/'health-target-change-source260-r1-build.json').write_text(json.dumps(receipt,indent=2)+'\n');d['buildReceipt']='health-target-change-source260-r1-build.json'
(p/'source260-target-change-native-build-r1-outcome.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d),flush=True);raise SystemExit(code)
