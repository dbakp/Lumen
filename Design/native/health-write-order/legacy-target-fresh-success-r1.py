"""Read-only complete successful fresh-authority recovery facts and validators."""
import base64,json,stat
from datetime import datetime
from pathlib import PurePosixPath
from uuid import UUID

def validate(record,first,provider,h,v,started):
    """Validate actual trees/payloads; never accept a stored PASS label."""
    for name in ['current','prior']:v.tree(record[name],h)
    current=record['current'];prior=record['prior'];before=first['current']
    assert record['provider']==provider==first['provider']
    assert set(record['residuals'])=={'LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*'}
    assert not any(record['residuals'].values())
    # Successful publication legitimately retires the older .previous and moves
    # the original current root to .previous. Do not impose rejection semantics.
    assert prior['files']==before['files'] and prior['rootIdentity']==before['rootIdentity']
    identity_keys=['st_ino','st_dev','st_mode','st_size','st_mtime_ns']
    for name,wanted in before['files'].items():
        if name=='health-write-intent.json':continue
        assert current['files'][name]==wanted
        assert all(current['metadata']['files'][name]['identity'][k]==before['metadata']['files'][name]['identity'][k] for k in identity_keys)
    for name in before['files']:
        assert all(prior['metadata']['files'][name]['identity'][k]==before['metadata']['files'][name]['identity'][k] for k in identity_keys)
    oldjournal=json.loads(v.payload(before['files']['health-write-intent.json'],h))
    journal=json.loads(v.payload(current['files']['health-write-intent.json'],h))
    assert set(journal)==set(oldjournal) and journal['version']==oldjournal['version']
    assert journal['owner']==oldjournal['owner'] and journal['lifecycle']!=oldjournal['lifecycle']
    UUID(journal['lifecycle']);assert len(journal['events'])==len(oldjournal['events'])==2
    for actual,wanted in zip(journal['events'],oldjournal['events']):
        actual=dict(actual);wanted=dict(wanted)
        issue=actual.pop('issue',None);oldissue=wanted.pop('issue',None)
        # Actual didCommit kicks pending work. With Health disconnected, the
        # existing deletion can record unavailable; identities/payload/acks and
        # the withdrawn old save must remain exact. No imported saves are queued.
        assert actual==wanted
        if actual['action']=='delete':assert issue in [oldissue,'unavailable']
        else:assert issue==oldissue
    assert {event['localID'] for event in journal['events']}=={'synthetic-reset-pending-removal','synthetic-reset-unstarted-save'}
    assert all(event['lifecycle']!=journal['lifecycle'] for event in journal['events'])
    def read(name):return v.payload(current['files'][name],h)
    source=json.loads(v.payload(provider,h));payload=base64.b64decode(source['payload'],validate=True)
    assert h.sha(payload)==source['sha256'];snapshot=json.loads(payload)
    meals=json.loads(read('meals.json'));assert len(meals)==len(snapshot['meals'])==2
    assert json.loads(read('workouts.json'))==snapshot['workouts']==[]
    photo_digests={};newids=set()
    for actual,wanted in zip(meals,snapshot['meals']):
        actual=dict(actual);wanted=dict(wanted);new=actual.pop('photoID');old=wanted.pop('photoID')
        UUID(new);assert new not in snapshot['photos'] and new not in newids;newids.add(new)
        assert actual==wanted
        name='photos/'+new+'.jpg';raw=read(name);expected=base64.b64decode(snapshot['photos'][old],validate=True)
        assert raw==expected;photo_digests[name]=h.sha(raw)
    assert {name for name in current['files'] if name.startswith('photos/')}==set(photo_digests)
    receipts=[name for name in current['files'] if name.startswith('.health-recovery-history/')]
    assert len(receipts)==1;assert len(PurePosixPath(receipts[0]).parts)==2
    UUID(PurePosixPath(receipts[0]).stem);receipt=json.loads(read(receipts[0]))
    assert set(receipt)=={'source','domains','recordDigests','photoDigests','recoveredAt','fileSource','omittedPhotoCount','reviewedPhotos'}
    assert receipt['source']=='selected-file:'+provider['sha256'] and receipt['domains']==['meals','workouts']
    assert receipt['fileSource']=={'fileName':PurePosixPath(provider['file']).name,'format':'legacyJSONBackup','byteCount':provider['bytes'],'sha256':provider['sha256']}
    assert receipt['omittedPhotoCount']==0 and type(receipt['omittedPhotoCount']) is int
    assert receipt['recordDigests']=={name:h.sha(read(name)) for name in ['meals.json','workouts.json']}
    assert receipt['photoDigests']==photo_digests
    assert receipt['reviewedPhotos']=={name:{'byteCount':len(base64.b64decode(value,validate=True)),'sha256':h.sha(base64.b64decode(value,validate=True))} for name,value in snapshot['photos'].items()}
    recovered=datetime.fromisoformat(receipt['recoveredAt'].replace('Z','+00:00')).timestamp()
    assert started-1<=recovered<=record['observedAt']+1
    # The earlier Today copy stays exact. Exactly one additional v2 copy holds
    # the genuinely current immutable legacy tokens, including newer Data40.
    oldcopies={name for name in before['files'] if name.startswith('.health-recovery/')}
    newcopies={name for name in current['files'] if name.startswith('.health-recovery/')}-oldcopies
    assert len(newcopies)==4
    manifests=[name for name in newcopies if name.endswith('/manifest.json')];assert len(manifests)==1
    parent=str(PurePosixPath(manifests[0]).parent);UUID(PurePosixPath(parent).name)
    assert newcopies=={parent+'/'+name for name in ['manifest.json','legacy-origin-meals.json','legacy-origin-workouts.json','device-intent.json']}
    manifest=json.loads(read(manifests[0]));assert set(manifest)=={'version','createdAt','domains','photos','intent','legacyOrigins'}
    assert type(manifest['version']) is int and manifest['version']==2 and manifest['domains']==['meals','workouts'] and manifest['photos'] is False and manifest['intent'] is True
    assert datetime.fromisoformat(manifest['createdAt'].replace('Z','+00:00')).tzinfo is not None
    assert set(manifest['legacyOrigins'])=={'meals','workouts'}
    for domain,wanted in [('meals',b'{synthetic newer persisted meals damaged'),('workouts',h.DATA)]:
        name='legacy-origin-'+domain+'.json';raw=read(parent+'/'+name)
        assert manifest['legacyOrigins'][domain]=={'file':name,'sha256':h.sha(raw)}
        envelope=json.loads(raw);assert type(envelope['schemaVersion']) is int
        assert envelope=={'schemaVersion':1,'domain':domain,'key':'lumen.health.'+domain+'.v1','type':'data','payload':base64.b64encode(wanted).decode(),'sha256':h.sha(wanted)}
    assert read(parent+'/device-intent.json')==v.payload(before['files']['health-write-intent.json'],h)
    expected=set(before['files'])|{'meals.json','workouts.json'}|set(photo_digests)|set(receipts)|newcopies
    assert set(current['files'])==expected and len(expected)==22
    assert current['rootIdentity']['st_ino']!=before['rootIdentity']['st_ino']
    return {'currentFiles':22,'priorFiles':13,'newPrivateFiles':4,'receipt':receipts[0],'photoDigests':photo_digests,'newPrivateDirectory':parent,'journalOwnerAndEventIdentitiesPayloadsAcknowledgementsPreserved':True,'existingDeletionIssue':next((event.get('issue') for event in journal['events'] if event['action']=='delete'),None),'journalLifecycleRotated':True,'olderPriorRetirement':'Allowed only at actual successful transaction; not rejection preservation'}

def collect(group,sink,first,provider,h,e,v,started):
    import time
    sink['observedAt']=time.time()
    for name,path in [('current',group/'LumenData'),('prior',group/'LumenData.previous')]:
        sink[name]={};e.e.observe_tree(path,sink[name])
    sink['provider']=h.provider()
    sink['residuals']={pattern:[str(path) for path in group.glob(pattern)] for pattern in ['LumenData.restore-*','LumenData.retired-*','Lumen-reset-fixture-*']}
    sink['validation']=validate(sink,first,provider,h,v,started)
