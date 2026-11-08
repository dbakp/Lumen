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

def retain_terminal(result,raw,prefix,evidence):
 errors=[];bindings={'png':[],'json':[],'manifest':[],'other':[]};summary=None
 if not result.exists():
  errors.append('Native result bundle missing; no summary/attachment acceptance')
 else:
  try:
   summary_bytes=subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)])
   (P/(prefix+'-summary.json')).write_bytes(summary_bytes);summary=json.loads(summary_bytes)
  except Exception as ex:errors.append('summary: '+repr(ex))
  destination=pathlib.Path(str(raw)+'-attachments');destination.mkdir(exist_ok=True)
  try:subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(destination)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,check=True)
  except Exception as ex:errors.append('attachment exporter: '+repr(ex))
  # A failed exporter may have already written valuable originals. Salvage
  # every eligible file independently; one broken entry cannot skip its peers.
  candidates=[]
  try:
   for directory,dirs,names in os.walk(destination,followlinks=False):
    for name in list(dirs):
     if (pathlib.Path(directory)/name).is_symlink():dirs.remove(name);errors.append('symlink directory skipped: '+name)
    candidates.extend(pathlib.Path(directory)/n for n in names)
  except Exception as ex:errors.append('enumerate partial attachments: '+repr(ex))
  for f in sorted(candidates):
   try:
    assert not f.is_symlink() and f.is_file(),str(f)
    kind='manifest' if f.name=='manifest.json' else f.suffix.lower().removeprefix('.')
    if kind not in bindings:kind='other'
    original=f.read_bytes();relative=str(f.relative_to(destination))
    target=P/(prefix+'-'+sha(relative.encode())[:12]+'-'+f.name)
    target.write_bytes(original)
    bindings[kind].append({'file':target.name,'bytes':len(original),'sha256':sha(original),'raw':str(f),'relativeExportPath':relative,'source':evidence['source'],'individuallyOpened':False,'role':'export metadata' if kind=='manifest' else 'original native attachment'})
    try:write(P/(prefix+'-'+kind+'-attachments.json'),bindings[kind])
    except Exception as ex:errors.append('incremental binding '+kind+': '+repr(ex))
   except Exception as ex:errors.append('attachment '+str(f)+': '+repr(ex))
 for kind,rows in bindings.items():
  try:write(P/(prefix+'-'+kind+'-attachments.json'),rows)
  except Exception as ex:errors.append('binding manifest '+kind+': '+repr(ex))
 # Bind each declared metadata entry to its retained original. Metadata is
 # exporter evidence, never a native helper result or a substitute screenshot.
 try:
  assert len(bindings['manifest'])==1,'exactly one original export manifest required'
  metadata=json.loads((P/bindings['manifest'][0]['file']).read_bytes());assert isinstance(metadata,list)
  declared=[]
  expected='LumenSmokeTests/testHealthLegacyRootAcquisition'+next(test for mode,test in MODES.values() if mode==evidence['mode'])
  for case in metadata:
   identifier=case['testIdentifier'].removesuffix('()')
   assert identifier in {expected,'LumenUITests.'+expected},identifier
   for attachment in case['attachments']:
    name=attachment['exportedFileName'];assert name and pathlib.Path(name).name==name and '/' not in name and '\\' not in name
    assert attachment['deviceId']==SIM
    declared.append(name)
  assert len(declared)==len(set(declared)),'duplicate declared export name'
  retained=[row['relativeExportPath'] for kind,rows in bindings.items() if kind!='manifest' for row in rows]
  assert sorted(retained)==sorted(declared),'declared versus retained original attachments differ'
  evidence['retainedMetadataIdentityAndInventoryExact']=True
 except Exception as ex:errors.append('attachment metadata identity/inventory: '+repr(ex))
 if summary is None:errors.append('required native summary unavailable')
 if not bindings['manifest']:errors.append('required original export metadata unavailable')
 if evidence.get('nativeExitCode')==0 and not bindings['png']:errors.append('required successful native screenshot unavailable')
 if evidence.get('nativeExitCode')==0:
  if summary is None or (summary.get('passedTests'),summary.get('failedTests'),summary.get('skippedTests'))!=(1,0,0):errors.append('native terminal summary is not declared1/0/0')
  if bindings['json']:errors.append('unexpected JSON nativehelper attachment; declared wrappers emit none, review required')
 evidence['retention']={'errors':errors,'originalPNGCount':len(bindings['png']),'nativeHelperJSONCount':len(bindings['json']),'exportMetadataCount':len(bindings['manifest']),'nativeHelperBoundary':'These API observation wrappers attach screenshots only. Full app protocol reports are host readbacks, not native-helper JSON.','summaryRetained':summary is not None,'partialSalvageAttemptedIndependently':True}
 return errors

def verify_fixed_keys(data_root,expected,phase,prefix,run_id,process,original_report_sha,allow_missing_wait=True,observation_tag=None):
 """Wait only for absent prepared fixture keys; present changes never retry."""
 assert set(expected)=={'lumen.health.meals.v1','lumen.health.workouts.v1'}
 for wanted in expected.values():
  assert wanted['type']=='data' and wanted['bytes']==42 and wanted['sha256']==sha(b'{synthetic persisted legacy origin damaged')
  assert base64.b64decode(wanted['base64'],validate=True)==b'{synthetic persisted legacy origin damaged'
 observations=[];deadline=time.monotonic()+(30 if phase=='prepared' and allow_missing_wait else 0)
 target=P/(prefix+'-'+(observation_tag or phase)+'-fixed-preferences-observations.json')
 while True:
  path=data_root/'Library/Preferences/com.dbakp.lumen.plist';row={'phase':phase,'runID':run_id,'observedAt':time.time(),'fixedKeys':{}};values={};file_missing=False
  try:
   s=path.lstat();row['fileIdentity']={'device':s.st_dev,'inode':s.st_ino,'bytes':s.st_size,'mtimeNS':s.st_mtime_ns}
   row['fileClassification']='oversized plist' if s.st_size>=262144 else 'regular bounded plist' if stat.S_ISREG(s.st_mode) else 'unsupported nonregular plist'
   assert stat.S_ISREG(s.st_mode) and not path.is_symlink() and s.st_size<262144,'plist must be bounded regular file'
   values=plistlib.loads(path.read_bytes())
  except FileNotFoundError:file_missing=True;row['fileMissing']=True
  except Exception as ex:
   row['readError']=repr(ex);observations.append(row);write(target,observations);raise
  try:
   native_bytes=(data_root/'tmp/Lumen-legacy-root-probe-report.json').read_bytes()
   native=json.loads(native_bytes);row.update(nativePhase=native.get('phase'),nativeRunID=native.get('runID'),nativeReportSHA256=sha(native_bytes))
  except Exception as ex:
   row['nativeReportReadError']=repr(ex);observations.append(row);write(target,observations);raise
  native_changed=native.get('runID')!=run_id or native.get('phase')!=phase or sha(native_bytes)!=original_report_sha
  missing=False;changed=False
  for key,wanted in expected.items():
   assert key in {'lumen.health.meals.v1','lumen.health.workouts.v1'}
   value=values.get(key);fact={'actualType':type(value).__name__};row['fixedKeys'][key]=fact
   if key not in values:missing=True;continue
   if type(value) is bytes:
    fact.update(bytes=len(value),sha256=sha(value),base64=base64.b64encode(value).decode(),rawEncoding='data')
    changed=changed or value!=base64.b64decode(wanted['base64'],validate=True)
   else:
    changed=True
    if isinstance(value,str):
     raw=value.encode('utf-16-le',errors='surrogatepass');assert len(raw)<=524288
     fact.update(bytes=len(raw),sha256=sha(raw),base64=base64.b64encode(raw).decode(),rawEncoding='stringUTF16LE')
    else:fact['classification']='unsupported property-list type'
  row['status']='changed' if changed else 'missing' if missing or file_missing else 'exact'
  observations.append(row);write(target,observations)
  assert not native_changed,'native original report/runID/phase changed during fixed preferences check'
  assert not changed,'present fixed preference type/bytes changed; no retry permitted'
  if not missing and not file_missing:return observations
  assert phase=='prepared' and allow_missing_wait,'strict boundary fixed preference missing; no wait permitted'
  assert process.poll() is None,'native producer ended before prepared fixed keys became durable'
  assert row['nativePhase']=='prepared' and row['nativeRunID']==run_id
  if time.monotonic()>=deadline:raise TimeoutError('prepared fixed preferences still absent after bounded30second observation')
  time.sleep(.25)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',required=True);ap.add_argument('--build',required=True);ap.add_argument('--case',choices=MODES,required=True);ap.add_argument('--trial',required=True);ap.add_argument('--expect',choices=['mutation','safe','control'],required=True);a=ap.parse_args()
 assert a.trial.isalnum();mode,test=MODES[a.case];assert (a.case=='ordinary')==(a.expect=='control')
 manifest_bytes=(P/a.source).read_bytes();build_bytes=(P/a.build).read_bytes();m=json.loads(manifest_bytes);build=json.loads(build_bytes);assert build['source']==a.source and build['buildExit']==0;manifest_verify(m)
 testbin=pathlib.Path(build['testBinary']);app=testbin.parents[3]/'Lumen.app/Lumen'
 for f,size,h in [(app,build['binaryBytes'],build['sha256']),(testbin,build['testBinaryBytes'],build['testBinarySHA256'])]:assert f.stat().st_size==size and sha(f.read_bytes())==h
 prefix='root-acquisition-'+a.case+'-'+a.trial.lower();raw=pathlib.Path('/tmp/LumenBatch44Checks')/('RootAcquisition'+test+a.trial);assert not raw.with_suffix('.log').exists() and not raw.with_suffix('.xcresult').exists()
 start=time.time();evidence={'source':a.source,'mode':mode,'expectation':a.expect,'startedAt':start,'localIdentityPreflight':True,'safetyAcceptance':False}
 log=raw.with_suffix('.log');result=raw.with_suffix('.xcresult');process=None;error=None;data_root=None;selected_run_id=None
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
     report=json.loads(raw_report)
    except (FileNotFoundError,subprocess.CalledProcessError,json.JSONDecodeError) as discovery_error:
     # Retry only initial discovery. Once a fresh run is known, even a later
     # report/parse/container error is an operational failure, never a retry.
     if selected_run_id is not None:raise
     evidence.setdefault('initialDiscoveryErrors',[]).append({'at':time.time(),'error':repr(discovery_error)})
     assert len(evidence['initialDiscoveryErrors'])<=3200
     write(P/(prefix+'-initial-discovery-errors.json'),evidence['initialDiscoveryErrors'])
     if process.poll() is not None:break
     data_root=None;time.sleep(.15);continue
    assert report['mode']==mode
    uuid.UUID(report['runID'])
    if selected_run_id is None:selected_run_id=report['runID']
    assert report['runID']==selected_run_id
    if 'prepared' in evidence:assert report['runID']==evidence['prepared']['runID']
    phase=report['phase']
    assert phase in {'prepared','observed','host-audited','failed'}
    if phase=='prepared':assert 'observed' not in seen,'native phase regressed after observation'
    if phase=='observed':assert 'prepared' in seen,'observed phase without actual prepared acknowledgement'
    if phase=='host-audited':assert seen=={'prepared','observed'}
    if phase in seen:assert sha(raw_report)==evidence[phase]['originalReportSHA256'],'immutable known phase report changed'
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
     fixed_observations=verify_fixed_keys(data_root,report['initialFixed'],phase,prefix,report['runID'],process,sha(raw_report))
     # Recheck the complete phase boundary after any prepared-only wait.
     current_report=read(report_file);assert current_report['runID']==report['runID'] and current_report['phase']==phase
     assert report_file.read_bytes()==raw_report,'immutable prepared/observed report changed during host checks'
     assert installed.stat().st_size==build['binaryBytes'] and sha(installed.read_bytes())==build['sha256']
     for reportkey,pathkey in ([('initialRoot','root'),('initialPrevious','previous')] if phase=='prepared' else [('finalRoot','root'),('finalPrevious','previous'),('movedRoot','moved'),('movedPrevious','movedPrevious')]):assert live_tree(paths[pathkey])==report[reportkey],reportkey
     if phase=='prepared':
      assert not live_tree(paths['moved'])['root']['exists'] and not live_tree(paths['movedPrevious'])['root']['exists']
      assert not any(x.name.startswith(('LumenData.restore-','LumenData.retired-','LumenData.discovery-')) for x in paths['root'].parent.iterdir())
      assert report['leaseReady']==(a.case!='ordinary')
     (P/(prefix+'-'+phase+'.json')).write_bytes(raw_report)
     if phase=='observed':
      assert not any(x.name.startswith(('LumenData.restore-','LumenData.retired-','LumenData.discovery-')) for x in paths['root'].parent.iterdir()), 'unfinished stage/retired/discovery'
      assess_observed(report,a,evidence)
      manifest_verify(m)
     manifest_verify(m);assert (P/a.source).read_bytes()==manifest_bytes and (P/a.build).read_bytes()==build_bytes
     verify_fixed_keys(data_root,report['initialFixed'],phase,prefix,report['runID'],process,sha(raw_report),allow_missing_wait=False,observation_tag=phase+'-immediately-before-ack')
     final_installed_bytes=installed.read_bytes();assert len(final_installed_bytes)==build['binaryBytes'] and sha(final_installed_bytes)==build['sha256']
     evidence[phase]={'payloadRows':rows,'installedIdentity':True,'liveTreesAndFixedDataExact':True,'runID':report['runID'],'originalReportSHA256':sha(raw_report),'sourceManifestSHA256':sha(manifest_bytes),'buildReceiptSHA256':sha(build_bytes),'installedBinary':{'path':str(installed),'bytes':len(final_installed_bytes),'sha256':sha(final_installed_bytes)},'checkedAt':time.time()}
     write(P/(prefix+'-'+phase+'-host-preack.json'),evidence[phase]);seen.add(phase)
     write(data_root/'tmp/Lumen-legacy-root-probe-ack.json',{'runID':report['runID'],'phase':phase})
    if process.poll() is not None:break
    time.sleep(.15)
   else:raise TimeoutError('bounded native observation')
  evidence['nativeExitCode']=process.wait();assert evidence['nativeExitCode']==0 and seen=={'prepared','observed'},evidence
  manifest_verify(m);evidence['status']='PASS declared observation/expectation only';evidence['driverExitCode']=0
 except Exception as ex:
  error=repr(ex);evidence.update(status='FAILED observation or expectation; no acceptance',error=error,driverExitCode=1)
  write(P/(prefix+'-host-failure.json'),{'error':error,'phase':'host gate failed; no further acknowledgement','nativePID':process.pid if process else None,'at':time.time()})
  if process is not None and process.poll() is None:
   # Keep XCTest alive so the app's own unacknowledged protocol can fail and
   # produce a complete failure result. Never acknowledge a failed host gate.
   print('Host gate failed; awaiting bounded native failure finalization without acknowledgement',flush=True)
   until=time.monotonic()+180;finalization_hashes=set();evidence['failureFinalizationReports']=[]
   def salvage_app_report():
    try:
     if data_root is None:return
     f=data_root/'tmp/Lumen-legacy-root-probe-report.json';s=f.lstat();assert stat.S_ISREG(s.st_mode) and not f.is_symlink() and 0<s.st_size<=16*1024**2 and s.st_mtime>=start
     data=f.read_bytes();h=sha(data)
     if h in finalization_hashes:return
     assert len(finalization_hashes)<16,'bounded finalization reports exceeded'
     finalization_hashes.add(h);target=P/(prefix+'-failure-finalization-'+str(len(finalization_hashes))+'.json');target.write_bytes(data)
     facts={'file':target.name,'bytes':len(data),'sha256':h,'observedAt':time.time()};evidence['failureFinalizationReports'].append(facts)
     write(P/(prefix+'-failure-finalization-reports.json'),evidence['failureFinalizationReports'])
     parsed=json.loads(data);assert parsed['mode']==mode
     if selected_run_id is not None:assert parsed['runID']==selected_run_id
    except Exception as ex:evidence.setdefault('failureFinalizationReadErrors',[]).append(repr(ex))
   while process.poll() is None and time.monotonic()<until:
    salvage_app_report();time.sleep(.25)
   salvage_app_report()
   if process.poll() is None:
    evidence['forcedTerminationAfterGrace']=True;process.terminate()
    try:process.wait(timeout=30)
    except subprocess.TimeoutExpired:process.kill();process.wait(timeout=10)
   else:evidence['nativeFinalizedNaturallyAfterHostFailure']=True
 finally:
  if process is not None:evidence['nativeExitCode']=process.poll()
  try:retention_errors=retain_terminal(result,raw,prefix,evidence)
  except Exception as ex:retention_errors=['terminal salvage failure: '+repr(ex)];evidence['retention']={'errors':retention_errors}
  try:
   assert log.exists(),'native log missing'
   b=log.read_bytes();(P/(prefix+'.log.gz')).write_bytes(gzip.compress(b,mtime=0));evidence.update(logBytes=len(b),logSHA256=sha(b))
  except Exception as ex:retention_errors.append('log retention: '+repr(ex));evidence['logRetentionError']=repr(ex)
  if retention_errors:error=error or 'Native retention incomplete';evidence.update(status='FAILED evidence retention; no acceptance',driverExitCode=1,safetyAcceptance=False)
  evidence['finishedAt']=time.time();write(P/(prefix+'-outcome.json'),evidence);print(json.dumps(evidence),flush=True)
 return 1 if error else 0
if __name__=='__main__':raise SystemExit(main())
