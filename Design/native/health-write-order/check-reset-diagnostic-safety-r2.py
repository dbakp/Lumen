"""Execute actual diagnostic guard/entry fragments with fake endpoints only."""
from pathlib import Path
import base64,gzip,hashlib,json,subprocess,tempfile,time
BASE=Path(__file__).resolve().parent;REPO=BASE.parents[2]
raw=Path(tempfile.mkdtemp(prefix='LumenResetDiagnosticSafetyR2-',dir='/tmp'));sha=lambda d:hashlib.sha256(d).hexdigest()
fixture=(REPO/'Lumen/Views/HealthRecoveryCancelUIFixture.swift').read_text();app=(REPO/'Lumen/LumenApp.swift').read_text();delegate=(REPO/'Lumen/Services/HealthBackgroundSync.swift').read_text()
a=fixture.index('    static func context(_ args: [String])');b=fixture.index('    static var runID: UUID?',a);context=fixture[a:b]
a=fixture.index('    static let diagnosticProtocol =');b=fixture.index('    /// Small explicit synthetic intent/private-copy fixture',a);methods=fixture[a:b]
a=app.index('        do { try HealthLegacyResetUIFixture.preflightIfRequested() }');b=app.index('        if ProcessInfo.processInfo.arguments.contains("-resetForUITests")',a);entry=app[a:b]
assert app.index('HealthLegacyResetDiagnosticView()') < app.index('else if protectedDataAvailable { LumenReadyView() }')
assert delegate.index('HealthLegacyResetUIFixture.diagnosticOnly { return true }') < delegate.index('        HealthBackgroundSync.shared.start()')
# No Security import: all credential/default endpoints below are mocks. The
# actual unchanged method fragments are inserted verbatim between those mocks.
swift='''import Foundation
import CoreFoundation
import Darwin
typealias OSStatus = Int32
let errSecSuccess: OSStatus = 0
let errSecItemNotFound: OSStatus = -25300
let kSecClass = "class", kSecClassGenericPassword = "genp", kSecAttrService = "svce"
let kSecReturnAttributes = "returnAttrs", kSecMatchLimit = "limit", kSecMatchLimitAll = "all"
let scenario = ProcessInfo.processInfo.environment["LUMEN_DIAGNOSTIC_SCENARIO"]!
var queryCalls = 0
func SecItemCopyMatching(_ request: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    queryCalls += 1
    let dict = request as NSDictionary
    precondition(dict["returnAttrs"] as? Bool == true && dict["returnData"] == nil)
    if scenario == "credential-present" {
        result?.pointee = [["acct":"MUST-NOT-EXPORT-ACCOUNT", "v_Data":"MUST-NOT-EXPORT-SECRET"], [:]] as CFArray
        return 0
    }
    return scenario == "credential-unavailable" ? -34018 : -25300
}
class UserDefaults {
    static let standard = UserDefaults()
    func bool(forKey key: String) -> Bool { precondition(key == "lumen.health.connected"); return scenario == "health-connected" }
    func object(forKey key: String) -> Any? {
        let known = ["lumen.llm.key", "lumen.llm.oauth.token", "lumen.llm.oauth.refresh", "lumen.llm.oauth.account.v2", "lumen.llm.connection.v3", "strava.clientID", "strava.clientSecret", "strava.token", "strava.refresh"]
        precondition(known.contains(key))
        return scenario == "legacy-provider-present" && key == "lumen.llm.key" ? "MUST-NOT-EXPORT-LEGACY-VALUE" : nil
    }
}
@MainActor enum HealthLegacyResetUIFixture {
    enum Failure: Error { case unsafeContext, invalidObservation }
    private static var parent: URL? {
        scenario == "no-parent" ? nil : URL(fileURLWithPath: ProcessInfo.processInfo.environment["LUMEN_DIAGNOSTIC_DIRECTORY"]!)
    }
'''+context+methods+'''}
@main struct Harness {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LUMEN_DIAGNOSTIC_DIRECTORY"]!)
        var resetCalls = 0
        if scenario == "write-failure" {
            let file = directory.appendingPathComponent("Lumen-legacy-reset-preflight-diagnostic-7ee08113-f268-410a-b3cd-46d270370f08-" + String(getpid()) + ".json")
            try Data("Synthetic existing diagnostic sentinel".utf8).write(to: file)
        }
        func executeActualEntryFragment() {
'''+entry+'''            resetCalls += 1 // A stand-in counter, NEVER LocalStore or a real reset.
        }
        executeActualEntryFragment()
        let output: [String: Any] = ["scenario":scenario, "resetCalls":resetCalls, "queryCalls":queryCalls,
            "diagnosticOutcome":HealthLegacyResetUIFixture.diagnosticOutcome]
        print(String(data: try JSONSerialization.data(withJSONObject:output, options:[.sortedKeys]), encoding:.utf8)!)
    }
}
'''
source=raw/'DiagnosticSafety.swift';binary=raw/'DiagnosticSafety';source.write_text(swift)
compiled=subprocess.run(['xcrun','swiftc','-parse-as-library',str(source),'-o',str(binary)],capture_output=True,text=True);(raw/'build.log').write_text(compiled.stdout+compiled.stderr)
assert compiled.returncode==0,compiled.stderr
args=['-resetForUITests','-health-backup-ui-fixture','-health-backup-case','legacy','-health-backup-healthy-merge-ui','-health-backup-empty-ui',
      '-health-legacy-origin-ui','data','-health-legacy-reset-ui','-health-legacy-reset-run','7EE08113-F268-410A-B3CD-46D270370F08','-health-legacy-reset-diagnostic-only']
scenarios={'approved-empty':('approved-initial',1), 'credential-present':('blocked-credentials-present',1),
 'credential-unavailable':('blocked-credential-query-status',1), 'health-connected':('blocked-health-connected',0),
 'legacy-provider-present':('blocked-legacy-provider-setting',1), 'malformed-context':('blocked-context',0),
 'observer-diagnostic-conflict':('blocked-context',0),'write-failure':('diagnostic-write-failed',1),'no-parent':('diagnostic-write-failed',1)}
rows=[]
for name,(expected,queries) in scenarios.items():
 folder=raw/name;folder.mkdir();actual_args=list(args)
 if name=='malformed-context':actual_args[actual_args.index('-health-legacy-reset-run')+1]='invalid'
 if name=='observer-diagnostic-conflict':actual_args[actual_args.index('-health-legacy-reset-ui')]='-health-legacy-reset-observer'
 env=dict(__import__('os').environ,LUMEN_DIAGNOSTIC_SCENARIO=name,LUMEN_DIAGNOSTIC_DIRECTORY=str(folder))
 run=subprocess.run([str(binary),*actual_args],env=env,capture_output=True,text=True);(folder/'run.log').write_text(run.stdout+run.stderr);assert run.returncode==0,(name,run.stderr)
 result=json.loads(run.stdout);assert result['resetCalls']==0 and result['queryCalls']==queries and result['diagnosticOutcome']==expected,result
 files=list(folder.glob('Lumen-legacy-reset-preflight-diagnostic-*.json'))
 if name=='no-parent':assert not files
 elif name=='write-failure':assert len(files)==1 and files[0].read_bytes()==b'Synthetic existing diagnostic sentinel'
 else:
  assert len(files)==1;payload=files[0].read_bytes();diagnostic=json.loads(payload)
  assert diagnostic['classification']==expected and diagnostic['diagnosticOnly'] is True
  assert not any(secret in payload for secret in [b'MUST-NOT-EXPORT',b'v_Data',b'"acct"'])
  if name=='credential-present':assert diagnostic['credentialQueryOSStatus']==0 and diagnostic['credentialAttributeMatchCount']==2
  if name=='credential-unavailable':assert diagnostic['credentialQueryOSStatus']==-34018
  if name=='approved-empty':assert diagnostic['guardApproved'] is True and diagnostic['knownLegacyProviderKeysPresent']==[]
  else:assert diagnostic['guardApproved'] is False
 rows.append({'case':name,'exit':run.returncode,**result,'actualDiagnosticFiles':len(files),'secretPayloadExported':False})
files={}
for p in sorted(raw.rglob('*')):
 if p.is_file() and p!=binary:
  data=p.read_bytes();files[str(p.relative_to(raw))]={'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()}
archive=BASE/'reset-diagnostic-safety-r2-fixtures.json.gz';archive.write_bytes(gzip.compress(json.dumps({'files':files},separators=(',',':')).encode(),mtime=0))
provenance=[]
for p in [REPO/'Lumen/LumenApp.swift',REPO/'Lumen/Views/HealthRecoveryCancelUIFixture.swift',REPO/'Lumen/Services/HealthBackgroundSync.swift',BASE/'check-reset-diagnostic-safety-r2.py']:
 data=p.read_bytes();provenance.append({'file':str(p.relative_to(REPO)),'bytes':len(data),'sha256':sha(data)})
out={'status':'PASS9 isolated exact guard/entry fragments with mocked credential/default endpoints; no app/simulator/reset acceptance','cases':rows,
 'actualSourceFragments':{name:{'bytes':len(value.encode()),'sha256':sha(value.encode())} for name,value in [('context',context),('diagnosticMethods',methods),('initializerEntry',entry)]},
 'provenance':provenance,'fixtureArchive':{'file':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive.read_bytes()),'payloadFiles':len(files)},
 'temporaryDirectory':str(raw),'compiledExecutableBytes':binary.stat().st_size,'scope':'Actual extracted Swift guard/record/entry code executed with mocked Security/UserDefaults/metadata directory; reset stand-in counter0 in9scenarios, no credential payload serialized. Source order checks for diagnostic body and delegate guard only, not native UI/lifecycle proof.',
 'physicalDeviceActions':False,'checkedAt':time.time()};(BASE/'reset-diagnostic-safety-r2-outcome.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'status':out['status'],'smallPayloads':len(files),'temporaryDirectory':str(raw)}))
