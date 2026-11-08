from pathlib import Path
import json,gzip,base64,hashlib,time
b=Path('Design/native/health-write-order');sha=lambda x:hashlib.sha256(x).hexdigest();m=json.loads((b/'durable-source-r242.json').read_bytes());a=json.loads(gzip.decompress((b/'durable-source-r242.json.gz').read_bytes()));count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for name,w in m[group].items():
  p=Path(name);assert not p.is_symlink();r=p.read_bytes();saved=a[key][name].encode() if key=='files' else base64.b64decode(a[key][name],validate=True);assert r==saved and len(r)==w['bytes'] and sha(r)==w['sha256'],name;count+=1
for name in ['source242-test-typecheck-r2.json','source241-fixture-typecheck-r1.json']:
 r=json.loads((b/name).read_bytes());src=Path(r['source']).read_bytes();assert len(src)==r['sourceBytes'] and sha(src)==r['sourceSHA256'] and r['exit']==0 and r['stdout']==r['stderr']==''
r=json.loads((b/'source242-healthy-region-controls-r2.json').read_bytes());raw=gzip.decompress((b/r['fixture']).read_bytes());assert len(raw)==r['decodedBytes'] and sha(raw)==r['decodedSHA256'];d=json.loads(raw);assert len(d['caseResults'])==42 and (r['accepted'],r['rejected'])==(6,36)
p=json.loads((b/'health-current-release-source242-r1-predeclared-plan.json').read_bytes());assert [len(p[k]) for k in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']]==[207,191,16,21]
old=json.loads((b/'durable-source-r241.json').read_bytes());assert [n for n in old['files'] if m['files'][n]!=old['files'][n]]==['LumenUITests/LumenSmokeTests.swift'];assert all(m['fixtureInputs'][n]==w for n,w in old['fixtureInputs'].items())
out={'status':'PASS root674current/archive and42puregeometry/readiness/actualASTlabelcontrols/currentwholeUITesttyping/helpbindings; independent142 pending','source':'durable-source-r242.json','bindings':count,'sourceManifestSHA256':sha((b/'durable-source-r242.json').read_bytes()),'archiveSHA256':sha((b/'durable-source-r242.json.gz').read_bytes()),'modifiedPriorInputs':1,'unchangedPriorInputs':654,'scope':'Preparation/source audit only; no242fullbuild/native/producteligibility/transaction acceptance; original241NOTREADY preserved','checkedAt':time.time()};p=b/'source242-root-source-audit-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
