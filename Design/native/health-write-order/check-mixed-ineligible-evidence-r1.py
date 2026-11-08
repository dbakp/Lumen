"""Read-only independent byte/live-state checker. Does not seed/reset/ack/run UI."""
import importlib.util,json,struct,sys,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('mixed',Path(__file__).with_name('health-mixed-ineligible-evidence-r1.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
prefix,output=sys.argv[1:3];r=h.load(h.BASE/(prefix+'-host-audit.json'))
preflight=h.verify_inputs(r['source'],r['build']);h.installed(r['build'])
assert r['nativeExit']==0 and r['status'].startswith('PASS actual') and r['released']['intentionallyHostReleased'] is True
summary=h.load(h.BASE/(prefix+'-summary.json'));assert [summary[k] for k in ['passedTests','failedTests','skippedTests']]==[1,0,0]
images=h.load(h.BASE/(prefix+'-images.json'));helpers=h.load(h.BASE/(prefix+'-readbacks.json'))
assert len(images)==14 and len(helpers)==1
names=[]
for row in images+helpers:
    data=h.read(h.BASE/row['file'],4*1024*1024)
    assert len(data)==row['bytes'] and h.sha(data)==row['sha256'] and row['source']==r['source']
    assert h.read(row['raw'],4*1024*1024)==data
    if row in images:
        assert struct.unpack('>II',data[16:24])==(1206,2622)
        name=row['metadata']['suggestedHumanReadableName']
        matches=[s for s in h.SUFFIXES if 'health-mixed-ineligible-legacy-'+s+'_' in name or name=='health-mixed-ineligible-legacy-'+s or name.startswith('health-mixed-ineligible-legacy-'+s+'.')]
        # Export metadata may append the standard XCTest timestamp/extension.
        if not matches:matches=[s for s in h.SUFFIXES if ('health-mixed-ineligible-legacy-'+s) in name]
        assert len(matches)==1,(name,matches);names+=matches
assert sorted(names)==sorted(h.SUFFIXES)
helper=h.load(h.BASE/helpers[0]['file']);assert helper['scope']=='mixed-ineligible-workouts-only'
observations=helper['observations'];phases={x['phase']:x for x in observations}
assert len(phases)==len(observations)
assert set(phases)=={'healthy-water','healthy-goals','mixed-off','workouts-selected','confirmation','not-now','acknowledged','post-success','relaunch-review','relaunch-workouts-healthy'}
for phase,x in phases.items():
    for e in x.get('elements',[]):
        f=e['frame'];assert f['width']>0 and f['height']>0
        assert f['x']>=x['usableLeft'] and f['x']+f['width']<=x['usableRight']
        assert f['y']>=x['usableTop']-2 and f['y']+f['height']<=x['usableBottom']
for phase,value in [('mixed-off','0'),('workouts-selected','1'),('not-now','1')]:
    elements=phases[phase]['elements'];assert len(elements)==3
    assert elements[0]['label']=="This saved data can't be replaced here."
    assert elements[1]['value']=='0' and elements[1]['enabled'] is False
    assert elements[2]['value']==value and elements[2]['enabled'] is True
assert phases['confirmation']['completeBody']=='Selected data will be replaced by records from this file. The older saved data will stay in a private recovery copy on this iPhone.'
assert phases['confirmation']['wholeAlertInScreen'] is True
assert phases['acknowledged']['successValue']=='success-observed'
assert phases['post-success']['elements'][0]['label']=='Older saved data will stay in a private recovery copy on this iPhone. For meal recovery, this includes any old photos.'
assert phases['relaunch-review']['elements'][0]['label']=="This saved data can't be replaced here."
assert phases['relaunch-review']['elements'][1]['value']=='0' and phases['relaunch-review']['elements'][1]['enabled'] is False
assert len(phases['relaunch-review']['elements'])==3 and phases['relaunch-review']['elements'][2]['label']=='Current data opens'
assert all(phases['relaunch-workouts-healthy'][k] is True for k in ['noWorkoutsToggle','recoverDisabled','noFixtureRelaunchArguments'])
root=h.container('group.com.dbakp.lumen')/'LumenData';assert h.snapshot(root)==r['after']
assert h.directories(root)==r['directoriesAfter']==r['commitObservedDirectories']==h.allowed_directories(r['directoriesBefore'],r['after'])
assert set(r['after'])==set(r['success']['tree'])
for name,want in r['success']['tree'].items():
    if name in ['profile.json','habits.json']:assert json.loads(h.base64.b64decode(r['after'][name]['base64']))==json.loads(h.base64.b64decode(want['base64']))
    else:assert r['after'][name]==want
assert h.read(root/'workouts.json')==b'[]' and not (root/'meals.json').exists()
assert h.fixed(r['checkpoint']['legacyOrigins'])==r['success']['fixed']
assert r['success']['receipt']['domains']==['workouts'] and r['success']['receipt']['photoDigests']==r['success']['receipt']['reviewedPhotos']=={}
assert r['success']['receipt']['recordDigests']=={'workouts.json':h.sha(b'[]')} and r['success']['receipt']['omittedPhotoCount']==0
v2=r['success']['v2'];directory=Path(v2['directory'])
assert {p.name for p in directory.iterdir()}=={'manifest.json','device-intent.json','legacy-origin-workouts.json'}
assert h.load(directory/'manifest.json')==v2['manifest'] and h.row(h.read(directory/'legacy-origin-workouts.json'))==v2['outer']
assert h.load(directory/'legacy-origin-workouts.json')==v2['envelope']
assert h.read(directory/'device-intent.json')==h.base64.b64decode(r['before']['health-write-intent.json']['base64'])
for name,want in r['held']['priorCopy']['files'].items():assert r['after'][name]==want
assert not root.with_suffix('.previous').exists() and not list(root.parent.glob('LumenData.restore-*')) and not list(root.parent.glob('LumenData.retired-*'))
assert r['retirementSamples'] and all(not r['retirementSamples'][-1][k] for k in ['priorExists','restore','retired'])
assert r['parent']['tree']==r['success']['tree'] and r['relaunchParent']['tree']==r['after']
for selection in [r['selection'],r['relaunchSelection']]:
    assert not h.owned(selection['source']['owner']['pid'])
    assert all(not Path(path).exists() for path in selection['workspaces'])
trace=h.events(root.parent);assert trace==r['originEvents']
assert len({x['sessionID'] for x in trace})==1 and [x['event'] for x in trace[:3]]==['open','ready','acquire']
assert trace[1]['domains']==trace[2]['domains']==['workouts'] and len(trace)>3 and all(x['event']=='closed' for x in trace[3:])
assert [x['phase'] for x in r['boundaries']]==['initial-before-file-selection','selected-original','held-before-ack','observed-before-intentional-release','success-before-ack','parent-before-relaunch','fresh-relaunch-review','final-after-relaunch']
assert all(x['status']=='PASS' and x['fixed']==r['success']['fixed'] for x in r['boundaries'])
h.provider()
d={'status':'PASS read-only live/source/native mixed-ineligible audit','source':r['source'],'build':r['build'],'sourceInputs':preflight['inputs'],'originals':14,'fullNativeHelperBytes':helpers[0]['bytes'],'liveFiles':len(r['after']),'fixedTypedBoundarySamples':len(r['boundaries']),'checkedAt':time.time(),'scope':'Single main/light/normal workouts-only mixed dictionary case; no all43/VO/motion/appearances/reset/global acceptance.'}
(h.BASE/output).write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d))
