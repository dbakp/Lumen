"""Actual source guards preserve full alert assertion and remove value transport."""
from pathlib import Path
import gzip,hashlib,json,time
B=Path(__file__).resolve().parent;R=B.parents[2];current=(R/'LumenUITests/LumenSmokeTests.swift').read_text();old247=json.loads(gzip.decompress((B/'durable-source-r247.json.gz').read_bytes()))['files']['LumenUITests/LumenSmokeTests.swift'];old246=json.loads(gzip.decompress((B/'durable-source-r246.json.gz').read_bytes()))['files']['LumenUITests/LumenSmokeTests.swift']
body='Selected data will be replaced by records from this file. The older saved data will stay in a private recovery copy on this iPhone.'
def part(s):
 a=s.index('            if duringConfirmation {');return s[a:s.index('            snap(prefix + "-confirmation");',a)]
def query(s):
 p=part(s);return 'let body = "'+body+'"' in p and len(body)==131 and 'alert.staticTexts.matching(NSPredicate(format: "label == %@", body)).firstMatch' in p and 'alert.staticTexts[body]' not in p and 'alert.frame.contains(bodyElement.frame)' in p and 'recover.isHittable && cancel.isHittable' in p
def transport(s):
 p=part(s);return (query(s) and 'recover.value' not in p and 'func observeRelay(' in p and 'O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC' in p
  and 'try require(wholeAlert(),"confirmation-gate"' in p and 'try require(wholeAlert(),"confirmation-after-mutation"' in p
  and p.index('try require(wholeAlert(),"confirmation-gate"')<p.index('let marker: [String:Any]')
  and 'changed = observeRelay("mutated",previous:gate)' in p and '"probeTransport":"runner-file-relay"' in p)
rows=[]
for name,source,want,fn in [('current full body exact query',current,True,query),('old247 query correction retained',old247,True,query),('old246 long identifier rejected',old246,False,query),('reject identifier regression',current.replace('alert.staticTexts.matching(NSPredicate(format: "label == %@", body)).firstMatch','alert.staticTexts[body].firstMatch'),False,query),('reject contains query',current.replace('"label == %@", body','"label CONTAINS %@", body'),False,query),('reject shortened body',current.replace(body,'Short consequence'),False,query),('current relay + real alert gating',current,True,transport),('old247 action-value dependency rejected',old247,False,transport),('reject missing premutation real alert',current.replace('try require(wholeAlert(),"confirmation-gate"','try require(true,"confirmation-gate"'),False,transport),('reject missing postmutation real alert',current.replace('try require(wholeAlert(),"confirmation-after-mutation"','try require(true,"confirmation-after-mutation"'),False,transport),('reject unbound changed relay',current.replace('changed = observeRelay("mutated",previous:gate)','changed = observeRelay("mutated")'),False,transport)]:
 actual=fn(source);assert actual==want,name;rows.append({'name':name,'accepted':actual,'expected':want,'sourceSHA256':hashlib.sha256(source.encode()).hexdigest()})
(B/'source248-confirmation-query-controls-r1.json').write_text(json.dumps({'status':'PASS actual source exact-label/relay/real-alert prerequisite guards','count':len(rows),'cases':rows,'scope':'Source text guards only, actual extracted reader tested separately; no real XCTest alert/runner/timing/cancellation acceptance','checkedAt':time.time()},indent=2)+'\n');print(len(rows),'actual query/transport source controls PASS')
