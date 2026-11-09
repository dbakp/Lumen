"""Strict pure validators for the separate real deadline / late-acknowledgement case."""
import base64
import hashlib
from uuid import UUID
GATE={'runID','pid','sessionID','captureID','nonce','appearanceID','domains','legacyDomains','omitPhotos'}
PROTOCOL='Lumen-confirmation-expiry-verification-v1'

def uuid(value):
    assert type(value) is str and str(UUID(value)).upper()==value

def binding(value):
    assert set(value)==GATE and all(type(x) is str for x in value.values())
    for key in ['runID','sessionID','captureID','nonce','appearanceID']:uuid(value[key])
    assert value['pid'].isdigit() and str(int(value['pid']))==value['pid'] and int(value['pid'])>0
    assert value['domains']==value['legacyDomains']=='meals' and value['omitPhotos']=='false'

def trace(row,gate,started,complete=False):
    binding(gate)
    assert set(row)=={'verificationProtocol','binding','taskGeneration','events','checks','problems'}
    assert row['verificationProtocol']==PROTOCOL and row['binding']==gate and row['problems']==[]
    uuid(row['taskGeneration'])
    events=row['events'];names=['created','wait-started','closed','wait-exit','task-value-completed']
    assert 1<=len(events)<=5 and [r['event'] for r in events]==names[:len(events)]
    if complete:assert len(events)==5
    previous=started
    fields=[{}, {'taskCancelled':False,'closed':False,'consumed':False,'controlCancelled':False},
            {'reason':'deadline','closed':True,'consumed':False,'controlCancelled':True},
            {'errorType':'Lumen.HealthLegacyTargetChangeUIFixture.Failure','taskCancelled':False,'closed':True,'consumed':False,'controlCancelled':True,'expiryClock':'ContinuousClock','expiryLimitSeconds':90,'expiryElapsedSeconds':None,'expiryElapsedAttoseconds':None},{}]
    for item,wanted in zip(events,fields):
        assert set(item)=={'event','at'}|set(wanted)
        assert type(item['at']) in [int,float] and item['at']>=previous
        previous=item['at']
        assert all(type(item[k]) is type(v) and item[k]==v for k,v in wanted.items() if v is not None)
        if item['event']=='wait-exit':
            assert type(item['expiryElapsedSeconds']) is int and item['expiryElapsedSeconds']>=90
            assert type(item['expiryElapsedAttoseconds']) is int and 0<=item['expiryElapsedAttoseconds']<10**18
    assert type(row['checks']) is list and len(row['checks'])<=1
    return row

def check(row,main,ack_bytes,published_at,native_touch,native_return,e):
    assert set(row)=={'verificationProtocol','binding','taskGeneration','check'}
    assert row['verificationProtocol']==PROTOCOL and row['binding']==main['binding']
    assert row['taskGeneration']==main['taskGeneration']
    value=row['check'];uuid(value['requestID'])
    assert type(value['ordinal']) is int and value['ordinal']==1 and value['status']=='checked'
    assert native_touch<=value['touchAt']<=native_return
    assert published_at<value['touchAt']<=value['ackReadStartedAt']<=value['ackReadFinishedAt']
    raw=value['acknowledgement']
    assert raw=={'bytes':len(ack_bytes),'sha256':hashlib.sha256(ack_bytes).hexdigest(),'base64':base64.b64encode(ack_bytes).decode()}
    import json
    expected={k:main['binding'][k] for k in ['runID','pid','sessionID','captureID','nonce']}
    assert json.loads(ack_bytes)==dict(expected,phase='ui-observed')
    facts=value['nativeFacts']
    assert value['ackReadFinishedAt']<=facts['readStartedAt']<=facts['readFinishedAt']<=value['finishedAt']
    assert facts['fixtureBinding']=={k:main['binding'][k] for k in ['runID','pid','sessionID','captureID']}
    assert facts['fixtureFlags']=={'singleUseConsumed':False,'knownKeyWritten':False,'failed':False}
    assert all(type(v) is bool and v is False for v in facts['fixtureFlags'].values())
    assert facts['healthConnected'] is False and facts['knownKeyWritten'] is False and facts['originalValuesVerified'] is True
    e.obs.native_fixed(facts['fixed'],e.h.DATA,e.h)
    header=main['checks'];assert len(header)==1
    for key in ['ordinal','requestID','touchAt','status']:assert header[0][key]==value[key]
    return value

def marker(row,phase,armed,started,now,geometry):
    assert row['scope']=='actual-confirmation-expiry-before-notnow-late-ack'
    assert row['phase']==phase and row['gate']==armed
    assert started<=row['at']<=now
    suffix={'presented':'presented','expired':'expired','dismissed':'not-now-choices','checked':'checked'}[phase]
    assert row['attachmentName']=='health-confirmation-expiry-'+suffix
    assert type(row['imageBytes']) is int and 1000<row['imageBytes']<=4*1024*1024
    assert len(row['imageSHA256'])==64 and all(c in '0123456789abcdef' for c in row['imageSHA256'])
    if phase in ['presented','expired']:
        assert row['title']=='Replace selected data?' and row['body']==geometry.BODY
        assert geometry.contains(row['appFrame'],row['alertFrame'])
        for key in ['bodyFrame','recoverFrame','cancelFrame']:assert geometry.contains(row['alertFrame'],row[key])
        for key in ['recoverFrame','cancelFrame']:assert row[key]['width']>=44 and row[key]['height']>=44
        assert row['recoverFrame']!=row['cancelFrame']
        if phase=='expired':
            assert started<=row['expiryWaitStartedAt']<=row['expiryRelayObservedAt']<=row['at']
            for key in ['recoverEnabled','cancelEnabled','recoverHittable','cancelHittable']:assert row[key] is True
            relay=row['expiredRelay'];assert relay==dict(armed,phase='expired',targetPhase='host-expired',expiredTraceSHA256=relay['expiredTraceSHA256'])
            assert len(relay['expiredTraceSHA256'])==64 and all(c in '0123456789abcdef' for c in relay['expiredTraceSHA256'])
    else:
        assert started<=row['touchAt']<=row['tapReturnedAt']<=row['at']
        if phase=='dismissed':assert row['alertDismissed'] is True and row['choiceValues']==['1','0','0']
        else:assert row['identifier']=='checkConfirmationLifecycle' and row['value']=='checked-1'
    return row
