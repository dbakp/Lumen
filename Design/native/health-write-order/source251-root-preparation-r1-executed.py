"""Root frozen host-only163 corrections; no build/native/process queries."""
from pathlib import Path
import ast,base64,gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();load=lambda n:json.loads((B/n).read_bytes())
m=load('durable-source-r251.json');archive=json.loads(gzip.decompress((B/'durable-source-r251.json.gz').read_bytes()));prior=load('durable-source-r250.json');count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(archive[key])
 for n,fact in m[group].items():
  p=R/n;assert not p.is_symlink();raw=p.read_bytes();assert len(raw)==fact['bytes'] and sha(raw)==fact['sha256'];assert raw==(archive[key][n].encode() if key=='files' else base64.b64decode(archive[key][n],validate=True));count+=1
 for n,fact in prior[group].items():assert m[group][n]==fact,n
old=(B/'check-confirmation-lifecycle-r1.py').read_text();new=(B/'check-confirmation-lifecycle-r2.py').read_text();assert new==old.replace("v.all_payloads(state,h,state['appData'])","v.all_payloads(state,h,inputs['app'])").replace("'-lifecycle-r1-'","'-lifecycle-r2-'")
old=(B/'confirmation-lifecycle-driver-r1.py').read_text();new=(B/'confirmation-lifecycle-driver-r2.py').read_text();needle="    trace=observe(tracepath,'trace',window);v.trace(trace,actual,state['started'])\n";addition="    # The UI may cancel only after the actual waiter has started uncancelled.\n    if not window.get('relays'):\n        if len(trace['events'])==1:return\n        assert len(trace['events'])==2, 'Exact active waiter prefix required before arming UI'\n";assert new==old.replace(needle,needle+addition)
for n in ['source251-checker-api-controls-r1.json','source251-lifecycle-caller-controls-r1.json']:
 report=load(n);assert report['status'].startswith('PASS') and report['count']==14
 raw=gzip.decompress((B/report['fixture']).read_bytes());assert len(raw)==report['decodedBytes'] and sha(raw)==report['decodedSHA256'];json.loads(raw)
api=load('source251-checker-api-controls-r1.json');assert api['checker']['sha256']==sha((B/'check-confirmation-lifecycle-r2.py').read_bytes())
caller=load('source251-lifecycle-caller-controls-r1.json');assert caller['sourceSHA256']==sha((B/'confirmation-lifecycle-driver-r2.py').read_bytes())
entry=load('source251-entrypoint-controls-r1.json');assert not entry['realProcessQueries'] and len(entry['cases'])==2
for row in entry['cases']:assert row['exit']==0 and not row['stderr'] and row['sourceSHA256']==sha((B/row['file']).read_bytes())
for key in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert load('health-current-release-source251-r1-predeclared-plan.json')[key]==load('health-current-release-source250-r1-predeclared-plan.json')[key]
proof=load('source250-source-exact-github.json');assert proof['commit']=='103a5edb0a9af60c99b5855e992033b6f57b3429' and proof['unionPaths']==1887
raw=(B/'health-legacy-confirmation-lifecycle-source250-round2-part163-source.json').read_bytes();assert sha(raw)=='7170cb11603f4854a9462e9df508da77fd7d2f2a65d825f370abbc89711fea3c'
result={'status':'PASS root current/archive/all852priorunchanged/onlytwohost corrections/14API+14caller+2help/arrays/prior1887exact; independent source readiness pending','source':'durable-source-r251.json','bindings':count,'priorUnchanged':852,'priorModified':[],'appended':count-852,'scope':'Allapp/UITest inputs exact250, no repeated SDK/scheduling/currentnative or fullapp proof. Actual source250/163 NOT_READY preserved. Source251 firstfullpair/nativeR2/mandatorychecker/currentRelease/runtime/fullgoal remain unproved.','checkedAt':time.time()}
p=B/'source251-root-preparation-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
