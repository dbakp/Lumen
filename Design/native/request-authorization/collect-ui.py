"""Collect a terminal, passing synthetic UI run without retaining health contents."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--run', required=True)
parser.add_argument('--device', required=True)
parser.add_argument('--source', required=True)
parser.add_argument('--pre-search', action='store_true')
parser.add_argument('--marked-title', action='store_true')
args = parser.parse_args()
assert args.run.startswith('UIR') and args.run[3:].isdigit()
base = Path(__file__).resolve().parent
raw = Path('/tmp/LumenBatch41Checks')
name = 'ui-r' + args.run[3:]
bundle = raw / (args.run + '.xcresult')
summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle), '--compact']))
assert summary['passedTests'] == 1 and summary['failedTests'] == 0 and summary['skippedTests'] == 0
(base / (name + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')

def get(path):
    with urllib.request.urlopen('http://127.0.0.1:48731/' + path, timeout=5) as response:
        assert response.status == 200
        return json.load(response)

packets, counts = get('personal-audit'), get('counts')
assert len(packets) == (1 if args.pre_search else 2)
assert all(not value.get('holdTimeouts', 0) for value in counts.values())
assert packets[-1]['canaries']['library41']['system'] == packets[-1]['canaries']['library41']['assistant'] == 0
if not args.pre_search:
    assert packets[0]['canaries']['library41']['system'] > 0
else:
    assert counts['prepared-stage']['requests'] == 1 and counts['prepared-stage']['responsesWritten'] == 1
(base / (name + '-host-readback.json')).write_text(json.dumps({'personalAudit': packets, 'routes': counts}, indent=2) + '\n')
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device, 'com.dbakp.lumen', 'data'], text=True).strip())
root = container / 'Library/Application Support/LumenData'
documents = json.loads((root / 'documents.json').read_text())
conversations = json.loads((root / 'conversations.json').read_text())
assert len(documents) == 3 and len(conversations) == 1
messages = conversations[0]['messages']
assert [message['role'] for message in messages] == ['user', 'coach', 'user', 'coach']
answers = [message for message in messages if message['role'] == 'coach']
notice = 'Library records or search settings changed during this ' + ('request' if args.pre_search else 'reply') + '. Send your question again to use the current settings.'
assert answers[0]['text'] == notice and 'Synthetic flexible plan' in answers[1]['text']
manual = [document for document in documents if document.get('messageID') == answers[0]['id']]
plans = [document for document in documents if document['kind'] == 'plan']
assert len(manual) == 1 and manual[0]['kind'] == 'note' and manual[0]['body'] == notice
if args.marked_title:
    expected_title = 'Library records or search settings changed during this ' + ('request' if args.pre_search else 'reply') + '. Send your…'
    assert manual[0]['title'] == expected_title
assert len(plans) == 1 and plans[0]['messageID'] == answers[1]['id'] and len(plans[0]['steps']) == 3
assert all(not document['includeInAssistant'] for document in documents)
files = {file: hashlib.sha256((root / file).read_bytes()).hexdigest() for file in ['documents.json', 'conversations.json', 'conversation-selection.json']}
readback = dict(scope='Actual dedicated synthetic simulator files after terminal pass. No arbitrary file contents retained.', source=args.source,
                conversationCount=1, userQuestionCount=2, savedReplyCount=2, documentCount=3, noticeSavedAsNoteOnly=True,
                automaticPlans=1, genuinePlanSteps=3, allDocumentsSharingOff=True, markedTitleChecked=args.marked_title, noticeMessageID=answers[0]['id'], planMessageID=answers[1]['id'], files=files)
(base / (name + '-file-readback.json')).write_text(json.dumps(readback, indent=2) + '\n')
export = raw / (args.run + 'Attachments')
if not (export / 'manifest.json').is_file():
    assert not export.exists(), 'Incomplete export requires inspection before replacement'
    with (raw / (args.run + 'Export.log')).open('w') as log:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(export)], check=True, stdout=log, stderr=subprocess.STDOUT)
groups = json.loads((export / 'manifest.json').read_text())
assert groups
for group in groups:
    assert group['testIdentifier'].startswith('LumenSmokeTests/testLibrary')
    for item in group['attachments']:
        assert item['deviceId'] == args.device
        assert summary['startTime'] <= item['timestamp'] <= summary['finishTime']
        file = export / item['exportedFileName']
        assert file.parent == export and file.is_file() and not file.is_symlink()
output = base / name
output.mkdir(exist_ok=True)
images = []
for group in groups:
    for item in group['attachments']:
        label = item['suggestedHumanReadableName']
        if not label.startswith(('110', '111')) or not label.endswith('.png'):
            continue
        path = output / label
        shutil.copy2(export / item['exportedFileName'], path)
        images.append({**item, 'path': str(path), 'repositoryPath': str(path.relative_to(base.parents[2])), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'source': args.source})
(output / 'manifest.json').write_text(json.dumps(images, indent=2) + '\n')
for file in [args.run + '.log', args.run + 'Server.json']:
    with gzip.open(base / (file + '.gz'), 'wb') as target:
        target.write((raw / file).read_bytes())
print(json.dumps(dict(run=args.run, status='passed', source=args.source, actualPackets=len(packets), usefulOriginals=len(images), hostFilesMatched=True)))
