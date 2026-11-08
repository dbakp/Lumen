"""Root current/archive, actual logic outcomes/binary and complete synthetic fixture bindings."""
from pathlib import Path
import json,gzip,base64,hashlib,stat,os,time
B=Path(__file__).resolve().parent;repo=B.parents[2];sha=lambda x:hashlib.sha256(x).hexdigest();m=json.loads((B/'durable-source-r244.json').read_bytes());a=json.loads(gzip.decompress((B/'durable-source-r244.json.gz').read_bytes()));count=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(m[group])==set(a[key])
 for name,w in m[group].items():
  p=repo/name;assert not p.is_symlink();raw=p.read_bytes();saved=a[key][name].encode() if key=='files' else base64.b64decode(a[key][name],validate=True);assert raw==saved and len(raw)==w['bytes'] and sha(raw)==w['sha256'],name;count+=1
old=json.loads((B/'durable-source-r243.json').read_bytes());changed=[n for n in old['files'] if m['files'][n]!=old['files'][n]];assert set(changed)=={'Lumen/Models/HealthLegacyRecoveryOrigin.swift','Lumen/Views/BackupFileRecoveryView.swift','Tests/HealthLegacyRecoveryOriginChecks.swift'};assert all(m['fixtureInputs'][n]==w for n,w in old['fixtureInputs'].items())
origin=json.loads((B/'source244-origin-review-r1-outcome.json').read_bytes());reg=json.loads((B/'source244-logic-regressions-r1.json').read_bytes());assert origin['exit']==0 and reg['status'].startswith('PASS')
for name,ha in origin['sourceSHA256'].items():assert sha((repo/name).read_bytes())==ha==reg['sourceSHA256'][name]
binary=Path(reg['binary']);data=binary.read_bytes();assert len(data)==reg['binaryBytes'] and sha(data)==reg['binarySHA256']
reports=[]
for out in [origin]+reg['runs']:
 assert out['exit']==0
 raw=gzip.decompress((B/out['log']).read_bytes());assert len(raw)==out['logBytes'] and sha(raw)==out['logSHA256']
 if out.get('label')=='full':assert sum(x.startswith('PASS:') for x in raw.decode().splitlines())==2177 and raw.decode().rstrip().endswith('All import, model, totals, history, plan, conversation, evidence, document and reminder checks passed.')
 if 'report' in out:
  raw=(B/out['report']).read_bytes();assert len(raw)==out['reportBytes'] and sha(raw)==out['reportSHA256'];r=json.loads(raw);assert len(r['checks'])==out['checks'] and all(x['passed'] is True for x in r['checks']);reports.append((out['report'],len(r['checks'])))
assert [n for _,n in reports]==[46,57,117,22]
r=json.loads((B/'source244-logic-synthetic-roots-r1.json').read_bytes());raw=gzip.decompress((B/r['fixture']).read_bytes());assert len(raw)==r['decodedBytes'] and sha(raw)==r['decodedSHA256'];archive=json.loads(raw);files=0;byte_count=0
for root,record in archive['roots'].items():
 root=Path(root);assert not root.is_symlink()
 for row in record['entries']:
  p=root/row['path'];s=p.lstat();assert all(getattr(s,k)==value for k,value in row['identity'].items())
  if row['kind']=='regular':
   raw=base64.b64decode(row['base64'],validate=True);assert raw==p.read_bytes() and len(raw)==row['bytes'] and sha(raw)==row['sha256'];files+=1;byte_count+=len(raw)
  elif row['kind']=='symlink':assert stat.S_ISLNK(s.st_mode) and os.readlink(p)==row['target']
  elif row['kind']=='fifo':assert stat.S_ISFIFO(s.st_mode)
  else:assert row['kind']=='directory' and stat.S_ISDIR(s.st_mode)
assert files==218 and byte_count==24935
syntax=json.loads((B/'source244-syntax-r1.json').read_bytes());assert syntax['exit']==0 and syntax['stdout']==syntax['stderr']==''
pre=json.loads((B/'health-current-release-source244-r1-predeclared-plan.json').read_bytes());prior=json.loads((B/'health-current-release-source242-r1-predeclared-plan.json').read_bytes())
for key in ['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']:assert pre[key]==prior[key]
out={'status':'PASS root708current/archive/3priorchanged682unchanged/currentMaclogicbinary/full2177+46review+57origin+117transaction+22boundary outcomes/full218fixturefiles exact; independent146pending','source':'durable-source-r244.json','bindings':count,'sourceSHA256':sha((B/'durable-source-r244.json').read_bytes()),'archiveSHA256':sha((B/'durable-source-r244.json.gz').read_bytes()),'changedPriorInputs':changed,'actualLogicBinarySHA256':reg['binarySHA256'],'scopedChecks':reports,'defaultLogicPASSLines':2177,'fixtureRegularFiles':files,'fixtureRegularBytes':byte_count,'scope':'Macproductionlogic/model and syntax proof only; SwiftUIiOSbody/currentapp-testpair/native/healthyUI/commit/closure/Release pending','checkedAt':time.time()};p=B/'source244-root-source-audit-r1.json';assert not p.exists();p.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({k:out[k] for k in ['status','bindings','defaultLogicPASSLines','fixtureRegularFiles']}))
