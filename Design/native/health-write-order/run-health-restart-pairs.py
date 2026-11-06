"""Run serial process pairs, read back prepared files before launching resume."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--trial', default='R1')
parser.add_argument('--cases', nargs='+', default=['before-worker', 'before-receipt', 'undo-before-receipt'],
                    choices=['before-worker', 'before-receipt', 'undo-before-receipt'])
args = parser.parse_args()
base = Path(__file__).resolve().parent
repo = base.parents[2]
raw = Path('/tmp/LumenBatch43Checks')
device = '922E011C-3895-4DB1-9C9A-1D3A977226CF'
names = {'before-worker': 'BeforeWorker', 'before-receipt': 'BeforeReceipt', 'undo-before-receipt': 'Undo'}
progress = {'status': 'running', 'source': args.source, 'build': args.build, 'completed': []}
def snapshot(**fields):
    progress.update(fields)
    progress['updatedAtUTC'] = datetime.now(timezone.utc).isoformat()
    (raw / ('HealthRestartProgress' + args.trial + '.json')).write_text(json.dumps(progress, indent=2) + '\n')
def run(command, log):
    with log.open('wb') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, cwd=repo)
        snapshot(runningPID=process.pid)
        result = process.wait()
    snapshot(runningPID=None)
    if result:
        snapshot(status='failed', failedLog=str(log), exitCode=result)
        print('FAILED:', log, 'exit', result, flush=True)
        sys.exit(result if result > 0 else 1)
for scenario in args.cases:
    for phase in ['prepare', 'resume']:
        suffix = names[scenario] + phase.title() + args.trial
        stem = 'HealthRestart' + suffix
        result = raw / (stem + '.xcresult')
        assert not result.exists(), 'Never overwrite an earlier native result bundle'
        print('START:', scenario, phase, flush=True)
        snapshot(scenario=scenario, phase=phase, step='native XCTest')
        command = ['xcodebuild', '-project', 'Lumen.xcodeproj', '-scheme', 'Lumen', '-configuration', 'Debug',
                   '-destination', 'platform=iOS Simulator,id=' + device,
                   '-derivedDataPath', '/tmp/LumenBatch37Simulator',
                   '-clonedSourcePackagesDirPath', '/tmp/LumenBatch37Packages',
                   '-disableAutomaticPackageResolution', '-parallel-testing-enabled', 'NO',
                   '-only-testing:LumenUITests/LumenSmokeTests/testDurableHealthRestart' + names[scenario] + phase.title(),
                   '-resultBundlePath', str(result), 'test-without-building']
        run(command, raw / (stem + '.log'))
        log_text = (raw / (stem + '.log')).read_text()
        assert '** TEST EXECUTE SUCCEEDED **' in log_text
        snapshot(step='independent host readback')
        run([sys.executable, str(base / 'collect-health-restart.py'), phase, scenario,
             '--source', args.source, '--build', args.build, '--trial', args.trial.lower()],
            raw / (stem + 'Audit.log'))
        snapshot(step='export native originals')
        run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
             '--output-path', str(raw / (stem + 'Attachments')), '--filter', '*.png'],
            raw / (stem + 'Export.log'))
        progress['completed'].append({'scenario': scenario, 'phase': phase, 'log': stem + '.log'})
        snapshot(step='phase complete')
        print('PASS:', scenario, phase, '; native test and host readback complete', flush=True)
snapshot(status='passed', step='all requested process pairs complete')
print('PASS: all', len(args.cases), 'actual native/HealthKit process pairs; prepared host readbacks precede every resume.', flush=True)
