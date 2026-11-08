import json,gzip,hashlib,subprocess,time,shutil
from pathlib import Path
p=Path('Design/native/health-write-order');raw=Path('/tmp/LumenBatch44Checks');m=json.loads((p/'durable-source-r221.json').read_text());sha=lambda b:hashlib.sha256(b).hexdigest()
def verify():
 for group in ['files','fixtureInputs']:
  for name,r in m[group].items():
   f=Path(name);assert not f.is_symlink();b=f.read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],name
verify();assert shutil.disk_usage(Path.cwd()).free>8*1024**3;log=raw/'Source221SettingsErasureNativeBuildR1.log';assert not log.exists();command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','id=AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481','-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-jobs','2','build-for-testing']
with log.open('xb') as out:
 proc=subprocess.Popen(command,stdout=out,stderr=subprocess.STDOUT);subprocess.Popen(['caffeinate','-i','-w',str(proc.pid)]);print('Current221nativebuild running PID',proc.pid,flush=True);code=proc.wait()
verify();b=log.read_bytes();name='source221-settings-erasure-native-build-r1.log.gz';(p/name).write_bytes(gzip.compress(b,mtime=0));d={'status':'PASS simulator compile; currentnative runtime pending' if code==0 else 'FAILED current221native build; no runtime acceptance','source':'durable-source-r221.json','exitCode':code,'processPID':proc.pid,'command':command,'log':name,'logBytes':len(b),'logSHA256':sha(b),'checkedAt':time.time(),'availableBytes':shutil.disk_usage(Path.cwd()).free,'physicalDeviceActions':False}
if code==0:
 app=Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen');test=Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/LumenUITests-Runner.app/PlugIns/LumenUITests.xctest/LumenUITests');receipt={'source':'durable-source-r221.json','buildExit':0,'sha256':sha(app.read_bytes()),'binaryBytes':app.stat().st_size,'testBinary':str(test),'testBinarySHA256':sha(test.read_bytes()),'testBinaryBytes':test.stat().st_size,'sourceInputs':len(m['files']),'fixtureInputs':len(m['fixtureInputs']),'buildLog':name,'status':'Source221nativecompilePASS; GuardedSettingsresetobserver/currentUIharness compiled; actual native runtime pending','checkedAt':time.time()};(p/'health-settings-erasure-source221-r1-build.json').write_text(json.dumps(receipt,indent=2)+'\n');d['buildReceipt']='health-settings-erasure-source221-r1-build.json'
(p/'source221-settings-erasure-native-build-r1-outcome.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d),flush=True);raise SystemExit(code)
