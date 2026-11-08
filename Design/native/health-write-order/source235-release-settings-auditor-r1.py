"""Query selected current Release settings after its actual build; no device actions."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import time

repo = Path('/Users/davidbakposada/Documents/ChatGPT/Lumen')
base = repo / 'Design/native/health-write-order'
raw = Path('/tmp/LumenBatch44Checks')
build = json.loads((base / 'health-current-release-source235-r1-outcome.json').read_bytes())
plan = json.loads((base / 'health-current-release-source235-r1-plan.json').read_bytes())
assert build['buildExitCode'] == 0 and build['command'][-1] == 'build'
command = build['command'][:-1] + ['-showBuildSettings', '-json']
stdout = raw / 'Source235UnsignedReleaseR1Settings.json'
stderr = raw / 'Source235UnsignedReleaseR1Settings.log'
sha = lambda data: hashlib.sha256(data).hexdigest()
assert not stdout.exists() and not stderr.exists(), 'Never restart this actual query'
with stdout.open('xb') as out, stderr.open('xb') as err:
    process = subprocess.Popen(command, cwd=repo, stdout=out, stderr=err)
    query_pid = process.pid
    code = process.wait()
data = stdout.read_bytes()
if code != 0:
    failure = {'status': 'FAILED actual current235 settings query', 'source': 'durable-source-r235.json',
        'queryPID': query_pid, 'queryExitCode': code, 'command': command,
        'stdoutBytes': len(data), 'stdoutSHA256': sha(data),
        'stderrBytes': stderr.stat().st_size, 'stderrSHA256': sha(stderr.read_bytes())}
    (base / 'source235-release-settings-r1-failure.json').write_text(json.dumps(failure, indent=2) + '\n')
    raise RuntimeError('Current settings acquisition failed; actual outcome retained')
settings = json.loads(data)
matches = [row for row in settings if row['buildSettings'].get('PRODUCT_BUNDLE_IDENTIFIER') == 'com.dbakp.lumen']
assert len(matches) == 1
app = matches[0]['buildSettings']
assert app['CONFIGURATION'] == 'Release' and app['PLATFORM_NAME'] == 'iphoneos'
assert app['CODE_SIGNING_ALLOWED'] == 'NO'
# Xcode omitted this setting: actual compiler flags below supply the evidence.
debug = re.compile(r'(?:^|\s)(?:-D\s*)?DEBUG(?:=\S+)?(?:\s|$)')
for key in ['SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'OTHER_SWIFT_FLAGS', 'GCC_PREPROCESSOR_DEFINITIONS']:
    assert not debug.search(app.get(key, '')), (key, app.get(key))
keys = ['CONFIGURATION', 'PLATFORM_NAME', 'SDKROOT', 'ARCHS', 'PRODUCT_BUNDLE_IDENTIFIER',
        'CODE_SIGNING_ALLOWED', 'SWIFT_VERSION', 'SWIFT_OPTIMIZATION_LEVEL',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'OTHER_SWIFT_FLAGS', 'GCC_PREPROCESSOR_DEFINITIONS',
        'SWIFT_COMPILATION_MODE', 'ENABLE_TESTABILITY', 'IPHONEOS_DEPLOYMENT_TARGET',
        'CLANG_ENABLE_CODE_COVERAGE', 'GCC_GENERATE_TEST_COVERAGE_FILES', 'ENABLE_CODE_COVERAGE']
log = gzip.decompress((base / build['log']).read_bytes())
assert sha(log) == build['logSHA256'] and b'** BUILD SUCCEEDED **' in log
invocations = [line for line in log.decode(errors='replace').splitlines()
               if '-module-name Lumen ' in line and 'swiftc' in line]
assert invocations
optimization_flags = []
for line in invocations:
    tokens = [token for token in shlex.split(line) if token != '-Xcc']
    options = [token for token in tokens if token in ['-O', '-Osize', '-Onone', '-Ounchecked']]
    assert options and all(token in plan['buildSettingsRequirements']['SwiftOptimizationAllowed'] for token in options)
    optimization_flags.append(options)
    assert '-enable-testing' not in tokens
    for index, token in enumerate(tokens):
        if token == '-D':
            assert index + 1 < len(tokens) and tokens[index + 1].split('=')[0] != 'DEBUG'
        elif token.startswith('-D'):
            assert token[2:].split('=')[0] != 'DEBUG'
    assert all(token.endswith('.SwiftFileList') for token in tokens if token.startswith('@'))
filelists = set(re.findall(r'@([^\s]+\.SwiftFileList)', '\n'.join(invocations)))
assert len(filelists) == 1
filelist = Path(next(iter(filelists)))
assert filelist.is_relative_to('/tmp/LumenBatch37Release') and not filelist.is_symlink()
files = filelist.read_bytes()
for name in ['Lumen/Persistence/LocalStore.swift', 'Lumen/Models/HealthRecoverySelection.swift']:
    assert str(repo / name).encode() in files, name
assert not re.search(rb' 2\.[^/\n]+', files)
archive_name = 'source235-unsigned-release-r1-swift-filelist.txt.gz'
(base / archive_name).write_bytes(gzip.compress(files, mtime=0))
result = {
    'status': 'PASS selected actual Release settings and app compiler invocation checks',
    'source': 'durable-source-r235.json', 'queryPID': query_pid, 'queryExitCode': code,
    'command': command, 'target': matches[0]['target'], 'actualSettingTargetCount': len(settings),
    'selectedSettings': {key: app.get(key) for key in keys},
    'rawSettingsBytes': len(data), 'rawSettingsSHA256': sha(data), 'rawSettingsPath': str(stdout),
    'stderrBytes': stderr.stat().st_size, 'stderrSHA256': sha(stderr.read_bytes()),
    'appCompilerInvocations': len(invocations), 'appCompilerDefinesDEBUG': False,
    'actualCompilerOptimizationFlags': optimization_flags, 'appCompilerEnableTesting': False,
    'oneActualCurrentQuery': True,
    'missingSettingsAreNotNegativeFlagProof': [key for key in keys if app.get(key) is None],
    'appCompilerCoverageFlags': [flag for flag in ['-profile-generate', '-profile-coverage-mapping']
                                 if any(flag in line for line in invocations)],
    'swiftFileList': {'retained': archive_name, 'originalPath': str(filelist),
                      'bytes': len(files), 'sha256': sha(files), 'changedCallerAndPayloadListed': True},
    'buildLogSHA256': sha(log), 'planSHA256': sha((base / 'health-current-release-source235-r1-plan.json').read_bytes()),
    'auditorSHA256': sha(Path(__file__).read_bytes()), 'checkedAt': time.time(),
    'scope': 'Selected actual app settings/three parsed compiler invocations only; omitted settings are not no-DEBUG evidence. Fresh235 actual settings acquired once; inherited missing-field correction retains actual compiler flags as evidence. Coverage instrumentation is reported separately; no distribution/performance/noninstrumented/runtime acceptance. Unselected raw settings are not published; raw acquisition retained through review and exact compact backup.'
}
(base / 'source235-unsigned-release-r1-settings-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
