"""Isolated actual helper/caller/Swift-context checks; no simulator/app/Health action."""
import ast
import base64
import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import textwrap
import time

BASE = Path(__file__).resolve().parent

def module(name, file):
    spec = importlib.util.spec_from_file_location(name, BASE / file)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value

e = module('isolated_reset_evidence', 'legacy-settings-erase-evidence-r2.py')
t = module('isolated_reset_terminal', 'legacy-settings-erase-finalization-r1.py')
f = module('isolated_reset_shared', 'capture-state-finalization-r2.py')
h = e.h
raw = Path(tempfile.mkdtemp(prefix='LumenResetHarnessIsolatedR1-', dir='/tmp'))
results = []; started = time.time()
sha = lambda data: hashlib.sha256(data).hexdigest()


def record(name, details): results.append({'case': name, 'status': 'PASS isolated declared guard', **details})

# Execute the literal caller boundary block in a bounded fake environment; this
# is not a parallel implementation or an actual native/simulator test.
driver = (BASE / 'legacy-settings-erase-driver-r2.py').read_text()
fragment = driver[driver.index('            raw_checkpoint = h.read(candidates[0])'):driver.index('            time.sleep(0.15)')]
wrapped = 'def exercise_boundary():\n    for _ in range(1):\n' + textwrap.indent(textwrap.dedent(fragment), '        ')
ast.parse(wrapped)
old_container, old_installed, old_provider = h.container, h.installed, h.provider
old_check_output = subprocess.check_output
try:
    for number, scenario in enumerate(['wrong-data', 'wrong-string', 'unsupported-type', 'file-metadata-guard']):
        folder = raw / scenario; group = folder / 'group'; data = folder / 'data'; app = folder / 'Lumen.app'
        for p in [group / 'LumenData', group / 'LumenData.previous', data / 'Library/Preferences', app]: p.mkdir(parents=True)
        for p in [group / 'LumenData', group / 'LumenData.previous']: (p / 'probe.json').write_text('[]')
        (group / 'Lumen-legacy-origin-review-events.json').write_text(json.dumps({'events': []}))
        kind = 'string' if scenario == 'wrong-string' else 'data'
        original = 'Synthetic persisted old value e\u0301 🫖'.encode('utf-16-le') if kind == 'string' else h.DATA
        expected = {'kind': kind, 'values': {domain: {'key': key, 'type': 'stringUTF16LE' if kind == 'string' else 'data',
             'payload': base64.b64encode(original).decode()} for domain, key in zip(['meals','workouts'], e.KEYS)}}
        actual = 'Synthetic WRONG string e\u0301 🫖' if kind == 'string' else b'{synthetic WRONG persisted value'
        if scenario == 'unsupported-type': actual = False
        if scenario == 'file-metadata-guard': actual = h.DATA
        (data / 'Library/Preferences/com.dbakp.lumen.plist').write_bytes(plistlib.dumps(dict.fromkeys(e.KEYS, actual)))
        h.container = lambda kind, g=group, d=data, a=app: {'data':d, 'app':a, 'group.com.dbakp.lumen':g}[kind]
        h.installed = lambda _: {'known': 'synthetic-only'}; h.provider = lambda: {'known':'unchanged-external-synthetic-source'}
        subprocess.check_output = lambda *a, app=app, **kw: str(app / 'Lumen') + '\n'
        before = {}; prior = {}; e.observe_tree(group / 'LumenData', before); e.observe_tree(group / 'LumenData.previous', prior)
        if scenario == 'file-metadata-guard':
            p = group / 'LumenData/probe.json'; facts = p.stat(); __import__('os').utime(p, ns=(facts.st_atime_ns, facts.st_mtime_ns+1000000000))
        observation = {'verificationProtocol':e.PROTOCOL, 'pid':42, 'runID':'7EE08113-F268-410A-B3CD-46D270370F08',
            'sequence':2, 'mode':'initial-fixture', 'healthConnected':False, 'healthAuthorized':False,
            'fixed':{x:{'persistedPresent':True,'effectivePresent':True} for x in ['meals','workouts']}, 'onboardingDone':True}
        checkpoint = group / 'Lumen-legacy-reset-checkpoint.json'; checkpoint.write_text(json.dumps(observation))
        initial = {'observation':{'sequence':1}, 'files':before['files'],'metadata':before['metadata'],
                   'prior':prior['files'],'priorMetadata':prior['metadata']}
        state = {'boundaries':[initial], 'messages':[], 'started':started-1, 'runID':observation['runID'],
                 'provider':h.provider(),'baseline':{'legacyOrigins':expected},'initialPID':42}
        saves=[]; acks=[]
        def persist():
            saves.append(copy.deepcopy(state)); (folder / 'retained-boundary.json').write_text(json.dumps(state,indent=2)+'\n')
        namespace = {'h':h,'e':e,'json':json,'time':time,'state':state,'candidates':[checkpoint],'group':group,'root':group/'LumenData',
            'persist':persist,'subprocess':subprocess,'Path':Path,'a':type('Args',(),{'build':'isolated-not-native','case':kind})(),
            'message':lambda *args:acks.append(args),'traceback':__import__('traceback')}
        exec(wrapped, namespace)
        try: namespace['exercise_boundary']()
        except AssertionError: pass
        else: raise AssertionError('Actual invalid boundary unexpectedly accepted')
        failed = state['boundaries'][-1]
        assert len(state['boundaries']) == 2 and failed['status'] == 'FAILED' and failed['error'] and not acks
        assert failed['rawCheckpoint']['base64'] == base64.b64encode(checkpoint.read_bytes()).decode()
        if scenario.startswith('wrong-'):
            retained = failed['fixed'][e.KEYS[0]]
            expected_bytes = actual.encode('utf-16-le') if isinstance(actual,str) else actual
            assert base64.b64decode(retained['base64']) == expected_bytes
        if scenario == 'unsupported-type': assert failed['fixed'][e.KEYS[0]]['actualType']=='bool'
        if scenario == 'file-metadata-guard': assert failed['metadata'] != initial['metadata'] and failed['priorMetadata']==initial['priorMetadata']
        record(scenario, {'actualCallerFragmentSHA256':sha(fragment.encode()), 'failedBoundaryRetained':True, 'acks':len(acks), 'persistCalls':len(saves)})
finally:
    h.container, h.installed, h.provider = old_container, old_installed, old_provider
    subprocess.check_output = old_check_output

# Actual incremental tree guard retains a symlink's lstat without following it.
folder = raw / 'tree-symlink'; folder.mkdir(); target = raw / 'synthetic-target.bin'; target.write_bytes(b'Synthetic outside target stays untouched')
(folder / 'bad-link').symlink_to(target); tree = {}
try: e.observe_tree(folder, tree)
except AssertionError: pass
else: raise AssertionError('Symlink accepted')
assert tree['status']=='FAILED observation' and tree['entries'][0]['path']=='bad-link' and target.read_bytes()==b'Synthetic outside target stays untouched'
record('tree-symlink', {'entryFactsRetained':True,'targetFollowedOrChanged':False})

# Actual terminal caller plus reviewed shared finalizer/retainer. Fake processes
# and fake exporters explicitly isolate caller wiring, not native failure timing.
class FakeProcess:
    returncode = None
    def __init__(self): self.returncode=None; self.waitCalls=0; self.signals=[]
    def poll(self): return self.returncode
    def wait(self, timeout=None): self.waitCalls+=1; self.returncode=0; return 0
    def send_signal(self, value): self.signals.append(value)
    def kill(self): self.signals.append('kill'); self.returncode=-9

for scenario in ['first-outcome-write-failure','first-state-write-failure','retainer-import-failure','clean-terminal-control']:
    folder=raw/scenario; folder.mkdir(); outpath=folder/'outcome.json'; state={'build':'isolated','case':'data'}
    process=FakeProcess(); exports=[]; saves=[]; accepts=[]; salvage=[]
    original_durable=f.durable_json; original_salvage=f.salvage_peers; writes=[0]
    def durable(path,value):
        writes[0]+=1
        if scenario=='first-outcome-write-failure' and writes[0]==1: raise OSError('Synthetic injected first outcome persistence failure')
        return original_durable(path,value)
    def persist():
        saves.append(1)
        if scenario=='first-state-write-failure' and len(saves)==1: raise OSError('Synthetic injected state persistence failure')
        (folder/'state.json').write_text(json.dumps(state,indent=2)+'\n')
    class Retainer:
        @staticmethod
        def retain(*args):
            exports.append(1); return {'errors':[],'summary':{'passedTests':1,'failedTests':0,'skippedTests':0}}
    def loader():
        if scenario=='retainer-import-failure': raise ImportError('Synthetic injected retainer import failure')
        return Retainer
    def mock_salvage(*args): salvage.append(1)
    f.durable_json=durable; f.salvage_peers=mock_salvage
    try: result=t.finalize(process,state,persist,outpath,loader,folder,folder,'isolated','isolated','isolated',lambda retained:accepts.append(1),f)
    finally: f.durable_json=original_durable; f.salvage_peers=original_salvage
    assert process.waitCalls==1 and not process.signals
    if scenario=='clean-terminal-control': assert result['driverExit']==0 and result['status'].startswith('PASS') and len(accepts)==1
    else: assert result['driverExit']==1 and not result['status'].startswith('PASS') and not accepts
    if scenario=='retainer-import-failure': assert len(salvage)==1
    else: assert len(exports)==1
    record(scenario, {'driverExit':result['driverExit'],'status':result['status'],'naturalWaitCalls':process.waitCalls,
        'signals':process.signals,'retainerCalls':len(exports),'mockSalvageCalls':len(salvage),'acceptCalls':len(accepts),
        'outcomePersistenceErrors':len(result.get('outcomePersistenceErrors',[])), 'statePersistenceErrors':len(result.get('finalizationPersistenceErrors',[]))})

# Extract the exact pure Swift context function, compile it with Foundation only,
# and call it under malformed contexts. No app, Keychain or reset API is present.
fixture_path=BASE.parents[2]/'Lumen/Views/HealthRecoveryCancelUIFixture.swift'; fixture=fixture_path.read_text()
start=fixture.index('    static func context(_ args: [String])'); end=fixture.index('    static var runID: UUID?', start)
context=fixture[start:end]
initial=['-health-legacy-reset-ui','-health-legacy-reset-run','7EE08113-F268-410A-B3CD-46D270370F08','-resetForUITests',
         '-health-backup-ui-fixture','-health-backup-empty-ui','-health-backup-healthy-merge-ui','-health-legacy-origin-ui','data','-health-backup-case','legacy']
observer=['-health-legacy-reset-observer','-health-legacy-reset-run',initial[2]]
bad=[['-health-legacy-reset-ui','-resetForUITests'],['-health-legacy-reset-ui','-health-legacy-reset-run','invalid','-resetForUITests'],
     initial+['-health-legacy-reset-observer'],initial+['-health-legacy-reset-ui'],observer+['-resetForUITests'],
     observer+['-health-backup-ui-fixture'],observer+['-health-legacy-origin-ui','data'],['-health-legacy-reset-run',initial[2]],
     [x for x in initial if x!='-health-backup-empty-ui'],[x for x in initial if x!='-health-backup-healthy-merge-ui'],
     ['wrong' if x=='data' else x for x in initial],['encrypted' if x=='legacy' else x for x in initial],
     ['-health-legacy-reset-observer','-health-legacy-reset-run'],observer+['-health-legacy-reset-run',initial[2]]]
arrays=lambda value: json.dumps(value,ensure_ascii=False)
swift='import Foundation\n@MainActor enum Probe {\n enum Failure: Error { case unsafeContext, invalidObservation }\n'+context+'}\n@main struct Harness { @MainActor static func main() throws {\n'
swift+='let initial: [String] = '+arrays(initial)+'\nlet observer: [String] = '+arrays(observer)+'\nlet bad: [[String]] = '+arrays(bad)+'\n'
swift+='precondition(try Probe.context(initial)?.mode == "initial-fixture")\n'
swift+='precondition(try Probe.context(observer)?.mode == "readonly-clean-relaunch")\n'
swift+='precondition(try Probe.context(["-resetForUITests"]) == nil)\n'
swift+='for args in bad { var resetCalls = 0; do { _ = try Probe.context(args); resetCalls += 1 } catch { }; precondition(resetCalls == 0) }\nprint("PASS context guards: \\(bad.count) malformed +3 controls")\n} }\n'
# Swift precondition's autoclosure cannot throw: use evaluated local results.
swift=swift.replace('precondition(try Probe.context(initial)?.mode == "initial-fixture")','let initialResult = try Probe.context(initial); precondition(initialResult?.mode == "initial-fixture")')
swift=swift.replace('precondition(try Probe.context(observer)?.mode == "readonly-clean-relaunch")','let observerResult = try Probe.context(observer); precondition(observerResult?.mode == "readonly-clean-relaunch")')
swift=swift.replace('precondition(try Probe.context(["-resetForUITests"]) == nil)','let ordinary = try Probe.context(["-resetForUITests"]); precondition(ordinary == nil)')
source=raw/'Context.swift'; binary=raw/'Context';source.write_text(swift)
command=['xcrun','swiftc','-parse-as-library',str(source),'-o',str(binary)]
compiled=subprocess.run(command,capture_output=True,text=True); (raw/'context-build.log').write_text(compiled.stdout+compiled.stderr)
assert compiled.returncode==0,compiled.stderr
ran=subprocess.run([str(binary)],capture_output=True,text=True); (raw/'context-run.log').write_text(ran.stdout+ran.stderr)
assert ran.returncode==0,ran.stderr
app=(BASE.parents[2]/'Lumen/LumenApp.swift').read_text();assert app.index('HealthLegacyResetUIFixture.preflightIfRequested()')<app.index('LocalStore.eraseAll()')
record('exact-swift-context', {'sourceFunctionBytes':len(context.encode()),'sourceFunctionSHA256':sha(context.encode()),
    'malformedCases':len(bad),'validControls':3,'compileExit':compiled.returncode,'runExit':ran.returncode,
    'stdout':ran.stdout.strip(),'preflightBeforeGenericResetSourceOrder':True,'actualAppResetExecuted':False})

# Retain every small actual synthetic test payload and generated source/log;
# compiled executable is disposable, not runtime acceptance or permanent input.
files={}
for path in sorted(raw.rglob('*')):
    if path.is_file() and not path.is_symlink() and path!=binary:
        data=path.read_bytes();files[str(path.relative_to(raw))]={'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()}
archive=BASE/'reset-harness-isolated-r1-fixtures.json.gz';archive.write_bytes(gzip.compress(json.dumps({'files':files},separators=(',',':')).encode(),mtime=0))
inputs=['legacy-settings-erase-evidence-r2.py','legacy-settings-erase-driver-r2.py','legacy-settings-erase-finalization-r1.py','capture-state-finalization-r2.py','check-reset-harness-isolated-r1.py']
provenance=[]
for name in inputs:
    data=(BASE/name).read_bytes();provenance.append({'file':str((BASE/name).relative_to(BASE.parents[2])),'bytes':len(data),'sha256':sha(data)})
for path in [fixture_path,BASE.parents[2]/'Lumen/LumenApp.swift']:
    data=path.read_bytes();provenance.append({'file':str(path.relative_to(BASE.parents[2])),'bytes':len(data),'sha256':sha(data)})
out={'status':'PASS isolated actual helper/caller/context guards ONLY; no simulator/native/product reset acceptance',
     'cases':results,'provenance':provenance,'callerFragmentBytes':len(fragment.encode()),'callerFragmentSHA256':sha(fragment.encode()),
     'fixtureArchive':{'file':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive.read_bytes()),'payloadFiles':len(files)},
     'temporaryDirectory':str(raw),'compiledContextExecutableBytes':binary.stat().st_size,
     'scope':'4actual caller wrong-value/metadata failures,1actual nofollow tree guard,4terminal caller mocked-process/exporter controls, actual extracted Swift pure context14malformed+3controls. No simulator/Keychain/Health/native timing/fault erasure execution.',
     'physicalDeviceActions':False,'checkedAt':time.time()}
(BASE/'reset-harness-isolated-r1-outcome.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps({'status':out['status'],'cases':len(results),'swiftMalformedCases':len(bad),'smallPayloadFiles':len(files),'temporaryDirectory':str(raw)}))
