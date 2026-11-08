"""Readonly exact stable independent report/current source review checkpoint."""
from pathlib import Path
import base64,gzip,hashlib,json,shutil,time
B=Path(__file__).resolve().parent;R=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest()
name='health-legacy-confirmation-lifecycle-source250-round2-part163-source.json';raw=(B/name).read_bytes();report=json.loads(raw)
assert len(raw)==27169 and sha(raw)=='7170cb11603f4854a9462e9df508da77fd7d2f2a65d825f370abbc89711fea3c'
assert report['part']==163 and report['verdict']['sourceReady'] is False and report['verdict']['stopBeforeBuildAndNative'] is True
bindings=report['provenance'];assert len(bindings)==50
for row in bindings:
 data=(R/row['path']).read_bytes();assert len(data)==row['bytes'] and sha(data)==row['sha256'],row['path']
m=json.loads((B/'durable-source-r250.json').read_bytes());archive=json.loads(gzip.decompress((B/'durable-source-r250.json.gz').read_bytes()));count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(archive[key])
 for name,fact in m[group].items():
  data=(R/name).read_bytes();saved=archive[key][name].encode() if key=='files' else base64.b64decode(archive[key][name],validate=True)
  assert data==saved and len(data)==fact['bytes'] and sha(data)==fact['sha256'];count+=1
assert count==852
diagnostic=json.loads((B/'source250-checker-metadata-diagnostic-r1.json').read_bytes());assert len(diagnostic['cases'])==7 and all(x['accepted'] is x['expected'] for x in diagnostic['cases'])
result={'status':'Root acknowledges163 NOT_READY; preserve250/current852/report50 before separate251 corrections','report':{'file':name,'bytes':len(raw),'sha256':sha(raw)},'allReportProvenanceBindingsExact':50,'currentArchiveBindingsExact':852,'rootRead':'Full27169Breport opened in nontruncated1-145/146-295/296-end ranges; whole newly authored sources and named control scopes reviewed. Unchanged historical source mechanically bound only.','requiredCorrection':'P163-C1 fresh inputs.app metadata argument and actual checker fragment API controls; preserve exact null exception','alsoAddress':'P163-R1 require actual active created+wait-started prefix before armed metadata relay; add pending-before-start caller control','separateDiagnostic':'source250-checker-metadata-diagnostic-r1.json,7actualAST/projection cases. Arrived after163 and not borrowed as its provenance.','scope':'No250sourceReady/build/native/Release acceptance. Prior248/249 accepted scopes unchanged; fullgoal active. No phoneactions or oldraw audit.','visualCheck':'Current visual markup/all3buttons/host state/stale snapshot fallback VM pass; no browser render','availableBytes':shutil.disk_usage(R).free,'checkedAt':time.time()}
out=B/'source250-root-part163-review.json';assert not out.exists();out.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],50,852)
