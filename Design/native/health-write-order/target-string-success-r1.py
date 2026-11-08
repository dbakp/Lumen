"""Read-only complete successful fresh-authority recovery facts and validators."""
import base64,json,stat
from datetime import datetime
from pathlib import PurePosixPath
from uuid import UUID

def validate_payloads(record,first,provider,h,v,started):
    """Validate actual trees/payloads; never accept a stored PASS label."""
    v.tree(record['current'],h)
    current=record['current'];before=first['current']
    original_prior=first['prior']
    assert record['provider']==provider==first['provider']
    # Actual successful publication retires the former current root. Selected
    # prior raw domains survive in their own v1 private copy, validated below.
    identity_keys=['st_ino','st_dev','st_mode','st_size','st_mtime_ns']
    for name,wanted in before['files'].items():
        if name=='health-write-intent.json':continue
        assert current['files'][name]==wanted
        assert all(current['metadata']['files'][name]['identity'][k]==before['metadata']['files'][name]['identity'][k] for k in identity_keys)
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
    # the genuinely current immutable legacy tokens, including newer exact String UTF16LE.
    oldcopies={name for name in before['files'] if name.startswith('.health-recovery/')}
    newcopies={name for name in current['files'] if name.startswith('.health-recovery/')}-oldcopies
    assert len(newcopies)==8
    manifests=[name for name in newcopies if name.endswith('/manifest.json')];assert len(manifests)==2
    versions={name:json.loads(read(name)) for name in manifests}
    assert sorted(value['version'] for value in versions.values())==[1,2]
    current_manifest=next(name for name,value in versions.items() if value['version']==2)
    prior_manifest=next(name for name,value in versions.items() if value['version']==1)
    parent=str(PurePosixPath(current_manifest).parent);UUID(PurePosixPath(parent).name)
    previous_parent=str(PurePosixPath(prior_manifest).parent);UUID(PurePosixPath(previous_parent).name);assert parent!=previous_parent
    current_copy={parent+'/'+name for name in ['manifest.json','legacy-origin-meals.json','legacy-origin-workouts.json','device-intent.json']}
    previous_copy={previous_parent+'/'+name for name in ['manifest.json','meals.json','workouts.json','device-intent.json']}
    assert newcopies==current_copy|previous_copy
    previous=versions[prior_manifest]
    assert set(previous)=={'version','createdAt','domains','photos','intent'}
    assert type(previous['version']) is int and previous['version']==1 and previous['domains']==['meals','workouts'] and previous['photos'] is False and previous['intent'] is True
    assert datetime.fromisoformat(previous['createdAt'].replace('Z','+00:00')).tzinfo is not None
    assert {'meals.json','workouts.json','health-write-intent.json'}<=set(original_prior['files'])
    assert not any(name.startswith('photos/') for name in original_prior['files'])
    for private_name,prior_name in [('meals.json','meals.json'),('workouts.json','workouts.json'),('device-intent.json','health-write-intent.json')]:
        assert read(previous_parent+'/'+private_name)==v.payload(original_prior['files'][prior_name],h)
    manifest=versions[current_manifest];assert set(manifest)=={'version','createdAt','domains','photos','intent','legacyOrigins'}
    assert type(manifest['version']) is int and manifest['version']==2 and manifest['domains']==['meals','workouts'] and manifest['photos'] is False and manifest['intent'] is True
    assert datetime.fromisoformat(manifest['createdAt'].replace('Z','+00:00')).tzinfo is not None
    assert set(manifest['legacyOrigins'])=={'meals','workouts'}
    for domain,wanted in [('meals',v.NEW),('workouts',v.OLD)]:
        name='legacy-origin-'+domain+'.json';raw=read(parent+'/'+name)
        assert manifest['legacyOrigins'][domain]=={'file':name,'sha256':h.sha(raw)}
        envelope=json.loads(raw);assert type(envelope['schemaVersion']) is int
        assert envelope=={'schemaVersion':1,'domain':domain,'key':'lumen.health.'+domain+'.v1','type':'stringUTF16LE','payload':base64.b64encode(wanted).decode(),'sha256':h.sha(wanted)}
    assert read(parent+'/device-intent.json')==v.payload(before['files']['health-write-intent.json'],h)
    expected=set(before['files'])|{'meals.json','workouts.json'}|set(photo_digests)|set(receipts)|newcopies
    assert set(current['files'])==expected and len(expected)==26
    assert current['rootIdentity']['st_ino']!=before['rootIdentity']['st_ino']
    return {'currentFiles':26,'requiredFinalPriorExists':False,'newPrivateFiles':8,'priorPrivateDirectory':previous_parent,'receipt':receipts[0],'photoDigests':photo_digests,'newPrivateDirectory':parent,'journalOwnerAndEventIdentitiesPayloadsAcknowledgementsPreserved':True,'existingDeletionIssue':next((event.get('issue') for event in journal['events'] if event['action']=='delete'),None),'journalLifecycleRotated':True,'olderPriorRetirement':'Selected prior meals/workouts/intent retained privately; final acceptance separately requires .previous absent. Not all13 prior files copied.'}

def collect_current(group,sink,first,provider,h,e,v,started):
    import time
    sink['observedAt']=time.time();sink['group']=str(group);sink['current']={}
    e.e.observe_tree(group/'LumenData',sink['current'])
    sink['provider']=h.provider()
    sink['validation']=validate_payloads(sink,first,provider,h,v,started)

def validate(record,first,provider,h,v,started):
    result=validate_payloads(record,first,provider,h,v,started)
    group=PurePosixPath(record['group']);assert group.is_absolute()
    namespace=record['namespace']
    assert namespace['group']==str(group)
    assert namespace['previous']=={'path':str(group/'LumenData.previous'),'exists':False,'errno':2}
    assert namespace['retired']==[] and namespace['restore']==[] and namespace['resetFixtures']==[]
    return result
