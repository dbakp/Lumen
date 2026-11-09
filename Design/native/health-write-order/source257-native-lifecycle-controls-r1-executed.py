"""Execute whole actual gate/trace on macOS with explicit environment stubs."""
from pathlib import Path
import gzip,hashlib,json,subprocess,tempfile,time
B=Path(__file__).resolve().parent;R=B.parents[2]
sha=lambda x:hashlib.sha256(x).hexdigest()
stubs=r'''import Foundation
import CryptoKit
import Darwin
enum Bundle { struct Main { let bundleIdentifier: String? = "com.dbakp.lumen" }; static let main = Main() }
enum ProcessInfo { struct Process { let arguments = ["-health-legacy-confirmation-window-ui", "-health-legacy-confirmation-lifecycle-ui", "-health-legacy-confirmation-expiry-ui"] }; static let processInfo = Process() }
enum Harness { static var parent: URL?; static var changes = 0; static var rows = [[String:Any]]() }
final class BackupOperationControl { private(set) var verificationCancelled=false; func cancel() { verificationCancelled=true }; func checkCancellation() throws { if verificationCancelled { throw CancellationError() } } }
enum AppGroup { static let id="isolated" }
enum HealthLocalFiles { enum Domain: String, Hashable { case meals,workouts } }
final class BackupRecoveryReviewSession { let id=UUID() }
enum HealthLegacyTargetChangeUIFixture {
 enum Failure: Error { case invalidContext,invalidObservation }
 struct Context { let kind="data" }
 static let lifecycleFlag="-health-legacy-confirmation-lifecycle-ui"
 static let expiryFlag="-health-legacy-confirmation-expiry-ui"
 static let run=UUID(); static var captures=[UUID:UUID]()
 static var requested: Bool { true }; static var phase: String { "ready" }
 static func context(_ args:[String]) throws -> Context? { Context() }
 static func confirmationBinding(_ session:UUID) throws -> [String:String] {
  if captures[session]==nil { captures[session]=UUID() }
  return ["runID":run.uuidString,"pid":String(getpid()),"sessionID":session.uuidString,"captureID":captures[session]!.uuidString]
 }
 static func change(_ session:BackupRecoveryReviewSession) { Harness.changes += 1 }
 @MainActor static func confirmationLifecycleFacts(session:UUID,capture:String) throws -> [String:Any] {
  ["healthConnected":false,"knownKeyWritten":false,"originalValuesVerified":true,
   "fixtureFlags":["singleUseConsumed":false,"knownKeyWritten":false,"failed":false],
   "fixtureBinding":try confirmationBinding(session),"fixed":["stub":"explicit-no-real-preferences"],
   "readStartedAt":Date().timeIntervalSince1970,"readFinishedAt":Date().timeIntervalSince1970]
 }
}
'''
harness=r'''import Foundation
@main struct Main {
 @MainActor static func main() async throws {
  Harness.parent=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  let session=BackupRecoveryReviewSession()
  let gate=try HealthConfirmationTargetChangeGate(session:session,appearance:UUID(),domains:[.meals],legacyDomains:[.meals],omitPhotos:false)
  let meta=gate.lifecycle!
  func trace() throws -> [String:Any] { try JSONSerialization.jsonObject(with:Data(contentsOf:meta.trace)) as! [String:Any] }
  let clock=ContinuousClock.now
  let task=Task { @MainActor in
   var exit="returned";gate.noteWaiterStarted();defer { gate.noteWaiterExit(errorType:exit) }
   do { try await gate.waitAndChange(session,stillPresented:{true}) }
   catch is CancellationError { exit="CancellationError" }
   catch { exit=String(reflecting:type(of:error)) }
  }
  await task.value
  let elapsed=clock.duration(to:ContinuousClock.now).components
  let expired=try trace(),events=expired["events"] as! [[String:Any]]
  precondition(elapsed.seconds>=90 && events.count==4)
  precondition(events.map{$0["event"] as! String}==["created","wait-started","closed","wait-exit"])
  precondition(events[2]["reason"] as? String=="deadline")
  precondition(events[3]["taskCancelled"] as? Bool==false && events[3]["controlCancelled"] as? Bool==true)
  precondition(events[3]["expiryClock"] as? String=="ContinuousClock" && events[3]["expiryLimitSeconds"] as? Int==90)
  precondition((events[3]["expiryElapsedSeconds"] as? Int64 ?? -1)>=90)
  precondition(HealthConfirmationLifecycleTrace.check(session:session.id,request:UUID())=="check-failed")
  // The rejected early Check intentionally records a problem; start a fresh
  // metadata-only record is impossible by design, so do not claim a native pass.
  gate.close(reason:"not-now");task.cancel()
  HealthConfirmationLifecycleTrace.observeCompletion(of:task,metadata:meta)
  for _ in 0..<100 {
   if ((try trace())["events"] as! [[String:Any]]).last?["event"] as? String=="task-value-completed" { break }
   try await Task.sleep(for:.milliseconds(5))
  }
  let completed=try trace(),done=completed["events"] as! [[String:Any]]
  precondition(done.count==5 && done[2]["reason"] as? String=="deadline")
  var ack=meta.binding.filter{["runID","pid","sessionID","captureID","nonce"].contains($0.key)};ack["phase"]="ui-observed"
  let bytes=try JSONSerialization.data(withJSONObject:ack,options:[.sortedKeys]);try bytes.write(to:meta.acknowledgement,options:.withoutOverwriting)
  let answer=HealthConfirmationLifecycleTrace.check(session:session.id,request:UUID())
  precondition(answer=="checked-1" && Harness.changes==0)
  print(String(data:try JSONSerialization.data(withJSONObject:["expiredTrace":expired,"completedTrace":completed,"finalTrace":try trace(),"actualChanges":Harness.changes,"answer":answer,"outerElapsedSeconds":elapsed.seconds,"outerElapsedAttoseconds":elapsed.attoseconds],options:[.sortedKeys]),encoding:.utf8)!)
 }
}
'''

inputs={};copies=[]
for name in ['HealthConfirmationTargetChangeGate.swift','HealthConfirmationLifecycleTrace.swift']:
 file='Lumen/Views/'+name;raw=(R/file).read_bytes();text=raw.decode();assert text.startswith('#if DEBUG && targetEnvironment(simulator)\n') and text.endswith('#endif\n')
 body=text[len('#if DEBUG && targetEnvironment(simulator)\n'):-len('#endif\n')]
 before='FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)';assert body.count(before)==1;body=body.replace(before,'Harness.parent')
 inputs[file]={'bytes':len(raw),'sha256':sha(raw)};copies.append((name,body))
with tempfile.TemporaryDirectory(prefix='lumen257-native-lifecycle-') as temp:
 root=Path(temp);sources=[]
 for name,text in [('stubs.swift',stubs),*copies,('main.swift',harness)]:
  file=root/name;file.write_text(text);sources.append(str(file))
 binary=root/'controls';command=['xcrun','swiftc','-parse-as-library','-module-name','Lumen',*sources,'-o',str(binary)]
 compile=subprocess.run(command,capture_output=True,text=True)
 run=subprocess.run([str(binary),str(root)],capture_output=True,text=True,timeout=125) if compile.returncode==0 else None
 full={'inputs':inputs,'transforms':['Remove wholefile DEBUG+sim wrapper for macOS execution','Replace exactly one appgroup container lookup per actual file with isolated Harness.parent'], 'stubs':stubs,'harness':harness,'compiledCopies':dict(copies),'compileCommand':command,'compileExit':compile.returncode,'compileStdout':compile.stdout,'compileStderr':compile.stderr,'runExit':run.returncode if run else None,'runStdout':run.stdout if run else None,'runStderr':run.stderr if run else None}
 raw=json.dumps(full).encode();fixture='source257-native-lifecycle-controls-r1-fixtures.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(raw,mtime=0))
 result={'status':'PASS actual whole gate+trace isolated real90second deadline' if run and run.returncode==0 else 'FAILED isolated scheduling preparation','fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':sha(raw),'sources':inputs,'compileExit':compile.returncode,'runExit':run.returncode if run else None,'scope':'Actual unshortened90second gate+trace task scheduling/files/lateack/check with explicit Bundle/arguments/container/control/session/fixed preference stubs on macOS. No current iOS build/native alert/real preferences/release reference/FD/runtime acceptance.','checkedAt':time.time()}
 out=B/'source257-native-lifecycle-controls-r1.json';assert not out.exists();out.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result));print(compile.stderr[:2500]);print(run.stderr[:1000] if run else '')
