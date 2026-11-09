"""Root host-only source/current-case pair binding, including explicit control qualifications."""
from pathlib import Path
import base64,gzip,hashlib,importlib.util,json,subprocess,time
B=Path(__file__).resolve().parent;R=B.parents[2];load=lambda n:json.loads((B/n).read_bytes());sha=lambda x:hashlib.sha256(x).hexdigest()
m=load('durable-source-r256.json');a=json.loads(gzip.decompress((B/'durable-source-r256.json.gz').read_bytes()));old=load('durable-source-r255.json');count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  raw=(R/n).read_bytes();assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];count+=1
 for n,f in old[group].items():assert m[group][n]==f,n
assert count==977
plan=load('source256-host-completion-separation-r1-plan.json');assert plan['source']==m['source'] and plan['caseSource']=='durable-source-r255.json' and plan['build']=='health-target-change-source255-r1-build.json'
spec=importlib.util.spec_from_file_location('root_current_pair_evidence',B/'confirmation-lifecycle-evidence-r1.py');E=importlib.util.module_from_spec(spec);spec.loader.exec_module(E);inputs=E.h.verify_inputs(plan['caseSource'],plan['build'])
receipt=load(plan['build']);test=Path(receipt['testBinary']).read_bytes();assert len(test)==receipt['testBinaryBytes'] and sha(test)==receipt['testBinarySHA256'];assert inputs['app']['sha256']==receipt['sha256']
# Git source comparison is intentionally read-only. No build/device/process query.
command=['git','diff','--exit-code','62ed04b1638ef676f8ebd1199c3bc99195a2c74b','--','Lumen','Shared','LumenUITests','Lumen.xcodeproj'];result=subprocess.run(command,cwd=R,capture_output=True);assert result.returncode==0 and not result.stdout and not result.stderr
untracked=subprocess.check_output(['git','ls-files','--others','--exclude-standard','--','Lumen','Shared','LumenUITests','Lumen.xcodeproj'],cwd=R);assert not untracked
for file,countwanted,field in [('source256-host-caller-controls-r3.json',7,None),('source256-checker-schema-controls-r2.json',26,None),('source256-finalizer-argument-controls-r1.json',21,'source'),('source256-finalizer-caller-controls-r1.json',11,'actualSource')]:
 d=load(file);assert d['count']==countwanted and not d.get('processQueries',d.get('realProcessQueries'))
 if field:
  f=d[field];raw=(B/f['file']).read_bytes();assert len(raw)==f['bytes'] and sha(raw)==f['sha256']
 else:
  for n,f in d['sources'].items():
   raw=(B/n).read_bytes();assert len(raw)==f['bytes'] and sha(raw)==f['sha256']
caller=load('source256-host-caller-controls-r3.json');assert all(r['status']=='PASS' for r in caller['cases']);assert next(r for r in caller['cases'] if r['case']=='truthy-nonboolean-not-complete')['failure']
schema=load('source256-checker-schema-controls-r2.json');assert schema['currentSourceVerification']['source']==m['source'] and schema['currentSourceVerification']['exactCurrentArchiveBindings']==count
previous=load('source256-host-caller-controls-r2.json')['sources']['confirmation-lifecycle-driver-r3.py'];raw=(B/'source256-driver-before-strict-completion-shape-r1.py').read_bytes();assert len(raw)==previous['bytes'] and sha(raw)==previous['sha256']
help=load('source256-cli-help-r1.json');assert len(help['rows'])==3
for row in help['rows']:
 raw=(B/row['file']).read_bytes();assert row['exit']==0 and not row['stderr'] and len(raw)==row['sourceBytes'] and sha(raw)==row['sourceSHA256']
code=(B/plan['driver']).read_text();assert "window['checked']=True" not in code and "['confirmationWindow']['checked']" not in code and "if window.get('checked')" not in code
assert "assert type(window['hostCheckCompleted']) is bool" in code
assert code.index("window['protectedAfterCheck']={}")<code.index("window['originAfterCheck']=")<code.index("relay.publish(relaypath,dict(armed,phase='checked'")<code.index("window['hostCheckCompleted']=True")
checker=(B/plan['checker']).read_text();assert "window['hostCheckCompleted'] is True" in checker and "retained_value('checked',True)" in checker and "'-lifecycle-r3-'" in checker
proof=load('source255-native-exact-github.json');assert proof['commit']==plan['priorExactCommit'] and proof['unionPaths']==2145
cleanup=load('source256-completed-failed255-cleanup-r1.json');assert cleanup['creditedRecoveryBytes']==105267200 and cleanup['aggregateCreditedRecoveryBytes']==15279312471
result={'status':'PASS root977/currentarchive/all951prior unchanged/case255pair exact/7wholecaller+26checkerSchema+21args+11main+3help; source review pending','hostSource':m['source'],'caseSource':plan['caseSource'],'build':plan['build'],'hostBindings':count,'caseBindings':951,'priorUnchanged':951,'priorModified':[],'appended':26,'pair':{'actualBuildSource':'durable-source-r255.json','actualBuildPID':27201,'actualBuildExit':0,'appBytes':receipt['binaryBytes'],'appSHA256':receipt['sha256'],'testBytes':len(test),'testSHA256':sha(test),'noNewBuild':True,'compiledSourceGitDiffCommand':command,'compiledSourceGitDiffExit':0,'scope':'Whole app/test/gate/Trace/fixture/project source exactly matches actual255fullbuild and native255pair. Source256 changes only host verification files; caseSource255 and hostSource256 independently bound, no fabricated256compile.'},'controlQualifications':'HostR1 missing real protocol obs/H dependencies failed; compact failure/recipe preserved. R2 wholecaller preceded strict nonBoolean guard; exact old driver copy retained, currentR3 controls bind current code. CheckerR1 genuine255two-relay positive failed atactual3-relay prerequisite; R2 explicitly synthetic third length-only placeholder enables limited marker/nativecheck segment, missing placeholder rejects. No fullchecker/third-relay payload/postCheck/native success from controls. Full actual fresh native/currentR3 checker still mandatory.','next':'Samecritic172/root/exact source before freshSource256R1 R3driver(case255/host256/build255) and plan-derivedR4finalizer/mandatoryR3checker/allactual originals/root/samecritic/exact; then current app255 optimizedRelease/fullgoal. No extra appbuild/doccleanup-only build/phone action. Oldraw255paths historical; never rerun oldnative255 audits.','checkedAt':time.time()}
p=B/'source256-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
