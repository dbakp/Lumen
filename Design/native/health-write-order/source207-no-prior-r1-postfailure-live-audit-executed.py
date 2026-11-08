import json,pathlib,subprocess,plistlib,base64,hashlib,time,os,stat
p=pathlib.Path('Design/native/health-write-order');r=json.loads((p/'root-acquisition-no-prior-source207r1-latest-original-report.json').read_text());data=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container','AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481','com.dbakp.lumen','data'],text=True).strip());f=data/'Library/Preferences/com.dbakp.lumen.plist';observations=[]
for i in range(3):
 st=f.lstat();assert stat.S_ISREG(st.st_mode) and not f.is_symlink() and st.st_size<262144;values=plistlib.loads(f.read_bytes());fixed={}
 for key in r['initialFixed']:
  v=values.get(key);row={'actualType':type(v).__name__}
  if isinstance(v,bytes):row.update(base64=base64.b64encode(v).decode(),bytes=len(v),sha256=hashlib.sha256(v).hexdigest())
  elif isinstance(v,str):b=v.encode('utf-16-le');row.update(base64=base64.b64encode(b).decode(),bytes=len(b),sha256=hashlib.sha256(b).hexdigest())
  fixed[key]=row
 observations.append({'at':time.time(),'fileIdentity':{'device':st.st_dev,'inode':st.st_ino,'mtime_ns':st.st_mtime_ns,'size':st.st_size},'fixedKeys':fixed})
 if i<2:time.sleep(1)
latest=data/'tmp/Lumen-legacy-root-probe-report.json';raw=latest.read_bytes();(p/'root-acquisition-no-prior-source207r1-postfailure-app-report.json').write_bytes(raw)
paths={k:pathlib.Path(v) for k,v in r['paths'].items()};module={'__name__':'audit_import'};exec(compile((p/'health-legacy-root-acquisition-driver-r1.py').read_text(),str((p/'health-legacy-root-acquisition-driver-r1.py').resolve()),'exec'),module) if False else None
import importlib.util
spec=importlib.util.spec_from_file_location('rootdriver',p/'health-legacy-root-acquisition-driver-r1.py');driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver)
root=driver.live_tree(paths['root']);prior=driver.live_tree(paths['previous']);assert root==r['initialRoot'] and prior==r['initialPrevious'];assert not paths['moved'].exists() and not paths['movedPrevious'].exists()
out={'status':'Read-only actual postfailure preferences/root audit; no root-relocation or recovery observation','dataContainer':str(data),'observations':observations,'currentAndPriorExactPreparedTrees':True,'bothMovedPathsAbsent':True,'latestAppReportBytes':len(raw),'latestAppReportSHA256':hashlib.sha256(raw).hexdigest(),'latestAppPhase':json.loads(raw)['phase'],'noHostAckSent':not (data/'tmp/Lumen-legacy-root-probe-ack.json').exists(),'sourceUnchanged':True,'scope':'Only fixed known synthetickeys retained. No allplist copy, no write/query of phone or defaults. Later appearance would not prove a specific CFPreferences timing cause.','checkedAt':time.time()};(p/'source207-no-prior-r1-postfailure-live-audit.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
