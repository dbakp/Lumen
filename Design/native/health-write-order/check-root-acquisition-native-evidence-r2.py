"""Read-only retained+live audit. Never launches app/tests or changes simulator."""
import argparse,base64,gzip,hashlib,importlib.util,json,pathlib,plistlib,stat,subprocess,time
P=pathlib.Path(__file__).resolve().parent;REPO=P.parents[2];sha=lambda b:hashlib.sha256(b).hexdigest();read=lambda p:json.loads(pathlib.Path(p).read_text())
a=argparse.ArgumentParser();a.add_argument('--prefix',required=True);a.add_argument('--source',required=True);a.add_argument('--build',required=True);a.add_argument('--case',choices=['no-prior','with-prior','ordinary'],required=True);a.add_argument('--output',required=True);args=a.parse_args()
assert pathlib.Path(args.prefix).name==args.prefix and pathlib.Path(args.output).name==args.output
source=read(P/args.source);archive=json.loads(gzip.decompress((P/(args.source+'.gz')).read_bytes()));input_count=0
for group,archived in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(source[group])==set(archive[archived])
 for name,row in source[group].items():
  f=REPO/name;s=f.lstat();assert stat.S_ISREG(s.st_mode) and not f.is_symlink();b=f.read_bytes();assert len(b)==row['bytes'] and sha(b)==row['sha256']
  assert (archive[archived][name].encode() if group=='files' else base64.b64decode(archive[archived][name],validate=True))==b;input_count+=1
outcome=read(P/(args.prefix+'-outcome.json'));summary=read(P/(args.prefix+'-summary.json'));assert outcome['nativeExitCode']==outcome['driverExitCode']==0
expectation=outcome['expectation'];assert expectation in {'mutation','safe','control'}
assert (args.case=='ordinary')==(expectation=='control')
assert outcome['safetyAcceptance']==(expectation=='safe')
assert (summary['passedTests'],summary['failedTests'],summary['skippedTests'])==(1,0,0) and outcome['retention']['errors']==[]
prepared=read(P/(args.prefix+'-prepared.json'));observed=read(P/(args.prefix+'-observed.json'));latest=read(P/(args.prefix+'-latest-original-report.json'))
assert prepared['phase']=='prepared' and observed['phase']=='observed' and latest['phase']=='host-audited';assert len({x['runID'] for x in [prepared,observed,latest]})==1
assert {k:v for k,v in latest.items() if k!='phase'}=={k:v for k,v in observed.items() if k!='phase'}
rows=0
def payloads(v):
 global rows
 if isinstance(v,dict):
  if {'base64','bytes','sha256'}<=v.keys():
   b=base64.b64decode(v['base64'],validate=True);assert len(b)==v['bytes'] and sha(b)==v['sha256'];rows+=1
  for child in v.values():payloads(child)
 elif isinstance(v,list):
  for child in v:payloads(child)
for report in [prepared,observed,latest]:payloads(report)
build=read(P/args.build);assert build['source']==args.source and build['buildExit']==0
for phase,report in [('prepared',prepared),('observed',observed)]:
 proof=read(P/(args.prefix+'-'+phase+'-host-preack.json'));assert proof==outcome[phase]
 assert proof['sourceManifestSHA256']==sha((P/args.source).read_bytes()) and proof['buildReceiptSHA256']==sha((P/args.build).read_bytes())
 assert proof['originalReportSHA256']==sha((P/(args.prefix+'-'+phase+'.json')).read_bytes())
 for suffix in ['', '-immediately-before-ack']:
  samples=read(P/(args.prefix+'-'+phase+suffix+'-fixed-preferences-observations.json'));assert samples and samples[-1]['status']=='exact'
  for sample in samples:
   assert sample['runID']==report['runID'] and sample['nativeRunID']==report['runID'] and sample['nativePhase']==phase
   assert sample['nativeReportSHA256']==proof['originalReportSHA256']
   assert sample['status']=='exact' or (phase=='prepared' and not suffix and sample['status']=='missing')
   for key,value in sample['fixedKeys'].items():
    if value['actualType']=='NoneType':assert sample['status']=='missing'
    else:assert value['actualType']=='bytes' and base64.b64decode(value['base64'],validate=True)==b'{synthetic persisted legacy origin damaged'
for f,size,h in [(pathlib.Path(outcome['observed']['installedBinary']['path']),build['binaryBytes'],build['sha256']),(pathlib.Path(build['testBinary']),build['testBinaryBytes'],build['testBinarySHA256'])]:
 s=f.lstat();assert stat.S_ISREG(s.st_mode) and not f.is_symlink() and s.st_size==size and sha(f.read_bytes())==h
spec=importlib.util.spec_from_file_location('root_driver_readonly',P/'health-legacy-root-acquisition-driver-r1.py');driver=importlib.util.module_from_spec(spec);spec.loader.exec_module(driver)
paths={k:pathlib.Path(v) for k,v in observed['paths'].items()}
for field,path in [('finalRoot','root'),('finalPrevious','previous'),('movedRoot','moved'),('movedPrevious','movedPrevious')]:assert driver.live_tree(paths[path])==observed[field],field
assert sorted(x.name for x in paths['root'].parent.iterdir())==observed['siblingNamesAfter']
data_root=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container','AF849DEA-DF34-4B0E-9FC1-3E45DCBE8481','com.dbakp.lumen','data'],text=True).strip());f=data_root/'Library/Preferences/com.dbakp.lumen.plist';s=f.lstat();assert stat.S_ISREG(s.st_mode) and not f.is_symlink() and s.st_size<262144;values=plistlib.loads(f.read_bytes())
for key in ['lumen.health.meals.v1','lumen.health.workouts.v1']:assert type(values[key]) is bytes and values[key]==b'{synthetic persisted legacy origin damaged'
assert observed['movedRoot']==prepared['initialRoot'] and observed['initialFixed']==observed['finalFixed']
assert observed['traceBefore']==observed['traceAfter'] and observed['externalBefore']==observed['externalAfter']
if expectation=='safe':
 absent={'root':{'exists':False},'entries':{}}
 assert observed['rejected'] and not observed['didCommit'] and observed['finalRoot']==absent
 assert observed['notes'][0]['root']==observed['notes'][1]['root']==absent
 assert observed['notes'][1]['previous']==observed['notes'][0]['previous']==observed['finalPrevious']
 if args.case=='no-prior':assert observed['movedPrevious']==prepared['initialPrevious'] and observed['finalPrevious']==absent
 else:assert observed['movedPrevious']==absent and observed['finalPrevious']==prepared['initialPrevious']
elif args.case=='no-prior':
 assert observed['movedPrevious']==prepared['initialPrevious'] and observed['finalPrevious']=={'root':{'exists':False},'entries':{}}
 assert observed['rejected'] and not observed['didCommit'] and observed['finalRoot']['root']['exists'] and observed['finalRoot']['entries']=={}
 assert not observed['notes'][0]['root']['root']['exists'] and observed['notes'][1]['root']==observed['finalRoot']
elif args.case=='with-prior':
 assert observed['rejected'] and not observed['didCommit'] and observed['notes'][1]['root']==prepared['initialPrevious']==observed['finalRoot']
else:
 assert not observed['rejected'] and observed['didCommit']
 before=json.loads(base64.b64decode(prepared['journalBeforeBase64']));after=json.loads(base64.b64decode(observed['finalRoot']['entries']['health-write-intent.json']['base64']))
 assert before['owner']==after['owner'] and before['lifecycle']!=after['lifecycle'] and before['events']==after['events'] and len(after['events'])==1
bindings=0
for kind in ['png','json','manifest','other']:
 for row in read(P/(args.prefix+'-'+kind+'-attachments.json')):
  b=(P/row['file']).read_bytes();assert len(b)==row['bytes'] and sha(b)==row['sha256'];bindings+=1
report={'status':'PASS actual read-only frozen/archive/retained/live audit for declared API boundary; not broad product acceptance','source':args.source,'case':args.case,'expectation':expectation,'scopedSafeRejection':expectation=='safe','exactSourceAndArchiveInputs':input_count,'exactEmbeddedPayloadInstances':rows,'exactLiveTrees':4,'exactPersistentDataKeys':2,'exactRetainedAttachmentBindings':bindings,'actualNativePassed':1,'nativeHelperJSONCount':0,'scope':'No native/checker rerun of recovery, no source/provider/UI permission or broad timing credit. Full app protocol reports are host readbacks. Earlier prepared missing mechanism unproved. Current live facts cease to apply after next reset.','checkedAt':time.time()};(P/args.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
