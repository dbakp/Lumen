#!/usr/bin/env python3
"""Dedicated synthetic simulator API observation; native observation != safety PASS."""
import argparse,base64,gzip,hashlib,json,os,pathlib,plistlib,stat,subprocess,time,uuid
P=pathlib.Path(__file__).resolve().parent; REPO=P.parents[2]
SIM='AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481'
MODES={'no-prior':('legacy-root-missing-no-prior','NoPrior'),'with-prior':('legacy-root-missing-with-prior','WithPrior'),'ordinary':('ordinary-root-missing-pending-removal-control','Ordinary')}
sha=lambda b:hashlib.sha256(b).hexdigest()
def read(p):return json.loads(pathlib.Path(p).read_text())
def write(p,d):pathlib.Path(p).write_text(json.dumps(d,indent=2)+'\n')
def cmd(*args):return subprocess.check_output(args,text=True).strip()
def manifest_verify(m):
 for group in ['files','fixtureInputs']:
  for n,r in m[group].items():
   f=REPO/n;assert not f.is_symlink();b=f.read_bytes();assert len(b)==r['bytes'] and sha(b)==r['sha256'],n

def live_tree(root):
 def facts(f):
  try:s=f.lstat()
  except FileNotFoundError:return {'exists':False}
  return {'exists':True,'device':s.st_dev,'inode':s.st_ino,'mode':s.st_mode,'size':s.st_size,'mtimeSeconds':s.st_mtime_ns//10**9,'mtimeNanos':s.st_mtime_ns%10**9}
 r=facts(root);entries={};total=0
 if r['exists']:
  assert stat.S_ISDIR(r['mode'])
  def walk(d,prefix=''):
   nonlocal total
   for f in sorted(d.iterdir()):
    row=facts(f);n=prefix+f.name
    assert stat.S_ISDIR(row['mode']) or stat.S_ISREG(row['mode']),n
    if stat.S_ISREG(row['mode']):
     assert row['size']<=262144;b=f.read_bytes();total+=len(b);assert total<=2097152
     row.update(base64=base64.b64encode(b).decode(),bytes=len(b),sha256=sha(b))
    entries[n]=row
    if stat.S_ISDIR(row['mode']):walk(f,n+'/')
  walk(root)
 return {'root':r,'entries':entries}
def exact_payload_rows(value):
 count=0
 if isinstance(value,dict):
  if {'base64','bytes','sha256'}<=value.keys():
   b=base64.b64decode(value['base64'],validate=True);assert len(b)==value['bytes'] and sha(b)==value['sha256'];count+=1
  for x in value.values():count+=exact_payload_rows(x)
 elif isinstance(value,list):
  for x in value:count+=exact_payload_rows(x)
 return count

def assess_observed(r,a,evidence):
 initial=r['initialRoot']; prior=r['initialPrevious'];absent={'root':{'exists':False},'entries':{}}
 assert r['movedRoot']==initial and r['initialFixed']==r['finalFixed']
 assert r['traceBefore']==r['traceAfter'] and r['externalBefore']==r['externalAfter']
 assert [n['phase'] for n in r['notes']]==['before-root-acquisition','after-root-acquisition']
 before,after=r['notes'];assert before['root']==absent
 if a.case=='no-prior':assert before['previous']==absent and r['movedPrevious']==prior
 else:assert before['previous']==prior and r['movedPrevious']==absent
 assert not any(n.startswith(('LumenData.restore-','LumenData.retired-','LumenData.discovery-')) for n in r['siblingNamesAfter'])
 if a.expect=='safe':
  assert after['root']==absent and r['finalRoot']==absent
  assert after['previous']==before['previous']==r['finalPrevious']
  assert r['rejected'] and not r['didCommit'];evidence['safetyAcceptance']=True
  return
 assert after['previous']==absent
 if a.case=='no-prior':
  assert after['root']['root']['exists'] and after['root']['entries']=={}
  assert r['finalRoot']==after['root'] and r['finalPrevious']==absent
  assert r['rejected'] and not r['didCommit']
  evidence.update(observedRootMutation=True,baselineDefectObserved=True,acquisitionTransition='absent→new empty root; movedcurrent/prior exact')
  return
 assert after['root']==prior, 'actual prior identity/bytes restored at wrapper acquisition'
 assert r['finalPrevious']==absent
 if a.case=='with-prior':
  assert r['finalRoot']==prior and r['rejected'] and not r['didCommit']
  evidence.update(observedRootMutation=True,baselineDefectObserved=True,acquisitionTransition='absent→exact restored prior; movedcurrent exact')
  return
 assert not r['rejected'] and r['didCommit']
 entries=r['finalRoot']['entries'];original=prior['entries']
 def data(n):return base64.b64decode(entries[n]['base64'],validate=True)
 before_journal=json.loads(base64.b64decode(r['journalBeforeBase64'],validate=True));after_journal=json.loads(data('health-write-intent.json'))
 assert before_journal['owner']==after_journal['owner'] and before_journal['lifecycle']!=after_journal['lifecycle']
 assert before_journal['events']==after_journal['events'] and len(after_journal['events'])==1 and after_journal['events'][0]['action']=='delete'
 assert data('workouts.json')==b'[]'
 # Every old ordinary file/directory is covered. Raw comparison is intentional;
 # report a failure rather than silently excluding context or key-order changes.
 for n,row in original.items():
  assert n in entries,n
  if n not in {'workouts.json','health-write-intent.json'} and 'base64' in row:assert entries[n]['base64']==row['base64'],n
 private=[n for n in entries if n.startswith('.health-recovery/') and n.endswith('/manifest.json')]
 assert len(private)==1 and not any(n.startswith('.health-recovery') for n in original)
 base=private[0].removesuffix('/manifest.json');import uuid;uuid.UUID(base.split('/')[1])
 manifest=json.loads(data(private[0]));assert manifest['version']==1 and manifest['domains']==['workouts'] and manifest['photos'] is False and manifest['intent'] is True and not manifest.get('legacyOrigins')
 assert data(base+'/workouts.json')==base64.b64decode(original['workouts.json']['base64'],validate=True)
 assert data(base+'/device-intent.json')==base64.b64decode(r['journalBeforeBase64'],validate=True)
 receipts=[n for n in entries if n.startswith('.health-recovery-history/') and n.endswith('.json')];assert len(receipts)==1
 receipt=json.loads(data(receipts[0]));assert set(receipt)=={'source','domains','recordDigests','photoDigests','recoveredAt'}
 assert receipt['source']=='reviewed-backup' and receipt['domains']==['workouts'] and receipt['recordDigests']=={'workouts.json':sha(b'[]')} and receipt['photoDigests']=={}
 allowed=set(original)|{'.health-recovery',base,base+'/manifest.json',base+'/workouts.json',base+'/device-intent.json','.health-recovery-history',receipts[0]}
 assert set(entries)==allowed, sorted(set(entries)^allowed)
 evidence.update(ordinaryPendingDeletionPreserved=True,completeFinalTreeAndReceipt=True,acquisitionTransition='absent→exact restored prior before original intent read; committed selected empty workouts')

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--build',required=True);ap.add_argument('--case',choices=MODES,required=True);ap.add_argument('--trial',required=True);ap.add_argument('--expect',choices=['mutation','safe','control'],required=True);a=ap.parse_args()
 assert a.trial.isalnum();mode,test=MODES[a.case];assert (a.case=='ordinary')==(a.expect=='control')
 m=read(P/a.source);build=read(P/a.build);assert build['source']==a.source and build['buildExit']==0;manifest_verify(m)
 testbin=pathlib.Path(build['testBinary']);app=testbin.parents[3]/'Lumen.app/Lumen'
 for f,size,h in [(app,build['binaryBytes'],build['sha256']),(testbin,build['testBinaryBytes'],build['testBinarySHA256'])]:assert f.stat().st_size==size and sha(f.read_bytes())==h
 prefix='root-acquisition-'+a.case+'-'+a.trial.lower();raw=pathlib.Path('/tmp/LumenBatch44Checks')/('RootAcquisition'+test+a.trial);assert not raw.with_suffix('.log').exists() and not raw.with_suffix('.xcresult').exists()
 start=time.time();evidence={'source':a.source,'mode':mode,'expectation':a.expect,'startedAt':start,'localIdentityPreflight':True,'safetyAcceptance':False}
 log=raw.with_suffix('.log');result=raw.with_suffix('.xcresult');process=None;error=None
 try:
  with log.open('xb') as out:
   command=['xcodebuild','-project','Lumen.xcodeproj','-scheme','Lumen','-configuration','Debug','-destination','id='+SIM,'-derivedDataPath','/tmp/LumenBatch37Simulator','-clonedSourcePackagesDirPath','/tmp/LumenBatch37Packages','-disableAutomaticPackageResolution','-parallel-testing-enabled','NO','-maximum-concurrent-test-simulator-destinations','1','-resultBundlePath',str(result),'-only-testing:LumenUITests/LumenSmokeTests/testHealthLegacyRootAcquisition'+test,'test-without-building']
   process=subprocess.Popen(command,cwd=REPO,stdout=out,stderr=subprocess.STDOUT);evidence.update(pid=process.pid,command=command);print('Root observation producer PID',process.pid,flush=True)
   data_root=None;seen=set();deadline=time.time()+480
   while time.time()<deadline:
    try:
     if data_root is None:data_root=pathlib.Path(cmd('xcrun','simctl','get_app_container',SIM,'com.dbakp.lumen','data'))
     report_file=data_root/'tmp/Lumen-legacy-root-probe-report.json'
     if report_file.stat().st_mtime<start:raise FileNotFoundError()
     raw_report=report_file.read_bytes();(P/(prefix+'-latest-original-report.json')).write_bytes(raw_report)
     evidence['latestOriginalReport']={'bytes':len(raw_report),'sha256':sha(raw_report)}
     report=json.loads(raw_report);assert report['mode']==mode
     uuid.UUID(report['runID'])
     if 'prepared' in evidence:assert report['runID']==evidence['prepared']['runID']
     phase=report['phase']
     write(P/(prefix+'-latest-report.json'),report)
     if phase=='failed':raise AssertionError('Native probe failed; full original report retained')
     if phase in ['prepared','observed'] and phase not in seen:
      installed=pathlib.Path(cmd('xcrun','simctl','get_app_container',SIM,'com.dbakp.lumen','app'))/'Lumen';assert installed.stat().st_size==build['binaryBytes'] and sha(installed.read_bytes())==build['sha256']
      paths={k:pathlib.Path(v) for k,v in report['paths'].items()}
      expected=pathlib.Path(cmd('xcrun','simctl','get_app_container',SIM,'com.dbakp.lumen','group.com.dbakp.lumen'))/'LumenData'
      assert set(paths)=={'root','previous','moved','movedPrevious'} and paths['root'].resolve()==expected.resolve()
      assert paths['previous']==paths['root'].with_suffix('.previous')
      assert paths['moved']==paths['root'].parent/('LumenData.legacy-root-probe-'+report['runID'])
      assert paths['movedPrevious']==paths['root'].parent/('LumenData.legacy-prior-probe-'+report['runID'])
      rows=exact_payload_rows(report)
      for reportkey,pathkey in ([('initialRoot','root'),('initialPrevious','previous')] if phase=='prepared' else [('finalRoot','root'),('finalPrevious','previous'),('movedRoot','moved'),('movedPrevious','movedPrevious')]):assert live_tree(paths[pathkey])==report[reportkey],reportkey
      plist=plistlib.loads((data_root/'Library/Preferences/com.dbakp.lumen.plist').read_bytes())
      for key,row in report['initialFixed'].items():assert type(plist[key]) is bytes and plist[key]==base64.b64decode(row['base64'],validate=True)
      if phase=='prepared':
       assert not live_tree(paths['moved'])['root']['exists'] and not live_tree(paths['movedPrevious'])['root']['exists']
       assert not any(x.name.startswith(('LumenData.restore-','LumenData.retired-','LumenData.discovery-')) for x in paths['root'].parent.iterdir())
       assert report['leaseReady']==(a.case!='ordinary')
      (P/(prefix+'-'+phase+'.json')).write_bytes(raw_report)
      if phase=='observed':
       assert not any(x.name.startswith(('LumenData.restore-','LumenData.retired-','LumenData.discovery-')) for x in paths['root'].parent.iterdir()), 'unfinished stage/retired/discovery'
       assess_observed(report,a,evidence)
       manifest_verify(m)
      evidence[phase]={'payloadRows':rows,'installedIdentity':True,'liveTreesAndFixedDataExact':True,'runID':report['runID']};seen.add(phase)
      write(data_root/'tmp/Lumen-legacy-root-probe-ack.json',{'runID':report['runID'],'phase':phase})
     if process.poll() is not None:break
    except (FileNotFoundError,subprocess.CalledProcessError,json.JSONDecodeError):data_root=None
    time.sleep(.15)
   else:raise TimeoutError('bounded native observation')
  evidence['nativeExitCode']=process.wait();assert evidence['nativeExitCode']==0 and seen=={'prepared','observed'},evidence
  summary=json.loads(cmd('xcrun','xcresulttool','get','test-results','summary','--path',str(result)));write(P/(prefix+'-summary.json'),summary);assert summary['passedTests']==1 and summary['failedTests']==0 and summary['skippedTests']==0
  manifest_verify(m);evidence['status']='PASS declared observation/expectation only';evidence['driverExitCode']=0
 except Exception as ex:
  error=repr(ex);evidence.update(status='FAILED observation or expectation; no acceptance',error=error,driverExitCode=1)
  if process is not None and process.poll() is None:process.terminate();process.wait(timeout=30)
 finally:
  if process is not None:evidence['nativeExitCode']=process.poll()
  if result.exists():
   try:
    summary=json.loads(cmd('xcrun','xcresulttool','get','test-results','summary','--path',str(result)));write(P/(prefix+'-summary.json'),summary)
   except Exception as ex:evidence['summaryExportError']=repr(ex)
   for kind in ['png','json']:
    destination=pathlib.Path(str(raw)+'-attachments');destination.mkdir(exist_ok=True)
    try:
     if kind=='png':subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(destination)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,check=True)
     bindings=[]
     for f in sorted(destination.rglob('*')):
      if f.is_file() and not f.is_symlink() and f.suffix.lower()=='.'+kind and f.name!='manifest.json':
       target=P/(prefix+'-'+f.name);target.write_bytes(f.read_bytes());bindings.append({'file':target.name,'bytes':target.stat().st_size,'sha256':sha(target.read_bytes()),'raw':str(f),'individuallyOpened':False})
     write(P/(prefix+'-'+kind+'-attachments.json'),bindings)
    except Exception as ex:evidence[kind+'AttachmentExportError']=repr(ex)
  if log.exists():b=log.read_bytes();(P/(prefix+'.log.gz')).write_bytes(gzip.compress(b,mtime=0));evidence.update(logBytes=len(b),logSHA256=sha(b))
  if any(k.endswith('ExportError') for k in evidence):error=error or 'Native retention incomplete';evidence.update(status='FAILED evidence retention; no acceptance',driverExitCode=1,safetyAcceptance=False)
  evidence['finishedAt']=time.time();write(P/(prefix+'-outcome.json'),evidence);print(json.dumps(evidence),flush=True)
 return 1 if error else 0
if __name__=='__main__':raise SystemExit(main())
