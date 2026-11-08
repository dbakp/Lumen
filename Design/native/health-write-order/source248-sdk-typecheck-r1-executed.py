"""Actual iOS SDK typing; no application build, launch, reset or phone operation."""
from pathlib import Path
import concurrent.futures,hashlib,json,subprocess,tempfile,time
B=Path(__file__).resolve().parent;R=B.parents[2]
old=json.loads((B/'source239-test-typecheck-r1.json').read_bytes());base=old['command'][:-1]
stubs='''import Foundation
final class BackupOperationControl { func cancel() {} ; func checkCancellation() throws {} }
enum AppGroup { static let id = "group.com.dbakp.lumen" }
enum HealthLocalFiles { enum Domain: String, Hashable { case meals, workouts } }
final class BackupRecoveryReviewSession { let id = UUID() }
enum HealthLegacyTargetChangeUIFixture {
 enum Failure: Error { case invalidContext, invalidObservation }
 static var requested: Bool { false }; static var phase: String { "ready" }
 static func confirmationBinding(_ session: UUID) throws -> [String:String] { [:] }
 static func change(_ session: BackupRecoveryReviewSession) {}
}
'''
def check(kind,path):
 source=path.read_bytes()
 with tempfile.TemporaryDirectory(prefix='lumen246-'+kind+'-typing-') as folder:
  copied=Path(folder)/path.name;copied.write_bytes(source)
  command=base.copy()
  if kind=='gate':
   stub=Path(folder)/'stubs.swift';stub.write_text(stubs);command+=['-D','DEBUG',str(stub)]
  command+=[str(copied)];run=subprocess.run(command,capture_output=True)
  result={'status':'PASS actualSDK typecheck' if run.returncode==0 else 'FAILED actualSDK typecheck','kind':kind,'file':str(path.relative_to(R)),'sourceBytes':len(source),'sourceSHA256':hashlib.sha256(source).hexdigest(),'command':command,'exit':run.returncode,'stdout':run.stdout.decode(),'stderr':run.stderr.decode(),'dependencyStubs':stubs if kind=='gate' else None,'scope':'Whole UITest actualSDK typing or whole gate actualSDK typing with dependencies stubbed; no full app/runtime/alert/runner/authority/cancellation acceptance','checkedAt':time.time()}
  (B/('source248-'+kind+'-sdk-typecheck-r1.json')).write_text(json.dumps(result,indent=2)+'\n');return {k:result[k] for k in ['kind','exit','stderr']}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 futures=[pool.submit(check,'uitest',R/'LumenUITests/LumenSmokeTests.swift')]
 for f in futures:print(json.dumps(f.result()))
