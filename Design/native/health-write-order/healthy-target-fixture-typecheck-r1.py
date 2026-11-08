from pathlib import Path
import json,tempfile,subprocess,time,hashlib
b=Path('Design/native/health-write-order');path=Path('Lumen/Views/HealthHealthyTargetChangeUIFixture.swift');src=path.read_bytes();old=json.loads((b/'source239-test-typecheck-r1.json').read_text())
stubs='''import Foundation
final class BackupOperationControl {}
enum AppGroup { static let id = "group.com.dbakp.lumen" }
enum HealthLocalFiles {
 enum Domain: String, Hashable { case meals, workouts }
 static func validateCurrentData(_ data: Data, domain: Domain) throws {}
 static func readRegularData(_ file: URL, limit: Int) throws -> Data { Data() }
}
enum HealthLegacyOriginUIFixture { static let data = Data("{synthetic persisted legacy origin damaged".utf8) }
enum LocalStore { static func performWrite<T>(_ body: () throws -> T) rethrows -> T { try body() } }
struct OriginStub { func verify(in root: URL, legacy: (String) throws -> Any?, control: BackupOperationControl) throws {} }
final class BackupRecoveryReviewSession {
 struct Metadata { let legacyDomains: Set<HealthLocalFiles.Domain> }
 let id = UUID(); var originMetadata: Metadata?
 func acquireOrigins(_ domains: Set<HealthLocalFiles.Domain>, control: BackupOperationControl) throws -> [HealthLocalFiles.Domain: OriginStub] { [:] }
}
'''
with tempfile.TemporaryDirectory(prefix='lumen241-fixture-typecheck-') as tmp:
 p=Path(tmp)/path.name;p.write_bytes(src);stub=Path(tmp)/'stubs.swift';stub.write_text(stubs);command=old['command'][:-1]+['-D','DEBUG',str(stub),str(p)];r=subprocess.run(command,capture_output=True,text=True);out={'status':'PASS entire healthyfixture actualSDK SwiftUI typing with dependency stubs' if r.returncode==0 else 'FAILED healthyfixture isolatedtyping','source':str(path),'sourceBytes':len(src),'sourceSHA256':hashlib.sha256(src).hexdigest(),'command':command,'dependencyStubs':stubs,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'scope':'All actualfixture SwiftUI/Dictionary/Context code typing only; production dependencies stubbed, no appbuild/runtime/filemutation/authority proof','checkedAt':time.time()};(b/'source241-fixture-typecheck-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'exit':r.returncode,'stdoutBytes':len(r.stdout),'stderrBytes':len(r.stderr),'stderrPrefix':r.stderr[:1800]}))
