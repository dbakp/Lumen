"""Read-only post-run audit; never seed, reset, ack or mutate a simulator."""
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import sys
import time

base = Path(__file__).resolve().parent
repo = base.parents[2]
prefix, output = sys.argv[1:3]
r = json.loads((base / (prefix + '-host-audit.json')).read_bytes())
sha = lambda b: hashlib.sha256(b).hexdigest()
source = json.loads((base / r['source']).read_bytes())
archive = json.loads(gzip.decompress((base / (r['source'] + '.gz')).read_bytes()))
for group, key in [('files', 'files'), ('fixtureInputs', 'binaryFiles')]:
    for name, row in source[group].items():
        path = repo / name
        assert stat.S_ISREG(path.lstat().st_mode) and not path.is_symlink()
        data = path.read_bytes()
        archived = archive[key][name].encode() if key == 'files' else base64.b64decode(archive[key][name], validate=True)
        assert data == archived and len(data) == row['bytes'] and sha(data) == row['sha256'], name
images = json.loads((base / (prefix + '-images.json')).read_bytes())
readbacks = json.loads((base / (prefix + '-readbacks.json')).read_bytes())
assert len(images) == 20 and len(readbacks) == 1
for row in images + readbacks:
    data = (base / row['file']).read_bytes()
    assert len(data) == row['bytes'] and sha(data) == row['sha256'] and row['source'] == r['source']
    assert Path(row['raw']).read_bytes() == data
    if row in images: assert struct.unpack('>II', data[16:24]) == (1206, 2622)
helper = json.loads((base / readbacks[0]['file']).read_bytes())
for field in ['backAtGenuineFailure','failedBeforeTestScroll','freshChoicesAndOmissionOff','initialChoicesOff','omissionNotNowRetained','retryWithoutOmission','successObserved']:
    assert helper[field] is True
assert helper['boundedScrollObservationSeconds'] == 3 and helper['format'] == r['case']
disclosure = helper['postSuccessDisclosure']
assert disclosure['completeMessage'] == 'Older saved data will stay in a private recovery copy on this iPhone. For meal recovery, this includes any old photos.'
assert disclosure['afterSuccessAcknowledgement'] is True and disclosure['successValue'] == 'success-observed'
assert disclosure['wholeMessageInSingleFrame'] is True
frame=disclosure['frame']
assert frame['width']>0 and frame['height']>0
assert frame['x']>=disclosure['usableLeft'] and frame['x']+frame['width']<=disclosure['usableRight']
assert frame['y']>=disclosure['usableTop']-2 and frame['y']+frame['height']<=disclosure['usableBottom']
assert sum('post-success-older-data' in row['metadata']['suggestedHumanReadableName'] for row in images)==1

summary = json.loads((base / (prefix + '-summary.json')).read_bytes())
assert (summary['passedTests'],summary['failedTests'],summary['skippedTests'],r['producerExitCode']) == (1,0,0,0)
embedded = 0
def payloads(value):
    global embedded
    if isinstance(value, dict):
        if {'base64','bytes','sha256'}.issubset(value):
            raw = base64.b64decode(value['base64'], validate=True)
            assert len(raw) == value['bytes'] and sha(raw) == value['sha256']
            embedded += 1
        for child in value.values(): payloads(child)
    elif isinstance(value, list):
        for child in value: payloads(child)
payloads(r)
root = Path(r['readerHeld']['protocol']['root'])
assert stat.S_ISDIR(root.lstat().st_mode) and not root.is_symlink()
actual = {}
for parent, dirs, files in os.walk(root, followlinks=False):
    for name in dirs: assert not (Path(parent)/name).is_symlink()
    for name in files:
        path = Path(parent)/name
        assert stat.S_ISREG(path.lstat().st_mode) and not path.is_symlink()
        data = path.read_bytes()
        actual[str(path.relative_to(root))] = {'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode()}
assert actual == r['after']
assert not list(root.parent.glob('LumenData.restore-*')) and not list(root.parent.glob('LumenData.retired-*'))
assert not root.with_suffix('.previous').exists()
# Read only this declared simulator's data container and fixed known keys.
container = Path(subprocess.check_output(['xcrun','simctl','get_app_container',r['device'],'com.dbakp.lumen','data'],text=True).strip())
values = plistlib.loads((container/'Library/Preferences/com.dbakp.lumen.plist').read_bytes())
for domain, row in r['fixedLegacyValues'].items():
    assert domain in ['meals','workouts'] and row['key'] == 'lumen.health.' + domain + '.v1'
    value = values[row['key']]
    assert isinstance(value, bytes if r['origin']=='data' else str)
    raw = value if isinstance(value,bytes) else value.encode('utf-16-le')
    assert raw == base64.b64decode(row['base64'], validate=True) and sha(raw) == row['sha256']
for copy in r['retainedDamagedPaths']:
    directory = Path(copy['envelopes']['meals']['file']).parent
    assert directory.is_relative_to(root) and not directory.is_symlink()
    expected = {'manifest.json','legacy-origin-meals.json','legacy-origin-workouts.json','device-intent.json'}
    assert {x.name for x in directory.iterdir()} == expected
    assert json.loads((directory/'manifest.json').read_bytes()) == copy['manifest']
    assert copy['manifest']['version'] == 2 and copy['manifest']['photos'] is False and copy['manifest']['intent'] is True
    assert (directory/'device-intent.json').read_bytes() == base64.b64decode(r['before']['health-write-intent.json']['base64'])
    for domain, envelope in copy['envelopes'].items():
        path = Path(envelope['file']); data = path.read_bytes()
        assert sha(data) == envelope['sha256'] and json.loads(data) == envelope['envelope']
        assert envelope['envelope']['payload'] == r['fixedLegacyValues'][domain]['base64']
for photo, digest in r['receipt']['photoDigests'].items(): assert sha((root/photo).read_bytes()) == digest
boundary = json.loads((base/(prefix+'-legacy-boundaries.json')).read_bytes())['observations']
assert boundary == r['fixedValueObservations'] and all(x['status']=='PASS' for x in boundary)
assert json.loads((base/(prefix+'-v2-copy-boundaries.json')).read_bytes())['observations'] == r['v2CopyObservations']
assert [x['boundary'] for x in r['v2CopyObservations']] == ['success-before-ack','after-relaunch']
for sample in boundary:
    assert sample['originOwnerEvents'] == r['originReviewEvents'][:len(sample['originOwnerEvents'])]
inputs = json.loads((base/r['inputProvenance']).read_bytes())
provider = next(x for x in inputs['files'] if Path(x['input']).name == r['receipt']['fileSource']['fileName'])
path = Path(provider['seeded']); facts = path.lstat()
assert not path.is_symlink() and sha(path.read_bytes()) == provider['sha256']
assert (facts.st_ino,facts.st_dev,facts.st_mode,facts.st_mtime_ns) == (provider['inode'],provider['device'],provider['mode'],provider['modifiedNS'])
result = {'status':'PASS read-only post-run audit','source':r['source'],'hostAudit':prefix+'-host-audit.json','currentArchiveInputsExact':len(source['files'])+len(source['fixtureInputs']),
          'originalImageBindings':len(images),'completeNativeJSONBytes':readbacks[0]['bytes'],'embeddedPayloadRowInstancesDecoded':embedded,'liveFilesExact':len(actual),'fixedTypedPersistentKeys':len(r['fixedLegacyValues']),
          'fixedValueBoundarySamples':len(boundary),'v2CopySamples':len(r['v2CopyObservations']),'providerIdentityExact':True,'verifierSHA256':sha(Path(__file__).read_bytes()),'checkedAt':time.time(),
          'scope':'Actual current simulator/file/preferences readback plus retained source/native/protocol/v2/receipt provenance; snapshots only. No new native execution, appearance/VO/motion/all-timing/allrawprior/oldphoto/full-product acceptance.'}
(base/output).write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
