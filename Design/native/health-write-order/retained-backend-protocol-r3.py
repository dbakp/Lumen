"""Pure strict persisted-state predicates; no filesystem or simulator queries on import."""
import base64
import datetime
import hashlib
import json
import math
import plistlib
import re
import stat
import uuid

FIELDS={'st_dev','st_ino','st_mode','st_nlink','st_size','st_mtime_ns','st_ctime_ns'}
PRESERVED={'st_dev','st_ino','st_mode','st_size','st_mtime_ns'}
DOMAINS={'water','meals','workouts','goals','today'}
BASE={'chat.json','conversation-selection.json','conversations.json','health-write-intent.json',
      'water.json','meals.json','workouts.json','goals.json','today.json','photos/synthetic-review-photo.jpg'}
OPTIONAL={'profile.json','sleep.json','habits.json'}
FAILED={'water.json':b'{"syntheticUnavailableWater":','meals.json':b'{','workouts.json':b'{','goals.json':b'{','today.json':b'{'}
NUTRITION={'calories','protein','carbs','fat'}


def integer(value,minimum=0):
    assert type(value) is int and value>=minimum
    return value


def number(value):
    assert type(value) in (int,float) and math.isfinite(value)
    return value


def same(a,b):
    if type(a) is not type(b):return False
    if type(a) is dict:return a.keys()==b.keys() and all(type(k) is str and same(v,b[k]) for k,v in a.items())
    if type(a) is list:return len(a)==len(b) and all(same(x,y) for x,y in zip(a,b))
    if type(a) is float:return math.isfinite(a) and math.isfinite(b) and json.dumps(a)==json.dumps(b)
    return type(a) in (str,int,bool,type(None)) and a==b


def canonical_uuid(value):
    assert type(value) is str and str(uuid.UUID(value)).upper()==value
    return value


def digest(value):return hashlib.sha256(value).hexdigest()


def raw(row):
    fact=row['raw'];assert set(fact)=={'bytes','sha256','base64'}
    integer(fact['bytes']);assert type(fact['base64']) is str
    data=base64.b64decode(fact['base64'],validate=True)
    assert len(data)==fact['bytes'] and digest(data)==fact['sha256']
    return data


def decoded(row):return json.loads(raw(row))


def validate_sample(sample):
    assert set(sample)=={'status','startedAt','finishedAt','roots','errors','entries','totalReadBytes'}
    assert sample['status']=='SUPPORTED bounded persisted sample' and sample['errors']==[]
    assert number(sample['finishedAt'])>=number(sample['startedAt'])>0
    assert set(sample['roots'])=={'current','previous','standardPreferences','groupPreferences'}
    count=total=0;flat={};directories={};aliases={}
    def facts(value):
        assert set(value)==FIELDS
        for key,v in value.items():integer(v,0 if key in ('st_size','st_mtime_ns','st_ctime_ns') else 1)
        assert stat.S_IFMT(value['st_mode']) in (stat.S_IFREG,stat.S_IFDIR)
    def visit(row,prefix,files,dirs,is_root=False):
        nonlocal count,total
        if is_root:
            assert type(row['path']) is str and row['path'].startswith('/')
            assert type(row['absent']) is bool
            assert type(row['ancestorPathBindings']) is list and row['ancestorPathBindings']
            for link in row['ancestorPathBindings']:
                assert set(link)=={'component','descriptor','namedAfter'}
                assert type(link['component']) is str and link['component'] not in ('','.','..') and '/' not in link['component']
                for observation in (link['descriptor'],link['namedAfter']):
                    assert set(observation)=={'st_dev','st_ino','st_mode'}
                    for value in observation.values():integer(value,1)
                    assert stat.S_ISDIR(observation['st_mode'])
                assert same(link['descriptor'],link['namedAfter'])
            if row['absent']:
                assert set(row)=={'path','absent','ancestorPathBindings'};return
        count+=1
        common={'kind','identityObserved','identityBefore','identityAfter','identityNamedAfter'}
        if is_root:common|={'path','absent','ancestorPathBindings'}
        for key in ('identityObserved','identityBefore','identityAfter','identityNamedAfter'):facts(row[key])
        assert all(same(row['identityObserved'],row[key]) for key in ('identityBefore','identityAfter','identityNamedAfter'))
        integer(row['kind'],1);assert row['kind']==stat.S_IFMT(row['identityBefore']['st_mode'])
        if row['kind']==stat.S_IFDIR:
            assert set(row)==common|{'namesBefore','namesAfter','children','inventoryBefore','inventoryAfter'}
            names=row['namesBefore'];assert type(names) is list and all(type(n) is str and n not in ('','.','..') and '/' not in n for n in names)
            assert names==sorted(set(names)) and names==row['namesAfter'] and set(names)==set(row['children'])
            for key in ('inventoryBefore','inventoryAfter'):
                inv=row[key];assert set(inv)=={'names','overflow','observedAtLeast','limit'}
                assert inv['overflow'] is False and inv['names']==names
                assert integer(inv['observedAtLeast'])==len(names)<=integer(inv['limit'])<=512
            dirs[prefix]=row
            for name in names:visit(row['children'][name],prefix+'/'+name if prefix else name,files,dirs)
        else:
            assert set(row)==common|{'raw'}
            data=raw(row);assert len(data)==row['identityBefore']['st_size']<=8*1024**2
            total+=len(data);files[prefix]=row
            key=(row['identityBefore']['st_dev'],row['identityBefore']['st_ino'])
            prior=aliases.setdefault(key,[])
            if prior:
                assert data==raw(prior[0]),'Same device/inode reports conflicting contents'
                assert same({k:row['identityBefore'][k] for k in PRESERVED},
                            {k:prior[0]['identityBefore'][k] for k in PRESERVED}),'Same device/inode reports conflicting preserved metadata'
            prior.append(row)
    for label,root in sample['roots'].items():
        if label!='previous':assert root['absent'] is False and root['kind']==stat.S_IFDIR,'Required data/Preferences directory absent'
        flat[label]={};directories[label]={};visit(root,'',flat[label],directories[label],True)
    for linked in aliases.values():
        assert all(row['identityBefore']['st_nlink']>=len(linked) for row in linked),'Link count smaller than sampled distinct aliases'
    assert integer(sample['entries'])==count<=512
    assert integer(sample['totalReadBytes'])==total<=32*1024**2
    return {'files':flat,'directories':directories}


def journal(row):
    value=decoded(row);assert set(value)=={'version','owner','lifecycle','events'}
    assert integer(value['version'],1)==1 and value['events']==[]
    canonical_uuid(value['owner']);canonical_uuid(value['lifecycle']);return value


def preserved(before,after):
    assert raw(before)==raw(after)
    assert same({k:before['identityBefore'][k] for k in PRESERVED},
                {k:after['identityBefore'][k] for k in PRESERVED})


def plist_value(value):
    """Typed semantic form, preserving Data/Date/Boolean versus number distinctions."""
    if type(value) is dict:
        assert all(type(k) is str for k in value);return {'type':'dict','value':{k:plist_value(v) for k,v in value.items()}}
    if type(value) is list:return {'type':'array','value':[plist_value(v) for v in value]}
    if type(value) is bytes:return {'type':'data','base64':base64.b64encode(value).decode()}
    if type(value) is datetime.datetime:return {'type':'date','value':value.isoformat()}
    if type(value) is float:number(value)
    assert type(value) in (str,int,float,bool)
    return {'type':type(value).__name__,'value':value}


def preferences(parsed,label):
    files=parsed['files'][label];expected='com.dbakp.lumen.plist' if label=='standardPreferences' else 'group.com.dbakp.lumen.plist'
    assert set(files).issubset({expected})
    assert set(parsed['directories'][label]).issubset({''})
    value=plistlib.loads(raw(files[expected])) if expected in files else {}
    assert type(value) is dict;plist_value(value);return value


def issue(domains):
    labels={'water':'water history','meals':'meal history','workouts':'workout history','goals':'targets','today':'daily readings'}
    text=', '.join(sorted(labels[d] for d in domains));return text[0].upper()+text[1:]+" couldn't be opened. Changes to this data are paused. Lumen hasn't replaced the saved data."


def packet(value):
    assert type(value) is bytes;row=json.loads(value)
    assert set(row)=={'day','capturedAt','values','estimates'}
    number(row['day']);number(row['capturedAt']);assert row['day']<=row['capturedAt']+60
    assert type(row['values']) is dict and all(type(k) is str and number(v)>=0 for k,v in row['values'].items())
    assert type(row['estimates']) is list and all(type(v) is str for v in row['estimates'])
    assert len(set(row['estimates']))==len(row['estimates']);return row


def exact_directories(parsed,label):
    expected={''} if parsed['directories'][label] else set()
    for path in parsed['files'][label]:
        parts=path.split('/')
        expected.update('/'.join(parts[:i]) for i in range(1,len(parts)))
    assert set(parsed['directories'][label])==expected,'Unknown or missing empty directory'


def iso_time(value):
    assert type(value) is str and re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ',value)
    return datetime.datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()


def validate_pre(sample,copy_id):
    assert re.fullmatch(r'healthRecoveryCopy-discovered-[0-9a-f]{64}',copy_id)
    parsed=validate_sample(sample);current=parsed['files']['current'];previous=parsed['files']['previous']
    for label in parsed['files']:exact_directories(parsed,label)
    identifier=copy_id[len('healthRecoveryCopy-'):];prefix='.health-recovery/'+identifier+'/'
    source_names={d+'.json' for d in DOMAINS}|{'manifest.json','device-intent.json','photos/synthetic-review-photo.jpg'}
    source={name:current[prefix+name] for name in source_names}
    assert set(current)==(BASE|(set(current)&OPTIONAL)|{prefix+n for n in source_names})
    assert BASE.issubset(previous) and set(previous).issubset(BASE|OPTIONAL)
    for name,data in FAILED.items():assert raw(current[name])==data
    initial=journal(current['health-write-intent.json']);assert same(initial,journal(previous['health-write-intent.json']))
    for name in {d+'.json' for d in DOMAINS}|{'photos/synthetic-review-photo.jpg'}:
        preserved(previous[name],source[name])
    preserved(previous['health-write-intent.json'],source['device-intent.json'])
    manifest=decoded(source['manifest.json']);assert set(manifest)=={'version','createdAt','domains','photos','intent'}
    assert integer(manifest['version'],1)==1 and manifest['domains']==sorted(DOMAINS)
    assert manifest['photos'] is True and manifest['intent'] is True
    assert iso_time(manifest['createdAt'])<=sample['finishedAt']+1
    # Deterministic sorted-key fixture encoded by unchanged260 production fixture source.
    # Historical canonical754Bsource bytes establish a predeclared fixture expectation, not a new native pass.
    assert len(raw(source['meals.json']))==754 and digest(raw(source['meals.json']))=='7c711206ccacdd0c9cdf12bc06308e7408407c48c77701d150fe75ec415967a7'
    meals=decoded(source['meals.json']);assert type(meals) is list and len(meals)==2
    assert all(iso_time(m['date'])<sample['startedAt']-3*86400 for m in meals),'Fixture meals must precede any current local day'
    assert {m['id'] for m in meals}=={'synthetic-first-meal','synthetic-second-meal'}
    assert all(m['photoID']=='synthetic-review-photo' for m in meals)
    assert raw(current['photos/synthetic-review-photo.jpg'])==raw(source['photos/synthetic-review-photo.jpg'])
    standard=preferences(parsed,'standardPreferences');shared=preferences(parsed,'groupPreferences')
    for key in ('lumen.health.meals.v1','lumen.health.workouts.v1','lumen.health.goals.v1'):assert key not in standard
    if 'lumen.health.connected' in standard:assert standard['lumen.health.connected'] is False
    assert shared['health.localStorageIssue']==issue(DOMAINS)
    before_packet=packet(shared['widget.evidence.v1']);assert before_packet['values']=={} and before_packet['estimates']==[]
    return {'parsed':parsed,'identifier':identifier,'sourcePrefix':prefix,'source':source,'journal':initial,
            'standard':standard,'shared':shared,'packet':before_packet}


def validate_post(before,sample,copy_id,prior_post=None,allow_pending_refresh=False):
    assert type(allow_pending_refresh) is bool
    pre=validate_pre(before,copy_id);post=validate_sample(sample)
    for label in post['files']:exact_directories(post,label)
    old=pre['parsed']['files']['current'];current=post['files']['current'];prefix=pre['sourcePrefix']
    assert sample['roots']['previous']['absent'] is True
    assert before['roots']['current']['identityBefore']['st_dev']==sample['roots']['current']['identityBefore']['st_dev']
    assert before['roots']['current']['identityBefore']['st_ino']!=sample['roots']['current']['identityBefore']['st_ino']
    receipts=[n for n in current if n.startswith('.health-recovery-history/')]
    assert len(receipts)==1;canonical_uuid(leaf_identifier(receipts[0],'.health-recovery-history/','.json'))
    receipt=decoded(current[receipts[0]]);assert set(receipt)=={'source','domains','recordDigests','photoDigests','recoveredAt'}
    assert receipt['source']=='retained:'+pre['identifier'] and receipt['domains']==['meals']
    assert receipt['recordDigests']=={'meals.json':digest(raw(current['meals.json']))}
    assert before['startedAt']-1<=iso_time(receipt['recoveredAt'])<=sample['finishedAt']+1
    source_meals=decoded(pre['source']['meals.json']);meals=decoded(current['meals.json'])
    assert type(meals) is list and len(meals)==2
    photos={m['photoID'] for m in meals};assert len(photos)==1;photo_id=canonical_uuid(next(iter(photos)))
    for a,b in zip(source_meals,meals):assert same(dict(a,photoID=photo_id),b)
    new_photo='photos/'+photo_id+'.jpg';assert receipt['photoDigests']=={new_photo:digest(raw(current[new_photo]))}
    assert raw(current[new_photo])==raw(pre['source']['photos/synthetic-review-photo.jpg'])
    def node(row):return tuple(row['identityBefore'][key] for key in ('st_dev','st_ino'))
    assert node(current['meals.json'])!=node(old['meals.json']),'Selected replacement reuses failed-original inode'
    assert node(current[new_photo])!=node(pre['source']['photos/synthetic-review-photo.jpg']),'New live photo must be an independent copy'
    incidents={n.split('/')[1] for n in current if n.startswith('.health-recovery/')}- {pre['identifier']}
    assert len(incidents)==1;incident=canonical_uuid(next(iter(incidents)));private='.health-recovery/'+incident+'/'
    expected_private={private+n for n in ('manifest.json','device-intent.json','meals.json','photos/synthetic-review-photo.jpg')}
    private_manifest=decoded(current[private+'manifest.json'])
    assert set(private_manifest)=={'version','createdAt','domains','photos','intent'}
    assert integer(private_manifest['version'],1)==1 and private_manifest['domains']==['meals']
    assert private_manifest['photos'] is True and private_manifest['intent'] is True
    assert before['startedAt']-1<=iso_time(private_manifest['createdAt'])<=sample['finishedAt']+1
    for source,target in [('meals.json',private+'meals.json'),('health-write-intent.json',private+'device-intent.json'),('photos/synthetic-review-photo.jpg',private+'photos/synthetic-review-photo.jpg')]:preserved(old[source],current[target])
    removed={'photos/synthetic-review-photo.jpg'}
    assert set(current)==(set(old)-removed)|expected_private|{new_photo,receipts[0]}
    for name in set(old)-{'meals.json','health-write-intent.json'}-removed:preserved(old[name],current[name])
    after_journal=journal(current['health-write-intent.json']);assert after_journal['owner']==pre['journal']['owner'] and after_journal['lifecycle']!=pre['journal']['lifecycle']
    standard=preferences(post,'standardPreferences');shared=preferences(post,'groupPreferences')
    assert same(plist_value(pre['standard']),plist_value(standard))
    changed={'widget.evidence.v1','health.localStorageIssue'}
    assert same(plist_value({k:v for k,v in pre['shared'].items() if k not in changed}),plist_value({k:v for k,v in shared.items() if k not in changed}))
    actual_issue=shared['health.localStorageIssue'];old_issue=pre['shared']['health.localStorageIssue']
    new_issue=issue(DOMAINS-{'meals'})
    assert actual_issue==new_issue or (allow_pending_refresh and actual_issue==old_issue), 'Unknown shared storage issue transition'
    after_packet=packet(shared['widget.evidence.v1'])
    # CurrentHealthEvidence.local returns nil when the current-day dates array is empty.
    # Recovering these old fixture meals must NOT invent today's nutrition zeros.
    assert after_packet['values']=={} and after_packet['estimates']==[]
    for key in ('day','capturedAt'):
        assert pre['packet'][key]<=after_packet[key] and after_packet[key]+978307200<=sample['finishedAt']+60
    packet_pending=same(plist_value(shared['widget.evidence.v1']),plist_value(pre['shared']['widget.evidence.v1']))
    if not packet_pending:
        assert after_packet['capturedAt']>pre['packet']['capturedAt'], 'Refreshed widget capture must advance'
        assert before['startedAt']-1<=after_packet['capturedAt']+978307200, 'Refreshed widget capture predates pre-action boundary'
    pending=actual_issue==old_issue or packet_pending
    assert allow_pending_refresh or not pending, 'Persisted declared refresh still pending'
    if prior_post is not None:
        assert not pending, 'Final endpoint cannot regress to baseline preferences'
        previous_post=validate_sample(prior_post)
        assert set(previous_post['files']['current'])==set(current)
        for name in current:preserved(previous_post['files']['current'][name],current[name])
        assert same(plist_value(preferences(previous_post,'standardPreferences')),plist_value(standard))
        assert same(plist_value(preferences(previous_post,'groupPreferences')),plist_value(shared))
    return {'observation':'OBSERVED_PENDING' if pending else 'VALID_ENDPOINT',
            'pendingRefresh':{'storageIssue':actual_issue==old_issue,'widgetPacket':packet_pending},
            'receipt':receipts[0],'privateIncident':incident,'photoID':photo_id,'selected':['meals'],
            'preservedCurrentLeaves':len(set(old)-{'meals.json','health-write-intent.json'}-removed),
            'oldFailedMealAndPhotosPreservedByIdentity':True,'emptyJournalSameOwnerDistinctLifecycle':True,'newPhotoIndependentInode':True,
            'persistedStandardDefaultsUnchanged':True,'sharedOnlyDeclaredRefreshTransitions':True,
            'scope':'Sampled persisted transaction endpoints only; nlink/ctime/directory identities can legitimately change, no global atomic/continuous/cacheddefaults/noHealthAPI or appearance acceptance.'}


def leaf_identifier(value,prefix,suffix):
    assert value.startswith(prefix) and value.endswith(suffix)
    name=value[len(prefix):-len(suffix)]
    assert '/' not in name and name;return name


def bind_roots(sample,expected):
    """Caller supplies roles from actual bound app/group container queries, not sample paths."""
    assert type(expected) is dict and set(expected)=={'current','previous','standardPreferences','groupPreferences'}
    assert set(sample['roots'])==set(expected)
    for label,path in expected.items():
        assert type(path) is str and path.startswith('/') and '/..' not in path
        assert sample['roots'][label]['path']==path,('Wrong container/path role',label)
    return True
