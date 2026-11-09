from pathlib import Path
import json,subprocess,tempfile,gzip,hashlib,time
b=Path('Design/native/health-write-order');s=Path('Lumen/Views/HealthLegacyTargetChangeUIFixture.swift').read_text()
context=s[s.index('    static func context('):s.index('    static var requested:')]
helpers=s[s.index('    static func stringBytes('):s.index('    private static func fixedFacts()')]
constants=s[s.index('    static let newerMeals ='):s.index('    private static let bridge')]
pre='''import Foundation
struct FakeProcess { var arguments: [String] }
enum ProcessInfo { static var processInfo = FakeProcess(arguments: []) }
final class UserDefaults {
 static let standard = UserDefaults()
 var persisted: [String: Any] = [:]; var effective: [String: Any] = [:]
 func persistentDomain(forName: String) -> [String: Any]? { persisted }
 func object(forKey key: String) -> Any? { effective[key] }
}
enum HealthLegacyOriginUIFixture {
 static let data = Data("{synthetic persisted legacy origin damaged".utf8)
 static let string = "Synthetic persisted old value e\\u{301} 🫖"
}
enum Fixture {
 enum Failure: Error { case invalidContext, invalidObservation, duplicateMutation }
 struct Context: Equatable { let runID: UUID; let kind: String }
 static let flag = "-health-legacy-target-change-ui"
 static let runFlag = "-health-legacy-target-change-run"
 static let lifecycleFlag = "-health-legacy-confirmation-lifecycle-ui"
 static let expiryFlag = "-health-legacy-confirmation-expiry-ui"
'''
post=''' static func check(_ key: String, changed: Bool) throws -> Any { try checkedFixedValue(key, mealsChanged: changed) }
}
let run = "11111111-1111-4111-8111-111111111111"
func args(_ kind: String) -> [String] { ["-health-legacy-target-change-ui","ready","-health-legacy-target-change-run",run,"-health-legacy-reset-run",run,"-health-legacy-origin-ui",kind,"-health-backup-case","legacy","-resetForUITests","-health-backup-ui-fixture","-health-backup-empty-ui","-health-backup-healthy-merge-ui","-health-legacy-reset-ui"] }
var results: [[String: Any]] = []
func expect(_ name: String, _ wanted: Bool, _ body: () throws -> Bool) {
 let actual: Bool
 do { actual = try body() } catch { actual = false }
 precondition(actual == wanted, name)
 results.append(["case":name,"accepted":actual,"expected":wanted])
}
for kind in ["data","string"] { expect("context-"+kind,true) { try Fixture.context(args(kind))?.kind == kind } }
expect("no-request",true) { try Fixture.context([]) == nil }
expect("confirmation-flag-once",true) { try Fixture.context(args("data")+["-health-legacy-confirmation-window-ui"])?.kind == "data" }
expect("confirmation-flag-duplicate",false) { try Fixture.context(args("data")+["-health-legacy-confirmation-window-ui","-health-legacy-confirmation-window-ui"]) != nil }
let life="-health-legacy-confirmation-lifecycle-ui",window="-health-legacy-confirmation-window-ui"
expect("lifecycle-data",true) { try Fixture.context(args("data")+[window,life])?.kind == "data" }
expect("lifecycle-string-rejected",false) { try Fixture.context(args("string")+[window,life]) != nil }
expect("lifecycle-without-window",false) { try Fixture.context(args("data")+[life]) != nil }
expect("lifecycle-duplicate",false) { try Fixture.context(args("data")+[window,life,life]) != nil }
let expiry = "-health-legacy-confirmation-expiry-ui"
expect("expiry-valid",true) { try Fixture.context(args("data")+[window,life,expiry])?.kind == "data" }
expect("expiry-alone",false) { try Fixture.context([expiry]) != nil }
expect("expiry-duplicate",false) { try Fixture.context(args("data")+[window,life,expiry,expiry]) != nil }
expect("expiry-without-lifecycle",false) { try Fixture.context(args("data")+[window,expiry]) != nil }
expect("expiry-without-window",false) { try Fixture.context(args("data")+[life,expiry]) != nil }
expect("expiry-string",false) { try Fixture.context(args("string")+[window,life,expiry]) != nil }
expect("expiry-missing-context",false) { try Fixture.context([window,life,expiry]) != nil }
expect("lifecycle-alone",false) { try Fixture.context([life]) != nil }
expect("unknown-kind",false) { try Fixture.context(args("unknown")) != nil }
for flag in ["-health-legacy-origin-ui","-health-legacy-target-change-ui","-health-legacy-reset-ui"] {
 expect("duplicate-"+flag,false) { try Fixture.context(args("string")+[flag,"string"]) != nil }
 var missing=args("string");missing.remove(at:missing.firstIndex(of:flag)!)
 expect("missing-"+flag,false) { try Fixture.context(missing) != nil }
}
expect("mismatched-run",false) { var a=args("string");a[a.firstIndex(of:"-health-legacy-reset-run")!+1]="22222222-2222-4222-8222-222222222222";return try Fixture.context(a) != nil }
for flag in ["-health-legacy-reset-observer","-health-legacy-reset-diagnostic-only","-health-legacy-origin-mixed-ui","-health-legacy-capture-ui"] {
 expect("forbidden-"+flag,false) { try Fixture.context(args("string")+[flag]) != nil }
}
let key="lumen.health.meals.v1",work="lumen.health.workouts.v1"
func fixed(_ kind: String, _ changed: Bool, persisted: Any?, effective: Any?, workout: Any? = nil) throws -> Bool {
 ProcessInfo.processInfo.arguments=args(kind)
 let original: Any = kind == "data" ? HealthLegacyOriginUIFixture.data as Any : HealthLegacyOriginUIFixture.string as Any
 UserDefaults.standard.persisted=[work:workout ?? original];UserDefaults.standard.effective=[work:workout ?? original]
 UserDefaults.standard.persisted[key]=persisted;UserDefaults.standard.effective[key]=effective
 _ = try Fixture.check(key,changed:changed);_ = try Fixture.check(work,changed:changed);return true
}
for changed in [false,true] {
 let data=changed ? Fixture.newerMeals : HealthLegacyOriginUIFixture.data
 let text=changed ? Fixture.newerMealsString : HealthLegacyOriginUIFixture.string
 expect("data-"+String(changed),true) { try fixed("data",changed,persisted:data,effective:data) }
 expect("string-"+String(changed),true) { try fixed("string",changed,persisted:text,effective:text) }
 expect("string-reject-data-"+String(changed),false) { try fixed("string",changed,persisted:Data(text.utf8),effective:Data(text.utf8)) }
 expect("data-reject-string-"+String(changed),false) { try fixed("data",changed,persisted:text,effective:text) }
}
let old=HealthLegacyOriginUIFixture.string,new=Fixture.newerMealsString
expect("normalization-equivalent",false) { try fixed("string",false,persisted:old.precomposedStringWithCanonicalMapping,effective:old.precomposedStringWithCanonicalMapping) }
expect("effective-changed",false) { try fixed("string",false,persisted:old,effective:new) }
expect("missing-persisted",false) { try fixed("string",false,persisted:nil,effective:old) }
expect("missing-effective",false) { try fixed("string",false,persisted:old,effective:nil) }
expect("workout-mutated",false) { try fixed("string",true,persisted:new,effective:new,workout:new) }
expect("new-as-original",false) { try fixed("string",false,persisted:new,effective:new) }
expect("old-as-new",false) { try fixed("string",true,persisted:old,effective:old) }
let out: [String:Any] = ["cases":results,"oldUTF16LE":Fixture.stringBytes(old as NSString).base64EncodedString(),"newUTF16LE":Fixture.stringBytes(new as NSString).base64EncodedString(),"actualReflectedSwiftStringType":String(reflecting:type(of:old as Any)),"normalizationEqualInSwift":old == old.precomposedStringWithCanonicalMapping,"rawUnitsDiffer":Fixture.stringBytes(old as NSString) != Fixture.stringBytes(old.precomposedStringWithCanonicalMapping as NSString)]
print(String(data:try JSONSerialization.data(withJSONObject:out,options:[.sortedKeys]),encoding:.utf8)!)
'''
source=pre+constants+context+helpers+post
with tempfile.TemporaryDirectory(prefix='lumen257-native-guards-') as temp:
 p=Path(temp)/'guards.swift';p.write_text(source);binary=Path(temp)/'guards';cmd=['xcrun','swiftc',str(p),'-o',str(binary)];c=subprocess.run(cmd,capture_output=True,text=True);r=subprocess.run([str(binary)],capture_output=True,text=True) if c.returncode==0 else None
 full={'source':source,'compileCommand':cmd,'compileExit':c.returncode,'compileStdout':c.stdout,'compileStderr':c.stderr,'runExit':r.returncode if r else None,'runStdout':r.stdout if r else None,'runStderr':r.stderr if r else None};raw=json.dumps(full).encode();fixture='source257-native-guard-controls-r1-fixtures.json.gz';(b/fixture).write_bytes(gzip.compress(raw,mtime=0))
 report={'status':'PASS actualextractedcontext/UTF16LE/fixedguards' if c.returncode==0 and r.returncode==0 else 'FAILED isolatedguard preparation','fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':hashlib.sha256(raw).hexdigest(),'actualSourceSHA256':hashlib.sha256(s.encode()).hexdigest(),'contextSHA256':hashlib.sha256(context.encode()).hexdigest(),'helpersSHA256':hashlib.sha256(helpers.encode()).hexdigest(),'compileExit':c.returncode,'runExit':r.returncode if r else None,'cases':json.loads(r.stdout)['cases'] if r and r.returncode==0 else [],'scope':'Actual extracted functions with isolated defaults/arguments stubs; no real preferences, app/runtime/bridge/scheduling/transaction/closure acceptance','checkedAt':time.time()};(b/'source257-native-guard-controls-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['status','compileExit','runExit']}));print(c.stderr[:1500]);print(r.stderr[:1500] if r else '')
