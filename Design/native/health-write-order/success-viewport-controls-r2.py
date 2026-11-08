"""Boundary negatives exercise the actual native predicate and strict host replay."""
from pathlib import Path
import copy,gzip,hashlib,importlib.util,json,subprocess,tempfile,time,math
B=Path(__file__).resolve().parent;repo=B.parents[2];source=(repo/'LumenUITests/LumenSmokeTests.swift').read_text();start=source.index('    private func recoveryCompletionRectIsValid(');end=source.index('    @MainActor\n    func testHealthBackupFileRecoveryTargetChangedAfterReadyOriginData()',start);methods=source[start:end]
spec=importlib.util.spec_from_file_location('viewport_control_subject',B/'target-success-viewport-r1.py');subject=importlib.util.module_from_spec(spec);spec.loader.exec_module(subject)
base={'application':[0,0,402,874],'navigation':[0,78,402,54],'label':[16,132,370,52],'exists':True,'hittable':True,'message':'Selected data recovered'}
cases=[]
def case(name,ok,**changes):
 value=copy.deepcopy(base);value.update(changes);cases.append({'name':name,'expected':ok,'input':value})
case('actual-top-edge',True);case('inside',True,label=[16,160,370,52]);case('bottom-edge',True,label=[16,782,370,52]);case('side-edges',True,label=[0,132,402,52]);case('translated-application',True,application=[20,40,402,874],navigation=[20,118,402,54],label=[36,172,370,52])
case('top-clipped',False,label=[16,131.99,370,52]);case('bottom-clipped',False,label=[16,782.01,370,52]);case('left-clipped',False,label=[-.01,132,370,52]);case('right-clipped',False,label=[16,132,386.01,52]);case('offscreen',False,label=[16,900,370,52]);case('zero-label-width',False,label=[16,132,0,52]);case('zero-label-height',False,label=[16,132,370,0]);case('negative-label-width',False,label=[386,132,-370,52]);case('negative-label-height',False,label=[16,184,370,-52]);case('nan-label',False,label=[16,'NaN',370,52]);case('infinite-label',False,label=[16,132,'Infinity',52]);case('empty-application',False,application=[0,0,0,874]);case('invalid-navigation',False,navigation=[0,78,0,54]);case('navigation-outside-app',False,navigation=[-1,78,402,54]);case('no-usable-height',False,navigation=[0,78,402,756]);case('absent',False,exists=False);case('not-hittable',False,hittable=False);case('wrong-label',False,message='Selected');case('empty-label',False,message='')
def restore(value):return float('nan') if value=='NaN' else float('inf') if value=='Infinity' else value
def make_row(value):
 app,nav=[value[k] for k in ['application','navigation']];return {'phase':'fresh-committed','exists':value['exists'],'hittable':value['hittable'],'message':value['message'],'wholeSuccessBeforeAnyTestScroll':True,'geometry':{k:[restore(n) for n in value[k]] for k in ['application','navigation','label']}|{'viewport':[app[0],nav[1]+nav[3],app[2],app[1]+app[3]-40-(nav[1]+nav[3])]}}
python_results=[]
for c in cases:
 try:subject.validate(make_row(c['input']));accepted=True
 except (AssertionError,KeyError,ValueError,OverflowError):accepted=False
 assert accepted==c['expected'],c['name'];python_results.append({'name':c['name'],'accepted':accepted})
extra=[]
for name,edit in [('missing-geometry',lambda r:r.pop('geometry')),('forged-viewport',lambda r:r['geometry'].__setitem__('viewport',[0,120,402,714])),('boolean-coordinate',lambda r:r['geometry']['label'].__setitem__(0,False)),('short-rectangle',lambda r:r['geometry'].__setitem__('label',[16,132,370])),('false-whole-flag',lambda r:r.__setitem__('wholeSuccessBeforeAnyTestScroll',False))]:
 row=make_row(base);edit(row)
 try:subject.validate(row);raise RuntimeError('Invalid host shape accepted: '+name)
 except (AssertionError,KeyError,ValueError,OverflowError):pass
 extra.append(name)
def number(n):return 'CGFloat.nan' if n=='NaN' else 'CGFloat.infinity' if n=='Infinity' else str(n)
def rectangle(v):return 'CGRect(x: '+number(v[0])+', y: '+number(v[1])+', width: '+number(v[2])+', height: '+number(v[3])+')'
lines=[]
for c in cases:
 v=c['input'];lines.append('check('+json.dumps(c['name'])+', '+str(c['expected']).lower()+', '+str(v['exists']).lower()+', '+str(v['hittable']).lower()+', '+json.dumps(v['message'])+', '+rectangle(v['label'])+', '+rectangle(v['application'])+', '+rectangle(v['navigation'])+')')
harness='import Foundation\nimport CoreGraphics\nfinal class Subject {\n'+methods+'''func evaluate(_ exists: Bool, _ hit: Bool, _ label: String, _ target: CGRect, _ app: CGRect, _ nav: CGRect) -> Bool {
 recoveryCompletionVisible(exists:exists,hittable:hit,label:label,target:target,application:app,navigation:nav)
}
}
let subject=Subject()
var results: [[String: Any]]=[]
func check(_ name: String,_ expected: Bool,_ exists: Bool,_ hit: Bool,_ label: String,_ target: CGRect,_ app: CGRect,_ nav: CGRect) {
 let result=subject.evaluate(exists,hit,label,target,app,nav)
 precondition(result == expected,name)
 results.append(["name":name,"accepted":result])
}
'''+ '\n'.join(lines)+'''\nlet data=try JSONSerialization.data(withJSONObject:results,options:[.sortedKeys]);print(String(decoding:data,as:UTF8.self))\n'''
with tempfile.TemporaryDirectory(prefix='lumen238-viewport-') as temp:
 p=Path(temp);(p/'main.swift').write_text(harness);compile=subprocess.run(['xcrun','swiftc',str(p/'main.swift'),'-o',str(p/'controls')],capture_output=True,text=True);
 if compile.returncode!=0:
  failure={'status':'FAILED isolated Swift harness compile','source':harness,'command':'xcrun swiftc temporary main.swift','exit':compile.returncode,'stdout':compile.stdout,'stderr':compile.stderr,'checkedAt':time.time()}
  (B/'source238-viewport-controls-preparation-failure-r4.json.gz').write_bytes(gzip.compress(json.dumps(failure).encode(),mtime=0))
  raise RuntimeError('Isolated harness compile failed; fulldiagnostic retainedgzip')
 run=subprocess.run([str(p/'controls')],capture_output=True,text=True,timeout=30);assert run.returncode==0,run.stderr;swift=json.loads(run.stdout);assert swift==python_results
archive={'methods':methods,'harness':harness,'cases':cases,'swift':swift,'host':python_results,'hostShapeNegatives':extra,'compileExit':compile.returncode,'compileStdout':compile.stdout,'compileStderr':compile.stderr,'runExit':run.returncode,'runStdout':run.stdout,'runStderr':run.stderr};raw=json.dumps(archive,indent=2).encode();name='source238-success-viewport-controls-r2-fixtures.json.gz';(B/name).write_bytes(gzip.compress(raw,mtime=0));report={'status':'PASS24actualnativegeometry/strict-host cases plus5hostshape negatives','sourceFile':'LumenUITests/LumenSmokeTests.swift','sourceSHA256':hashlib.sha256(source.encode()).hexdigest(),'nativeMethodBytes':len(methods.encode()),'nativeMethodSHA256':hashlib.sha256(methods.encode()).hexdigest(),'hostModuleSHA256':hashlib.sha256((B/'target-success-viewport-r1.py').read_bytes()).hexdigest(),'swiftCases':len(cases),'sharedHostCases':len(cases),'additionalHostRejects':len(extra),'archive':name,'decodedBytes':len(raw),'decodedSHA256':hashlib.sha256(raw).hexdigest(),'scope':'Actual extracted pure native method/CoreGraphics containment and actual strict host validator; no XCTest/SwiftUI/layout/speech/native run acceptance. Exact actual132top accepted, real clipping/invalid/absent/wronglabel rejected.','checkedAt':time.time()};(B/'source238-success-viewport-controls-r2.json').write_text(json.dumps(report,indent=2)+'\n');print(report['status'])
