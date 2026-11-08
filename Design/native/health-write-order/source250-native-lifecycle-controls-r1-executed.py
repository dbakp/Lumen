"""Execute whole actual gate/trace on macOS with explicit environment stubs."""
from pathlib import Path
import gzip,hashlib,json,subprocess,tempfile,time
B=Path(__file__).resolve().parent;R=B.parents[2]
sha=lambda x:hashlib.sha256(x).hexdigest()
stubs=r'''import Foundation
import CryptoKit
import Darwin
enum Bundle { struct Main { let bundleIdentifier: String? = "com.dbakp.lumen" }; static let main = Main() }
enum ProcessInfo { struct Process { let arguments = ["-health-legacy-confirmation-window-ui", "-health-legacy-confirmation-lifecycle-ui"] }; static let processInfo = Process() }
enum Harness { static var parent: URL?; static var changes = 0; static var rows = [[String:Any]]() }
final class BackupOperationControl { private(set) var verificationCancelled=false; func cancel() { verificationCancelled=true }; func checkCancellation() throws { if verificationCancelled { throw CancellationError() } } }
enum AppGroup { static let id="isolated" }
enum HealthLocalFiles { enum Domain: String, Hashable { case meals,workouts } }
final class BackupRecoveryReviewSession { let id=UUID() }
enum HealthLegacyTargetChangeUIFixture {
 enum Failure: Error { case invalidContext,invalidObservation }
 struct Context { let kind="data" }
 static let lifecycleFlag="-health-legacy-confirmation-lifecycle-ui"
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
harness=r'''@main struct Main {
 @MainActor static func run(_ name:String, beforeStart:Bool, badAck:Bool=false, duplicate:Bool=false) async throws {
  let session=BackupRecoveryReviewSession()
  let gate=try HealthConfirmationTargetChangeGate(session:session,appearance:UUID(),domains:[.meals],legacyDomains:[.meals],omitPhotos:false)
  let meta=gate.lifecycle!
  func trace() throws -> [String:Any] { try JSONSerialization.jsonObject(with:Data(contentsOf:meta.trace)) as! [String:Any] }
  if beforeStart { gate.close(reason:"not-now") }
  let task=Task { @MainActor in
   var exit="returned";gate.noteWaiterStarted();defer { gate.noteWaiterExit(errorType:exit) }
   do { try await gate.waitAndChange(session,stillPresented:{true}) }
   catch is CancellationError { exit="CancellationError" }
   catch { exit=String(reflecting:type(of:error)) }
  }
  if !beforeStart {
   for _ in 0..<100 {
    if ((try trace())["events"] as! [[String:Any]]).contains(where:{$0["event"] as? String == "wait-started"}) { break }
    try await Task.sleep(for:.milliseconds(5))
   }
  }
  gate.close(reason:"not-now");gate.close(reason:"duplicate-close");task.cancel()
  HealthConfirmationLifecycleTrace.observeCompletion(of:task,metadata:meta)
  for _ in 0..<100 {
   if ((try trace())["events"] as! [[String:Any]]).last?["event"] as? String == "task-value-completed" { break }
   try await Task.sleep(for:.milliseconds(5))
  }
  let completed=try trace(),events=completed["events"] as! [[String:Any]]
  precondition(events.last?["event"] as? String == "task-value-completed")
  precondition(events.filter{$0["event"] as? String == "closed"}.count==1)
  precondition((events.first{$0["event"] as? String == "closed"})?["reason"] as? String == "not-now")
  precondition(events.contains{$0["event"] as? String == "wait-exit" && $0["errorType"] as? String == "CancellationError"})
  var ack=meta.binding.filter{["runID","pid","sessionID","captureID","nonce"].contains($0.key)}
  ack["phase"]="ui-observed";if badAck { ack["nonce"]=UUID().uuidString }
  let bytes=try JSONSerialization.data(withJSONObject:ack,options:[.sortedKeys])
  try bytes.write(to:meta.acknowledgement,options:.withoutOverwriting)
  let answer=HealthConfirmationLifecycleTrace.check(session:session.id,request:UUID())
  precondition(answer==(badAck ? "check-failed" : "checked-1"))
  let file=meta.trace.deletingPathExtension().appendingPathExtension("check-1.json")
  let check=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
  let facts=check["check"] as! [String:Any],raw=facts["acknowledgement"] as! [String:Any]
  precondition(raw["base64"] as? String==bytes.base64EncodedString())
  if badAck { precondition(facts["nativeFacts"]==nil) }
  if duplicate { precondition(HealthConfirmationLifecycleTrace.check(session:session.id,request:UUID())=="check-failed") }
  precondition(Harness.changes==0)
  Harness.rows.append(["case":name,"beforeStart":beforeStart,"badAck":badAck,"duplicate":duplicate,
   "trace":try trace(),"checkFile":check,"actualChanges":Harness.changes,"answer":answer])
 }
 @MainActor static func main() async throws {
  Harness.parent=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  try await run("close-before-start",beforeStart:true)
  try await run("close-while-waiting-double-close",beforeStart:false)
  try await run("wrong-late-nonce-raw-retained",beforeStart:false,badAck:true)
  try await run("duplicate-check-rejected",beforeStart:false,duplicate:true)
  print(String(data:try JSONSerialization.data(withJSONObject:["cases":Harness.rows],options:[.sortedKeys]),encoding:.utf8)!)
 }
}
'''
inputs={};copies=[]
for name in ['HealthConfirmationTargetChangeGate.swift','HealthConfirmationLifecycleTrace.swift']:
 file='Lumen/Views/'+name;raw=(R/file).read_bytes();text=raw.decode();assert text.startswith('#if DEBUG && targetEnvironment(simulator)\n') and text.endswith('#endif\n')
 body=text[len('#if DEBUG && targetEnvironment(simulator)\n'):-len('#endif\n')]
 before='FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)';assert body.count(before)==1;body=body.replace(before,'Harness.parent')
 inputs[file]={'bytes':len(raw),'sha256':sha(raw)};copies.append((name,body))
with tempfile.TemporaryDirectory(prefix='lumen250-native-lifecycle-') as temp:
 root=Path(temp);sources=[]
 for name,text in [('stubs.swift',stubs),*copies,('main.swift',harness)]:
  file=root/name;file.write_text(text);sources.append(str(file))
 binary=root/'controls';command=['xcrun','swiftc','-parse-as-library',*sources,'-o',str(binary)]
 compile=subprocess.run(command,capture_output=True,text=True)
 run=subprocess.run([str(binary),str(root)],capture_output=True,text=True,timeout=30) if compile.returncode==0 else None
 full={'inputs':inputs,'transforms':['Remove wholefile DEBUG+sim wrapper for macOS execution','Replace exactly one appgroup container lookup per actual file with isolated Harness.parent'], 'stubs':stubs,'harness':harness,'compiledCopies':dict(copies),'compileCommand':command,'compileExit':compile.returncode,'compileStdout':compile.stdout,'compileStderr':compile.stderr,'runExit':run.returncode if run else None,'runStdout':run.stdout if run else None,'runStderr':run.stderr if run else None}
 raw=json.dumps(full).encode();fixture='source250-native-lifecycle-controls-r1-fixtures.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(raw,mtime=0))
 result={'status':'PASS actual whole gate+trace isolated scheduling' if run and run.returncode==0 else 'FAILED isolated scheduling preparation','fixture':fixture,'decodedBytes':len(raw),'decodedSHA256':sha(raw),'sources':inputs,'compileExit':compile.returncode,'runExit':run.returncode if run else None,'scope':'Actual gate+trace task scheduling/files/lateack/native check with explicit Bundle/arguments/container/control/session/fixed preference stubs on macOS. No current iOS build/native alert/real preferences/release reference/FD/runtime acceptance.','checkedAt':time.time()}
 out=B/'source250-native-lifecycle-controls-r1.json';assert not out.exists();out.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result));print(compile.stderr[:2500]);print(run.stderr[:1000] if run else '')
