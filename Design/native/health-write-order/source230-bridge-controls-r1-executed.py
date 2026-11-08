from pathlib import Path
import subprocess,tempfile,json,hashlib
source=Path('Lumen/Views/HealthLegacyTargetChangeUIFixture.swift').read_text()
fragment=source[source.index('    private final class Bridge:'):source.index('\n}\n\n@MainActor struct')].replace('private ','')
header='''import Foundation
import Darwin
final class BackupOperationControl {}
enum HealthLocalFiles { enum Domain: String { case meals, workouts } }
enum Fixture {
 enum Failure: Error { case invalidContext, invalidObservation, duplicateMutation }
 struct Context: Equatable { let runID: UUID }
 static let verificationProtocol = "Lumen-legacy-target-change-verification-v1"
'''
body='''
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("LumenTargetBridgeControls-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: temporary) }
var count = 0
func check(_ name: String, _ predicate: @autoclosure () -> Bool) { precondition(predicate(), name); count += 1; print(name + ":PASS") }
func rejects(_ name: String, _ action: () throws -> Void) { do { try action(); fatalError(name) } catch { check(name, true) } }
func fresh() throws -> (Fixture.Bridge,Fixture.Context,UUID,BackupOperationControl) {
 let bridge = Fixture.Bridge(), context = Fixture.Context(runID: UUID()), session = UUID(), control = BackupOperationControl()
 try bridge.prepare(context, root: temporary.appendingPathComponent("LumenData"))
 return (bridge,context,session,control)
}
let (b,c,s,k) = try fresh()
check("prepared disabled", !b.canChange(s))
check("bootstrap initially allowed", b.canStart)
rejects("wrong bootstrap context") { try b.observeBootstrap(Fixture.Context(runID:UUID()),facts:[:]) }
check("wrong context did not consume bootstrap", b.canStart)
rejects("not ready rejected") { _ = try b.authorize(c, session:s) }
try b.observeBootstrap(c,facts:[:])
check("bootstrap checking single use", !b.canStart && b.phase == "bootstrap-checking")
rejects("wrong bootstrap finish context") { try b.finishBootstrap(Fixture.Context(runID:UUID())) }
try b.finishBootstrap(c)
check("beforeselection native checked", b.phase == "before-selection" && !b.canStart)
rejects("duplicate bootstrap observe") { try b.observeBootstrap(c,facts:[:]) }
rejects("duplicate bootstrap finish") { try b.finishBootstrap(c) }
b.opened(s); b.began(s,control:k)
check("capturing disabled", !b.canChange(s))
b.ready(s,control:k,domains:[.meals,.workouts])
check("actual same control ready", b.canChange(s))
let capture = try b.authorize(c, session:s)
rejects("wrong session rejected") { _ = try b.authorize(c,session:UUID()) }
rejects("wrong context rejected") { _ = try b.authorize(Fixture.Context(runID:UUID()),session:s) }
rejects("wrong capture rejected") { try b.beforeWrite(c,session:s,captureID:UUID(),facts:[:],guardControl:"guard") }
check("denied guards did not consume", b.canChange(s))
try b.observedGuard(c,session:s,captureID:capture,facts:[:])
try b.beforeWrite(c,session:s,captureID:capture,facts:[:],guardControl:"guard")
check("consumed disabled", !b.canChange(s))
rejects("duplicate acquisition rejected") { _ = try b.authorize(c,session:s) }
rejects("duplicate write guard rejected") { try b.beforeWrite(c,session:s,captureID:capture,facts:[:],guardControl:"guard") }
b.markWritten();try b.observedResult(c,session:s,captureID:capture,facts:[:]);try b.afterWrite(c,session:s,captureID:capture,facts:[:])
check("written phase bound", b.phase == "mutated" && b.didWrite)
b.closed(s)
rejects("closed old authority rejected") { _ = try b.authorize(c,session:s) }
let freshSession=UUID(), freshControl=BackupOperationControl()
b.opened(freshSession);b.began(freshSession,control:freshControl);b.ready(freshSession,control:freshControl,domains:[.meals,.workouts])
check("fresh ready mutation remains consumed", b.phase == "fresh-ready" && !b.canChange(freshSession))
let (wrong,wc,ws,wk) = try fresh();try wrong.observeBootstrap(wc,facts:[:]);try wrong.finishBootstrap(wc);wrong.opened(ws);wrong.began(ws,control:wk)
let other=BackupOperationControl();wrong.ready(ws,control:other,domains:[.meals])
check("wrong actual control latches failure", wrong.phase == "verification-failed" && !wrong.canChange(ws))
rejects("failure cannot authorize") { _ = try wrong.authorize(wc,session:ws) }
let (closed,cc,cs,ck)=try fresh();try closed.observeBootstrap(cc,facts:[:]);try closed.finishBootstrap(cc);closed.opened(cs);closed.began(cs,control:ck);closed.closed(cs);closed.ready(cs,control:ck,domains:[.meals])
check("late completion after close rejected", closed.phase == "verification-failed" && !closed.canChange(cs))
let (missing,mc,ms,mk)=try fresh();try missing.observeBootstrap(mc,facts:[:]);try missing.finishBootstrap(mc);missing.opened(ms);missing.began(ms,control:mk);missing.ready(ms,control:mk,domains:[.workouts])
check("missing meals readiness rejected", missing.phase == "verification-failed")
print("CASES:" + String(count))
'''
with tempfile.TemporaryDirectory(prefix='LumenTargetBridgeCompiler-') as temp:
 p=Path(temp)/'Bridge.swift';p.write_text(header+fragment+body)
 r=subprocess.run(['swift',str(p)],capture_output=True,text=True)
 out={'scope':'Isolated actual Bridge state-machine extraction with stub control/domain types, temporary metadata files only. No preference mutation, LocalStore integration, app build or native proof.','extractedSourceSHA256':hashlib.sha256(fragment.encode()).hexdigest(),'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
 Path('Design/native/health-write-order/source230-bridge-controls-r1.json').write_text(json.dumps(out,indent=2)+'\n')
 print(json.dumps(out))
 assert r.returncode==0
