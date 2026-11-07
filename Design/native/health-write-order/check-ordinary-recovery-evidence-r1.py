import json,pathlib,base64,hashlib,sys,stat
b=pathlib.Path('Design/native/health-write-order');prefix=sys.argv[1];d=json.loads((b/(prefix+'-host-audit.json')).read_text());su=json.loads((b/(prefix+'-summary.json')).read_text());assert d['producerExitCode']==0 and (su['passedTests'],su['failedTests'],su['skippedTests'])==(1,0,0)
count=0
def data(v):return base64.b64decode(v['base64'],validate=True)
def obj(v):return json.loads(data(v))
def scan(v):
 global count
 if isinstance(v,dict):
  if {'base64','bytes','sha256'}<=v.keys():
   bs=data(v);assert len(bs)==v['bytes'] and hashlib.sha256(bs).hexdigest()==v['sha256'];count+=1
  for x in v.values():scan(x)
 elif isinstance(v,list):
  for x in v:scan(x)
scan(d)
r=d['readerHeld']['record'];assert d['readerHeld']['actualDescriptorAndSourceBound'];assert all(s in d['readerHeld']['lsof'] for s in [f"p{r['pid']}\n",f"f{r['descriptor']}\n",f"i{r['inode']}\n",r['file']]);assert d['readerCompleted']['sameActualReaderCompletedAndClosed'] and d['readerCompleted']['reviewOwnerStillOpen'] and d['readerCompleted']['record']['nonce']==r['nonce']
for name in ['failedBoundary','scrollBoundary','omissionNotNowBoundary']:
 v=d[name];assert v['currentAndPriorBytesAndMetadataExact'] and v['noReceiptStageOrCheckpoint'] and v['sourceWorkspacesExactExceptDeclaredPhotoFault']
v=d['backBoundary'];assert v['actualReviewOwnerClosed'] and v['completedReaderDescriptorClosed'] and v['currentPriorBytesAndMetadataExact'] and v['noReceiptStageOrRecoveryWorker'] and not v['hostDeletedWorkspace'] and not v['existingOldWorkspaces']
f=d['freshSelection'];assert f['allOldWorkspacesAbsent'] and f['independentFreshOwnership'] and f['healthyOriginalPhotosRestoredByNewSelection'] and f['source']['file']!=r['file'];assert d['heldPreparation']['stageInitiallyEmpty'];assert d['releasedPreparation']['sameActualControl'] and d['releasedPreparation']['allProtectedBytesExact'] and d['releasedPreparation']['allFreshOriginalWorkspacesExact'];assert [(x['ordinal'],x['phase']) for x in d['protocol']['attempts']]==[(2,'released')]
s=d['successBeforeRelaunch'];assert s['sourceIdentityAuditedWhileReviewOpen'] and s['providerIdentityAuditedWhileReviewOpen'] and s['receiptAuditBeforeAck']['fullReceiptAuditedBeforeAck'];rc=d['receipt'];assert s['receipt']==rc and rc['domains']==['meals','workouts'] and rc['omittedPhotoCount']==0 and len(rc['photoDigests'])==len(rc['reviewedPhotos'])==2;assert rc['reviewedPhotos']=={k:{'byteCount':v['bytes'],'sha256':v['sha256']} for k,v in f['photos'].items()};assert set(rc['photoDigests'].values())=={v['sha256'] for v in f['photos'].values()};tree=s['treeAfterCommit'];assert len(tree)==23 and set(tree)==set(d['after']);assert rc['photoDigests']==d['installedPhotoDigests'];assert all(tree[k]['sha256']==v for k,v in rc['photoDigests'].items());assert all(tree[k]['sha256']==v for k,v in rc['recordDigests'].items());meals=obj(tree['meals.json']);assert len(meals)==2 and all(m.get('photoID') for m in meals) and obj(tree['workouts.json'])==[]
assert obj(tree['water.json'])==obj(d['before']['water.json']) and obj(tree['goals.json'])==obj(d['before']['goals.json']);oi=obj(d['before']['health-write-intent.json']);ni=obj(tree['health-write-intent.json']);assert oi['owner']==ni['owner'] and oi['lifecycle']!=ni['lifecycle'] and ni['events']==[]
for k,v in d['preservationBeforeCommit']['files'].items():assert tree[k]==v
final=d['finalCleanupBeforeRelaunch'];assert final['ownedRootsAbsent'] and final['stageAbsent'] and not final['hostDeletedWorkspace'];assert tree==final['treeAtParentBeforeRelaunch'];assert d['providerIdentityExact'] and d['conflictingHealthyGoalsChecked'];assert hashlib.sha256((b/(sys.argv[2] if len(sys.argv)>2 else 'health-recovery-error-state-driver-r1.py')).read_bytes()).hexdigest()==d['verifierSHA256']
root=pathlib.Path(d['readerHeld']['protocol']['root']);actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()};assert actual==set(d['after']);assert not any(p.is_symlink() for p in root.rglob('*'))
for k,v in d['after'].items():assert (root/k).read_bytes()==data(v),k
priv=[k for k in actual if k.startswith('.health-recovery/')];assert len(priv)==8
print(json.dumps({'status':'PASS independent embedded/source/reader/current/prior/receipt/freshphoto/intent/cleanup/relaunch/live23file audit','prefix':prefix,'embeddedByteRecordsValidated':count,'liveFilesByteChecked':len(actual),'livePrivateFilesByteChecked':len(priv),'readerPID':r['pid'],'readerFD':r['descriptor'],'scope':'Main/light/standard ordinary-state declared endpoints only; no full parent/timing/VO/motion/allrawprior acceptance'}))
