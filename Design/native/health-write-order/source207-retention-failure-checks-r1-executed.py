import ast,pathlib,tempfile,json,hashlib,types,os,shutil,time
candidate=pathlib.Path('/tmp/lumen207-driver.py');source=candidate.read_text();node=next(n for n in ast.parse(source).body if isinstance(n,ast.FunctionDef) and n.name=='retain_terminal');tree=ast.Module(body=[node],type_ignores=[])
root=pathlib.Path(tempfile.mkdtemp(prefix='Lumen207RetentionFailureCheck-'));checks=[]
try:
 def execute(case,export_fail=False,summary_fail=False,missing=False,bad_peer=False,empty=False):
  base=root/case;base.mkdir();canonical=base/'canonical';canonical.mkdir();raw=base/'native';result=base/'native.xcresult'
  if not missing:result.mkdir()
  def output(args):
   if summary_fail:raise RuntimeError('injected summary failure')
   return b'{"passedTests":1,"failedTests":0,"skippedTests":0}\n'
  def run(args,**kw):
   dest=pathlib.Path(args[args.index('--output-path')+1]);dest.mkdir(exist_ok=True)
   if not empty:
    (dest/'manifest.json').write_text(json.dumps([{'testIdentifier':'LumenSmokeTests/testHealthLegacyRootAcquisitionNoPrior()','attachments':[{'exportedFileName':n,'deviceId':'synthetic-sim'} for n in ['a.png','z.png']]}]))
    (dest/'a.png').write_bytes(b'known synthetic PNG attachment A')
    (dest/'z.png').write_bytes(b'known synthetic PNG attachment Z')
    if bad_peer:(dest/'bad.png').symlink_to(dest/'absent-synthetic')
   if export_fail:raise RuntimeError('injected exporter failure after partial outputs')
  ns=dict(pathlib=pathlib,json=json,os=os,subprocess=types.SimpleNamespace(check_output=output,run=run,DEVNULL=-3,PIPE=-1),P=canonical,MODES={'no-prior':('legacy-root-missing-no-prior','NoPrior')},SIM='synthetic-sim',sha=lambda b:hashlib.sha256(b).hexdigest(),write=lambda p,d:pathlib.Path(p).write_text(json.dumps(d)))
  exec(compile(tree,str(candidate),'exec'),ns);evidence={'source':'candidate207','nativeExitCode':0,'mode':'legacy-root-missing-no-prior'};errors=ns['retain_terminal'](result,raw,case,evidence);return canonical,evidence,errors
 c,e,errors=execute('partial',True,True,bad_peer=True);assert len(errors)>=3 and e['retention']['originalPNGCount']==2 and e['retention']['exportMetadataCount']==1 and not e['retention']['summaryRetained'];assert any(f.read_bytes()==b'known synthetic PNG attachment Z' for f in c.glob('*.png'));checks.append('Exporter and summary throw plus bad peer: both partial originalPNG and full metadata independently salvaged; errors retained')
 c,e,errors=execute('missing',missing=True);assert errors and e['retention']['originalPNGCount']==0;checks.append('Missing result cannot pass retention')
 c,e,errors=execute('empty',empty=True);assert errors and any('metadata' in x for x in errors) and any('screenshot' in x for x in errors);checks.append('Successful exporter with empty outputs cannot pass required evidence')
 c,e,errors=execute('healthy');assert not errors and e['retention']['originalPNGCount']==2 and e['retention']['nativeHelperJSONCount']==0;checks.append('Complete originals/metadata/summary with declared zero nativehelper JSON accepted')
 report={'status':'PASS four meaningful isolated failure-retention checks; no native execution or product acceptance','candidateDriverBytes':candidate.stat().st_size,'candidateDriverSHA256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'checks':checks,'fixtureScope':'Only isolated known temporary export fixtures, no simulator/Git/app source actions. Exact retention function AST executed with injected exporter/summary failures; not an end-to-end xcresult export proof.','checkedAt':time.time()}
 pathlib.Path('/tmp/lumen207-retention-check-result.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
finally:shutil.rmtree(root)
