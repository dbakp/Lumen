"""Run actual production reveal/guard methods under deterministic yield gates.
No SwiftUI, native focus, transaction or screen acceptance is claimed here.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile,time,gzip
B=Path(__file__).resolve().parent;repo=B.parents[2]
source=(repo/'Lumen/Views/BackupFileRecoveryView.swift').read_text()
metadata=source[source.index('    private struct RecoveryCompletion:'):source.index('    @State private var completion:')].replace('private struct','struct')
methods=source[source.index('    private func cancelSuccessReveal()'):source.index('    private func startOriginCapture()')]
# Replace only the scheduling primitive: gates stop at the two real yield sites.
assert methods.count('await Task.yield()')==2
methods=methods.replace('await Task.yield()','await gate.pause()')
harness='''import Foundation
@MainActor final class YieldGate {
 var pending: CheckedContinuation<Void, Never>?
 func pause() async { await withCheckedContinuation { pending = $0 } }
 func wait() async { while pending == nil { await Task.yield() } }
 func advance() { let c = pending; pending = nil; c!.resume() }
}
@MainActor final class ScrollViewProxy {
 enum Anchor { case top }
 var targets: [String] = []
 func scrollTo(_ value: String, anchor: Anchor) { targets.append(value) }
}
@MainActor final class Subject {
 struct Session { var id = UUID() }
''' + metadata + '''
 var completion: RecoveryCompletion?
 var successReveal: Task<Void, Never>?
 var recoverySuccessFocused = false
 var reviewActive = true, recovered = true, busy = false
 var issue: String?, operation: String?
 var appearanceID = UUID(), attemptID = UUID(), session = Session()
 let gate = YieldGate()
 func cancel() { cancelSuccessReveal() }
 func begin(_ scroll: ScrollViewProxy) {
  let value = RecoveryCompletion(sessionID: session.id, appearanceID: appearanceID, attemptID: attemptID)
  completion = value; revealSuccess(value, scroll: scroll)
 }
''' + methods + '''
}
@main struct Run {
 @MainActor static func main() async {
  var results: [[String: Any]] = []
  for stage in 0...1 {
   for change in ["none", "cancel", "back", "new-appearance", "new-attempt", "new-session", "replacement", "error", "busy", "operation", "not-recovered"] {
    let s = Subject(), scroll = ScrollViewProxy()
    s.begin(scroll); let task = s.successReveal!
    await s.gate.wait()
    if stage == 1 { s.gate.advance(); await s.gate.wait() }
    switch change {
    case "cancel": s.cancel()
    case "back": s.reviewActive = false
    case "new-appearance": s.appearanceID = UUID()
    case "new-attempt": s.attemptID = UUID()
    case "new-session": s.session.id = UUID()
    case "replacement": s.completion = Subject.RecoveryCompletion(sessionID: s.session.id, appearanceID: s.appearanceID, attemptID: s.attemptID)
    case "error": s.issue = "new failure"
    case "busy": s.busy = true
    case "operation": s.operation = "new operation"
    case "not-recovered": s.recovered = false
    default: break
    }
    s.gate.advance()
    if stage == 0 && change == "none" { await s.gate.wait(); s.gate.advance() }
    await task.value
    precondition(scroll.targets == (stage == 1 || change == "none" ? ["fileHealthRecoverySuccess"] : []), "stale scroll: \\(change)")
    precondition(s.recoverySuccessFocused == (change == "none"), "stale focus: \\(change)")
    // Finishing the task does not replay the reveal on later reads.
    await Task.yield(); precondition(scroll.targets.count <= 1)
    results.append(["yieldStage":stage,"change":change,"scrollCount":scroll.targets.count,"focus":s.recoverySuccessFocused])
   }
  }
  let data = try! JSONSerialization.data(withJSONObject: results, options:[.sortedKeys]); print(String(decoding:data,as:UTF8.self))
 }
}
'''
with tempfile.TemporaryDirectory(prefix='lumen235-reveal-') as tmp:
 path=Path(tmp);(path/'main.swift').write_text(harness)
 command=['xcrun','swiftc','-parse-as-library',str(path/'main.swift'),'-o',str(path/'controls')]
 compile=subprocess.run(command,capture_output=True,text=True)
 assert compile.returncode==0,compile.stderr
 run=subprocess.run([str(path/'controls')],capture_output=True,text=True,timeout=30)
 assert run.returncode==0,run.stderr
 results=json.loads(run.stdout);assert len(results)==22
archive={'harness':harness,'productionMetadata':metadata,'productionMethods':source[source.index('    private func cancelSuccessReveal()'):source.index('    private func startOriginCapture()')],'compileExit':compile.returncode,'compileStdout':compile.stdout,'compileStderr':compile.stderr,'runExit':run.returncode,'runStdout':run.stdout,'runStderr':run.stderr,'results':results}
raw=json.dumps(archive,indent=2).encode();name='source235-success-reveal-controls-r1-fixtures.json.gz';(B/name).write_bytes(gzip.compress(raw,mtime=0))
report={'status':'PASS22 deterministic interleavings of extracted actual production guard/reveal/cancel methods','sourceFile':'Lumen/Views/BackupFileRecoveryView.swift','sourceSHA256':hashlib.sha256(source.encode()).hexdigest(),'cases':22,'yieldStages':2,'substitution':'Only Task.yield replaced by controlled continuations; SwiftUI proxy/state wrappers replaced with isolated observable stand-ins. Actual Task cancellation preserved.','archive':name,'archiveDecodedBytes':len(raw),'archiveDecodedSHA256':hashlib.sha256(raw).hexdigest(),'results':results,'scope':'No native SwiftUI layout/focus/speech/transaction acceptance. Real UI no-test-scroll check and full native closure/audit still required.','checkedAt':time.time()}
(B/'source235-success-reveal-controls-r1.json').write_text(json.dumps(report,indent=2)+'\n');print(report['status'])
