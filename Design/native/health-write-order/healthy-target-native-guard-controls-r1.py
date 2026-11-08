from pathlib import Path
import json,subprocess,tempfile,gzip,hashlib,time
b=Path('Design/native/health-write-order');s=Path('Lumen/Views/HealthHealthyTargetChangeUIFixture.swift').read_text()
context=s[s.index('    static func context('):s.index('    static var requested:')]
constant=s[s.index('    static let healthyMeals ='):s.index('    private static let bridge')]
nutrition=Path('Lumen/Models/NutritionModels.swift').read_text().split('public struct HydrationLog:')[0]
health=Path('Lumen/Models/HealthModels.swift').read_text();health=health[health.index('public enum HealthSource:'):health.index('public enum WorkoutKind:')]
source=nutrition+health+'''enum Fixture {
 enum Failure: Error { case invalidContext }
 struct Context: Equatable { let runID: UUID }
 static let flag = "-health-healthy-target-change-ui"
 static let runFlag = "-health-healthy-target-change-run"
'''+constant+context+'''}
let run = "11111111-1111-4111-8111-111111111111"
let args = [Fixture.flag,"ready",Fixture.runFlag,run,"-health-legacy-reset-run",run,"-health-legacy-origin-ui","data","-health-backup-case","legacy","-resetForUITests","-health-backup-ui-fixture","-health-backup-empty-ui","-health-backup-healthy-merge-ui","-health-legacy-reset-ui"]
var results: [[String:Any]] = []
func expect(_ name: String,_ wanted: Bool,_ body: () throws -> Bool) {
 let actual: Bool
 do { actual = try body() } catch { actual = false }
 precondition(actual == wanted,name);results.append(["case":name,"accepted":actual])
}
expect("valid-context",true) { try Fixture.context(args)?.runID.uuidString.lowercased()==run }
expect("not-requested",true) { try Fixture.context([])==nil }
for flag in [Fixture.flag,Fixture.runFlag,"-health-legacy-reset-run","-health-legacy-origin-ui","-health-backup-case","-resetForUITests","-health-backup-ui-fixture","-health-backup-empty-ui","-health-backup-healthy-merge-ui","-health-legacy-reset-ui"] {
 expect("duplicate-"+flag,false) { try Fixture.context(args+[flag,"ready"]) != nil }
 expect("missing-"+flag,false) { var a=args;a.remove(at:a.firstIndex(of:flag)!);return try Fixture.context(a) != nil }
}
for flag in ["-health-legacy-reset-observer","-health-legacy-reset-diagnostic-only","-health-legacy-origin-mixed-ui","-health-legacy-capture-ui","-health-legacy-target-change-ui","-health-legacy-target-change-run"] {
 expect("forbidden-"+flag,false) { try Fixture.context(args+[flag]) != nil }
}
for (flag,value) in [("-health-legacy-origin-ui","string"),("-health-backup-case","lumen"),("-health-legacy-reset-run","22222222-2222-4222-8222-222222222222"),(Fixture.flag,"other"),(Fixture.runFlag,"bad-uuid")] {
 expect("invalid-"+flag,false) { var a=args;a[a.firstIndex(of:flag)!+1]=value;return try Fixture.context(a) != nil }
}
let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
let meals=try decoder.decode([Meal].self,from:Fixture.healthyMeals)
expect("actual-model-nonempty-known-record",true) { meals.count==1 && meals[0].id=="synthetic-newer-healthy-meal" && meals[0].items.count==1 && meals[0].calories==321 && meals[0].photoID==nil && meals[0].source == .manual && meals[0].type == .lunch }
print(String(data:try JSONSerialization.data(withJSONObject:["cases":results,"healthyPayload":Fixture.healthyMeals.base64EncodedString()],options:[.sortedKeys]),encoding:.utf8)!)
'''
with tempfile.TemporaryDirectory(prefix='lumen241-native-guards-') as temp:
 p=Path(temp)/'guards.swift';p.write_text(source);binary=Path(temp)/'guards';cmd=['xcrun','swiftc',str(p),'-o',str(binary)];c=subprocess.run(cmd,capture_output=True,text=True);r=subprocess.run([str(binary)],capture_output=True,text=True) if c.returncode==0 else None
 full={'source':source,'compileCommand':cmd,'compileExit':c.returncode,'compileStdout':c.stdout,'compileStderr':c.stderr,'runExit':r.returncode if r else None,'runStdout':r.stdout if r else None,'runStderr':r.stderr if r else None};raw=json.dumps(full).encode();fixture='source241-native-guard-controls-r1-fixtures.json.gz';assert not (b/fixture).exists();(b/fixture).write_bytes(gzip.compress(raw,mtime=0))
 output=json.loads(r.stdout) if r and r.returncode==0 else None
 if output:assert __import__('base64').b64decode(output['healthyPayload'])==(b/'healthy-target-current-meal-r1.json').read_bytes()
 report={'status':'PASS actualextractedcontext and actualMeal/FoodItem decoder' if output else 'FAILED isolatedguard preparation','fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':hashlib.sha256(raw).hexdigest(),'actualSourceSHA256':hashlib.sha256(s.encode()).hexdigest(),'contextSHA256':hashlib.sha256(context.encode()).hexdigest(),'modelFragmentsSHA256':hashlib.sha256((nutrition+health).encode()).hexdigest(),'compileExit':c.returncode,'runExit':r.returncode if r else None,'cases':output['cases'] if output else [],'scope':'Actual extracted Context and actual Meal/FoodItem/HealthSource models in isolated Foundation executable; no real preferences, app/runtime/bridge/scheduling/transaction/closure acceptance','checkedAt':time.time()};(b/'source241-native-guard-controls-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['status','compileExit','runExit']}));print(c.stderr[:1500]);print(r.stderr[:1500] if r else '')
