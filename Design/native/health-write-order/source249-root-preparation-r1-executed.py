"""Root readonly frozen String confirmation preparation; no builds/queries/native."""
from pathlib import Path
import base64,gzip,hashlib,json,ast,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();load=lambda n:json.loads((B/n).read_bytes())
m=load('durable-source-r249.json');a=json.loads(gzip.decompress((B/'durable-source-r249.json.gz').read_bytes()));prior=load('durable-source-r248.json');changed=[];count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for n,f in m[group].items():
  p=R/n;assert not p.is_symlink();raw=p.read_bytes();assert len(raw)==f['bytes'] and sha(raw)==f['sha256'];assert raw==(a[key][n].encode() if key=='files' else base64.b64decode(a[key][n],validate=True));count+=1
 for n,f in prior[group].items():
  if m[group][n]!=f:changed.append(n)
assert count==816 and changed==['LumenUITests/LumenSmokeTests.swift']
addition='''    @MainActor
    func testHealthBackupFileRecoveryTargetChangedDuringConfirmationOriginString() throws {
        try exerciseHealthBackupFileRecoveryTargetChangedAfterReady(duringConfirmation: true)
    }

'''
old=json.loads(gzip.decompress((B/'durable-source-r248.json.gz').read_bytes()))['files'][changed[0]];assert a['files'][changed[0]].replace(addition,'')==old
expected=(B/'confirmation-target-driver-r3.py').read_text().replace('confirmation-target-evidence-r1.py','confirmation-string-evidence-r1.py').replace('HealthLegacyConfirmationData','HealthLegacyConfirmationString').replace('health-legacy-confirmation-data-','health-legacy-confirmation-string-').replace('data-during-confirmation-runner-relay','string-during-confirmation-runner-relay').replace('DuringConfirmationOriginData','DuringConfirmationOriginString').replace("['kind']=='data'","['kind']=='string'").replace('h.DATA','e.obs.OLD')
assert (B/'confirmation-string-driver-r1.py').read_text()==expected
expected=(B/'check-confirmation-target-r3.py').read_text().replace('confirmation-target-evidence-r1.py','confirmation-string-evidence-r1.py').replace('legacy-target-change-validation-r3.py','target-string-validation-r1.py').replace("'-confirmation-r3-'","'-confirmation-string-r1-'").replace("('-health-legacy-origin-ui','data')","('-health-legacy-origin-ui','string')").replace('h.DATA','e.obs.OLD')
assert (B/'check-confirmation-string-r1.py').read_text()==expected
controls=load('source249-string-caller-controls-r1.json');assert controls['count']==18 and all(r['status']=='PASS' for r in controls['cases'])
prep=load('source249-string-preparation-controls-r1.json');assert prep['count']==18 and prep['realProcessQueries']==0 and len(prep['help'])==2 and all(r['exit']==0 and r['realProcessQueries']==0 and not r['stderr'] for r in prep['help'])
assert prep['actualNamespaces']=={'obs':'target-string-observation-r2.py','success':'target-string-success-r1.py','v':'target-string-validation-r1.py'}
for report,name in [(controls,'source249-string-caller-controls-r1-fixtures.json.gz'),(prep,'source249-string-preparation-controls-r1-fixtures.json.gz')]:
 raw=gzip.decompress((B/name).read_bytes());assert len(raw)==report['archiveDecodedBytes'] and sha(raw)==report['archiveDecodedSHA256'];json.loads(raw)
sdk=load('source249-uitest-sdk-typecheck-r1.json');assert sdk['exit']==0 and not sdk['stdout'] and not sdk['stderr'] and sdk['sourceSHA256']==m['files'][changed[0]]['sha256']
arrays=['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers'];plan=load('health-current-release-source249-r1-predeclared-plan.json');old=load('health-current-release-source248-r1-predeclared-plan.json');assert all(plan[k]==old[k] for k in arrays)
proof=load('source248-release-exact-github.json');assert proof['commit']=='e000591dd284d0b746dc703e7d02894596fece0c' and proof['unionPaths']==1751
result={'status':'PASS root816current/archive/onewrapper-only/native routine unchanged/actualStringcomposition/18caller+18predicate+2help/SDK0/predeclaredarrays/prior1751exact; source review pending','source':'durable-source-r249.json','bindings':count,'priorUnchanged':794,'appended':21,'priorModified':changed,'actualDriverAndCheckerTransformExact':True,'scope':'App Lumen/Shared/gate/fixture production exact248; prior159Release optimizedINSTRUMENTED unsigneddevelopment static carry only. No current249build/confirmation/native/cancellation/expiry/fullgoal acceptance. Firstcaller output before unused misleading Data alias removal retained as preparation history. No raw248/Release live audits repeated.','checkedAt':time.time()};(B/'source249-root-preparation-r1.json').write_text(json.dumps(result,indent=2)+'\n');print(result['status'])
