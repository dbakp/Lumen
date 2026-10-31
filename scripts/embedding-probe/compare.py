"""Compare independent upstream/native reports without hiding failed cases."""
import hashlib
import json
import math
import sys
from pathlib import Path
reference_path, native_path, policy_path, output = map(Path, sys.argv[1:])
reference, native, policy = [json.loads(p.read_text()) for p in (reference_path, native_path, policy_path)]
assert reference['fixtureSHA256'] == native['fixtureSHA256']
assert reference['windowProofVersion'] == native['windowProofVersion'] == 1
left = {x['id']: x for x in reference['cases']}
right = {x['id']: x for x in native['cases']}
assert set(left) == set(right)
rows, failures = [], []
vector_count = 0

def difference(x, y):
    assert len(x) == len(y) == 384
    assert all(math.isfinite(v) for v in x+y)
    nx = math.sqrt(sum(v*v for v in x))
    ny = math.sqrt(sum(v*v for v in y))
    assert nx > 0 and ny > 0
    return sum(a*b for a,b in zip(x,y))/(nx*ny), max(abs(a-b) for a,b in zip(x,y))

for key, expected in left.items():
    actual = right[key]
    issues = []
    for field in ['tokenStatus','tokenIDs','queryStatus','passageStatus','windowTokenIDs','windowMasks']:
        if expected.get(field) != actual.get(field): issues.append(field+' differs')
    if expected.get('tokenIDs') is not None:
        for field in ['windowTokenIDs','windowMasks']:
            if field not in expected or field not in actual: issues.append(field+' missing')
    a, b = expected.get('passageVectors',[]), actual.get('passageVectors',[])
    if len(a) != len(b): issues.append('passage window count differs')
    metrics = []
    for kind, x, y in ([('query',expected['queryVector'],actual['queryVector'])] if expected.get('queryStatus') == actual.get('queryStatus') == 'used' else []):
        cosine, maximum = difference(x,y);metrics.append({'kind':kind,'cosine':cosine,'maximumElementDifference':maximum});vector_count += 1
    for index,(x,y) in enumerate(zip(a,b)):
        cosine, maximum = difference(x,y);metrics.append({'kind':'passage-'+str(index),'cosine':cosine,'maximumElementDifference':maximum});vector_count += 1
    if any(x['cosine'] < policy['minimumCosine'] or x['maximumElementDifference'] > policy['maximumElementDifference'] for x in metrics): issues.append('numerical gate failed')
    row = {'id':key,'tokenCount':len(expected['tokenIDs']) if 'tokenIDs' in expected else None,'queryStatus':actual['queryStatus'],'passageStatus':actual['passageStatus'],'passageWindowCount':len(b),'paddedWindowsExact':expected.get('windowTokenIDs')==actual.get('windowTokenIDs') and expected.get('windowMasks')==actual.get('windowMasks'),'minimumCosine':min((x['cosine'] for x in metrics),default=None),'maximumElementDifference':max((x['maximumElementDifference'] for x in metrics),default=None),'issues':issues}
    rows.append(row)
    if issues: failures.append({'id':key,'issues':issues})
report = {'scope':'Numerical/token/controller/window compatibility only; not retrieval, medical, multilingual or physical-device quality','result':'passed' if not failures else 'failed','caseCount':len(rows),'comparedVectors':vector_count,'fixtureSHA256':reference['fixtureSHA256'],'policy':policy,'referenceSHA256':hashlib.sha256(reference_path.read_bytes()).hexdigest(),'nativeSHA256':hashlib.sha256(native_path.read_bytes()).hexdigest(),'minimumCosine':min(x['minimumCosine'] for x in rows if x['minimumCosine'] is not None),'maximumElementDifference':max(x['maximumElementDifference'] for x in rows if x['maximumElementDifference'] is not None),'failures':failures,'cases':rows}
output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['result','caseCount','comparedVectors','minimumCosine','maximumElementDifference','failures']}))
sys.exit(0 if not failures else 1)
