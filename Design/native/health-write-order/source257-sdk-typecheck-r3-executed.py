"""Current whole native test and actual lifecycle trace/gate SDK typing only."""
from pathlib import Path
import concurrent.futures,hashlib,json,subprocess,tempfile,time
B=Path(__file__).resolve().parent;R=B.parents[2]
base=json.loads((B/'source239-test-typecheck-r1.json').read_bytes())['command'][:-1]
stubs='''import Foundation
final class BackupOperationControl { var verificationCancelled: Bool { false }; func cancel() {}; func checkCancellation() throws {} }
enum AppGroup { static let id = "group.com.dbakp.lumen" }
enum HealthLocalFiles { enum Domain: String, Hashable { case meals, workouts } }
final class BackupRecoveryReviewSession { let id = UUID() }
enum HealthLegacyTargetChangeUIFixture {
 enum Failure: Error { case invalidContext, invalidObservation }
 struct Context { let kind: String }
 static let lifecycleFlag = "-health-legacy-confirmation-lifecycle-ui"
 static let expiryFlag = "-health-legacy-confirmation-expiry-ui"
 static var requested: Bool { false }; static var phase: String { "ready" }
 static func context(_ args: [String]) throws -> Context? { nil }
 static func confirmationBinding(_ session: UUID) throws -> [String:String] { [:] }
 static func change(_ session: BackupRecoveryReviewSession) {}
 @MainActor static func confirmationLifecycleFacts(session: UUID, capture: String) throws -> [String:Any] { [:] }
}
'''
def check(kind,names):
 with tempfile.TemporaryDirectory(prefix='lumen257-'+kind+'-typing-') as folder:
  command=base.copy();sources=[]
  if kind=='lifecycle':
   stub=Path(folder)/'stubs.swift';stub.write_text(stubs);command+=['-D','DEBUG',str(stub)]
  for name in names:
   raw=(R/name).read_bytes();copied=Path(folder)/Path(name).name;copied.write_bytes(raw);command.append(str(copied));sources.append({'file':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
  run=subprocess.run(command,capture_output=True)
  result={'status':'PASS actualSDKtyping' if run.returncode==0 else 'FAILED actualSDKtyping','kind':kind,'sources':sources,'command':command,'exit':run.returncode,'stdout':run.stdout.decode(),'stderr':run.stderr.decode(),'stubs':stubs if kind=='lifecycle' else None,'scope':'Whole actual UITest without stubs or whole actual gate+trace with named dependencies stubbed; no full currentapp build/native/closure/lateack/probe/runtime acceptance','checkedAt':time.time()}
  target=B/('source257-'+kind+'-sdk-typecheck-r3.json');assert not target.exists();target.write_text(json.dumps(result,indent=2)+'\n');return {'kind':kind,'exit':run.returncode,'stderr':result['stderr']}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 futures=[pool.submit(check,'uitest',['LumenUITests/LumenSmokeTests.swift']),pool.submit(check,'lifecycle',['Lumen/Views/HealthConfirmationTargetChangeGate.swift','Lumen/Views/HealthConfirmationLifecycleTrace.swift'])]
 for f in futures:print(json.dumps(f.result()),flush=True)
