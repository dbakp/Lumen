"""Compile/run exact extracted native barrier under host XCTest, with before/after fence."""
from pathlib import Path
import base64, gzip, hashlib, json, shutil, subprocess, time
B=Path(__file__).resolve().parent; R=B.parents[2]
source=R/'LumenUITests/LumenSmokeTests.swift'; controls=B/'source261-native-barrier-host-controls-r3.swift'
output=B/'source261-native-barrier-controls-r3.json'; assert not output.exists()
work=Path('/tmp/LumenRetainedBackendBarrier261R2'); assert work.is_dir() and not work.is_symlink()
sha=lambda data:hashlib.sha256(data).hexdigest()
before=source.read_bytes(); test_before=controls.read_bytes()
text=before.decode(); helper=text[text.index('\n/// Test-runner transport only.'):].encode()
unit=b'import Foundation\nimport XCTest\nimport CryptoKit\nimport Darwin\n'+helper+b'\n'+test_before
swift=work/'actual-native-helper-controls-r3.swift';assert not swift.exists();swift.write_bytes(unit)
platform=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-platform-path'],text=True).strip()
frameworks=str(Path(platform)/'Developer/Library/Frameworks')
binary=work/'native-barrier-controls-r3';assert not binary.exists()
command=['xcrun','swiftc','-swift-version','5','-module-cache-path',str(work/'ModuleCache.noindex'),'-F',frameworks,'-framework','XCTest','-Xlinker','-rpath','-Xlinker',frameworks,str(swift),'-o',str(binary)]
result={'status':'FAILED host native-helper controls','scope':'Exact extracted native transport helper under host macOS XCTest and real synthetic file controls. No iOS app/native/SDK-sourceReady acceptance.',
 'beforeSourceBytes':len(before),'beforeSourceSHA256':sha(before),'helperBytes':len(helper),'helperSHA256':sha(helper),'controlSourceBytes':len(test_before),'controlSourceSHA256':sha(test_before),'command':command,'availableBeforeBytes':shutil.disk_usage(R).free,'workDirectory':str(work)}
process=subprocess.Popen(command,cwd=R,stdout=subprocess.PIPE,stderr=subprocess.PIPE);out,err=process.communicate();result['compile']={'pid':process.pid,'exit':process.returncode,'stdout':base64.b64encode(out).decode(),'stderr':base64.b64encode(err).decode()}
if process.returncode==0:
 process=subprocess.Popen([str(binary)],cwd=R,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 try:out,err=process.communicate(timeout=75)
 except subprocess.TimeoutExpired:process.kill();out,err=process.communicate();result['runtimeTimeout']=True
 result['run']={'pid':process.pid,'exit':process.returncode,'stdout':base64.b64encode(out).decode(),'stderr':base64.b64encode(err).decode()}
 if process.returncode==0:
  result['controls']=json.loads(out);result['status']='PASS exact native helper extracted host controls'
after=source.read_bytes();result['afterSourceBytes']=len(after);result['afterSourceSHA256']=sha(after)
result['sourceBeforeAfterExact']=before==after and controls.read_bytes()==test_before;result['checkedAt']=time.time()
assert result['sourceBeforeAfterExact'];output.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],flush=True)
if result['status'].startswith('FAILED'):print(err.decode(errors='replace'),flush=True)
raise SystemExit(not result['status'].startswith('PASS'))
