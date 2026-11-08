"""Actual source matcher for the documented XCTest overlength identifier hazard."""
from pathlib import Path
import gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2]
current=(R/'LumenUITests/LumenSmokeTests.swift').read_text();old=json.loads(gzip.decompress((B/'durable-source-r246.json.gz').read_bytes()))['files']['LumenUITests/LumenSmokeTests.swift']
body='Selected data will be replaced by records from this file. The older saved data will stay in a private recovery copy on this iPhone.'
def accepted(source):
 start=source.index('            if duringConfirmation {');end=source.index('            snap(prefix + "-confirmation");',start);part=source[start:end]
 return ('let body = "'+body+'"' in part and len(body)==131
  and 'alert.staticTexts.matching(NSPredicate(format: "label == %@", body)).firstMatch' in part
  and 'alert.staticTexts[body]' not in part
  and 'alert.frame.contains(bodyElement.frame)' in part
  and 'recover.isHittable && cancel.isHittable' in part
  and 'try require(XCTWaiter.wait(for: [armed], timeout: 10)' in part)
rows=[]
for name,source,want in [('actual247 full exact-label predicate',current,True),('actual frozen246 long identifier rejected',old,False),('reject identifier regression',current.replace('alert.staticTexts.matching(NSPredicate(format: "label == %@", body)).firstMatch','alert.staticTexts[body].firstMatch'),False),('reject contains predicate',current.replace('"label == %@", body','"label CONTAINS %@", body'),False),('reject shortened body',current.replace(body,'Selected data will be replaced.'),False),('reject body geometry removal',current.replace('alert.frame.contains(bodyElement.frame)','true'),False),('reject action prerequisite removal',current.replace('recover.isHittable && cancel.isHittable','true'),False)]:
 actual=accepted(source);assert actual==want,name;rows.append({'name':name,'accepted':actual,'expected':want,'sourceSHA256':hashlib.sha256(source.encode()).hexdigest()})
(B/'source247-confirmation-query-controls-r1.json').write_text(json.dumps({'status':'PASS actual source exact-label matcher rejects frozen246/known regression and weakened predicates','cases':rows,'bodyCharacters':len(body),'scope':'Source matcher and known203 failure provenance only, no new XCTest query runtime/whole app or native acceptance','checkedAt':time.time()},indent=2)+'\n');print(len(rows),'actual source matcher controls PASS')
