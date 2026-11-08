from pathlib import Path
import importlib.util,json,hashlib,gzip,base64,time,traceback
base=Path('/Users/davidbakposada/Documents/ChatGPT/Lumen/Design/native/health-write-order')
spec=importlib.util.spec_from_file_location('failed_capture_evidence',base/'capture-state-evidence-r2.py');e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e);h,ns=e.h,e.ns
prefix='health-capture-state-pending-back-source219r1';state=h.load(base/(prefix+'-driver-observations.json'));outcome=h.load(base/(prefix+'-outcome.json'));report={'status':'Read-only failed nativecase observations; NOT acceptance','source':state['source'],'build':state['build'],'case':state['case'],'checks':{},'physicalDeviceActions':False}
def observe(name,operation):
 try:report['checks'][name]={'observed':operation(),'captured':True}
 except BaseException:report['checks'][name]={'captured':False,'error':traceback.format_exc()}
observe('fullSourceBuild',lambda:h.verify_inputs(state['source'],state['build']))
observe('installed',lambda:h.installed(state['build']))
group=h.container('group.com.dbakp.lumen');root=group/'LumenData'
current=h.snapshot(root);meta=ns.tree(root);prior=h.snapshot(root.with_suffix('.previous'));pm=ns.tree(root.with_suffix('.previous'))
report.update(current=current,currentMetadata=meta,prior=prior,priorMetadata=pm,currentBytesExact=current==state['before'],currentMetadataExact=meta==state['beforeMetadata'],priorBytesExact=prior==state['prior'],priorMetadataExact=pm==state['priorMetadata'])
fixed={};observe('fixed',lambda:e.fixed(state['checkpoint']['legacyOrigins'],fixed));report['fixed']=fixed;report['fixedExact']=fixed==state['fixed'];observe('provider',h.provider);report['providerExact']=report['checks']['provider'].get('observed')==state['provider'];observe('sourceSelectedInput',lambda:e.source_exact(state['selection']));observe('ownedWorkspaces',lambda:h.owned(state['held']['pid']));report['selection']=state['selection'];report['actualCapture']=h.load(group/'Lumen-legacy-capture-checkpoint.json');report['originEvents']=h.events(group)
report['receiptStagePaths']=[str(p) for pattern in ['LumenData.restore-*','LumenData.retired-*'] for p in group.glob(pattern)];report['messageHistory']=state['messageHistory'];report['actualNative']={'passed':outcome['summary']['passedTests'],'failed':outcome['summary']['failedTests'],'skipped':outcome['summary']['skippedTests'],'nativeExit':outcome['nativeExit'],'driverExit':outcome['driverExit'],'retainedOriginals':len(outcome['retention']['images']),'nativeHelpers':len(outcome['retention']['readbacks']),'nativeFinalization':state['nativeFinalization']}
# Every archived source/fixture and retained failed attachment payload bound.
m=h.load(base/state['source']);archive=json.loads(gzip.decompress((base/(state['source']+'.gz')).read_bytes()));count=0
for key,stored in [('files','files'),('fixtureInputs','binaryFiles')]:
 for name,row in m[key].items():
  data=Path(name).read_bytes();original=archive[stored][name].encode() if stored=='files' else base64.b64decode(archive[stored][name]);assert data==original and len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'];count+=1
report['fullCurrentArchiveInputsExact']=count;report['scope']='Actual failed0/1/0 before choices/intendedBack,2nativeoriginals/0JSON. No capturecompletion/cleanup/Back/freshreview acceptance; failed120sbarrier and lostsettingsnavigation retained. Bounded failure finalization naturallycompleted65 without interrupt/kill; no faultrestore branch inpendingcase.';report['checkedAt']=time.time();target=base/'source219-capture-state-pending-back-r1-failed-live-audit.json';assert not target.exists();target.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['currentBytesExact','currentMetadataExact','priorBytesExact','priorMetadataExact','fixedExact','providerExact','receiptStagePaths','fullCurrentArchiveInputsExact','actualNative']},indent=2));print('checks',[(k,v['captured']) for k,v in report['checks'].items()]);print('originEvents',report['originEvents']);print('actualCaptureEvents',[r['event'] for r in report['actualCapture']['events']])
