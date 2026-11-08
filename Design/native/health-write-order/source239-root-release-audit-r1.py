"""Root actual Release evidence inspection; no build or device actions."""
import base64,gzip,hashlib,json,shlex,subprocess,time
from pathlib import Path
B=Path(__file__).resolve().parent; REPO=B.parents[2]
sha=lambda data:hashlib.sha256(data).hexdigest()
def load(name):return json.loads((B/name).read_bytes())
def fact(name):
 raw=(B/name).read_bytes();return {'file':str((B/name).relative_to(REPO)),'bytes':len(raw),'sha256':sha(raw)}
out=load('health-current-release-source239-r1-outcome.json');audit=load('health-current-release-source239-r1-audit.json')
settings=load('source239-unsigned-release-r1-settings-audit.json');plan=load('health-current-release-source239-r1-plan.json')
declared=load('health-current-release-source239-r1-predeclared-plan.json')
assert out['buildExitCode']==out['auditExitCode']==0 and audit['status']=='passed'
arrays=['checkedDevelopmentMarkers','debugPositiveControls','negativeMarkersWithoutDebugPositive','verifiedProductionMarkers']
for key in arrays: assert plan[key]==declared[key]==audit[key]
assert list(map(lambda key:len(plan[key]),arrays))==[203,187,16,21]
source=load('durable-source-r239.json');archive=json.loads(gzip.decompress((B/'durable-source-r239.json.gz').read_bytes()));bindings=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(source[group])==set(archive[key])
 for path,wanted in source[group].items():
  raw=(REPO/path).read_bytes();saved=archive[key][path].encode() if key=='files' else base64.b64decode(archive[key][path],validate=True)
  assert raw==saved and len(raw)==wanted['bytes'] and sha(raw)==wanted['sha256'];bindings+=1
log=gzip.decompress((B/out['log']).read_bytes());assert len(log)==out['logBytes'] and sha(log)==out['logSHA256']
lines=[line for line in log.decode().splitlines() if '-module-name Lumen ' in line and 'swiftc' in line]
commands=[]
for line in lines:
 tokens=shlex.split(line)
 assert '-O' in tokens and '-Onone' not in tokens and '-enable-testing' not in tokens
 assert '-profile-generate' in tokens and '-profile-coverage-mapping' in tokens
 assert all(not (token=='-D' and tokens[i+1].split('=')[0]=='DEBUG') and not token.startswith('-DDEBUG') for i,token in enumerate(tokens))
 commands.append({'sha256':sha(line.encode()),'optimization':'-O','DEBUG':False,'enableTesting':False,'coverageFlags':['-profile-generate','-profile-coverage-mapping']})
assert len(commands)==settings['appCompilerInvocations'] and commands
assert settings['selectedSettings']['ENABLE_CODE_COVERAGE']=='YES'
files=gzip.decompress((B/settings['swiftFileList']['retained']).read_bytes());assert sha(files)==settings['swiftFileList']['sha256']
paths=[Path(line) for line in files.decode().splitlines()];assert len(paths)==len(set(paths))
frozen=[];generated=[]
for path in paths:
 if path.is_relative_to(REPO):
  relative=str(path.relative_to(REPO));assert relative in source['files']
  raw=path.read_bytes();wanted=source['files'][relative];assert sha(raw)==wanted['sha256'] and len(raw)==wanted['bytes'];frozen.append(relative)
 else:
  assert path.is_relative_to('/tmp/LumenBatch37Release') and path.name=='GeneratedAssetSymbols.swift' and path.is_file() and not path.is_symlink()
  generated.append({'path':str(path),'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())})
expected={path for path in source['files'] if path.startswith(('Lumen/','Shared/')) and path.endswith('.swift')}
assert set(frozen)==expected and len(generated)==1
binary=Path('/tmp/LumenBatch37Release/Build/Products/Release-iphoneos/Lumen.app/Lumen');raw=binary.read_bytes()
assert len(raw)==audit['executableBytes'] and sha(raw)==audit['executableSHA256']
debug=Path('/tmp/LumenBatch37Simulator/Build/Products/Debug-iphonesimulator/Lumen.app/Lumen').read_bytes()
assert sha(debug)==audit['debugPositiveControlSHA256']
assert all(marker.encode() in debug for marker in plan['debugPositiveControls'])
assert not any(marker.encode() in raw for marker in plan['checkedDevelopmentMarkers'])
assert all(marker.encode() in raw for marker in plan['verifiedProductionMarkers'])
receipt=load('health-target-change-source239-r1-build.json');test=Path(receipt['testBinary']).read_bytes();assert len(test)==receipt['testBinaryBytes'] and sha(test)==receipt['testBinarySHA256']
host=load('durable-source-r240.json');host_archive=json.loads(gzip.decompress((B/'durable-source-r240.json.gz').read_bytes()));host_bindings=0
for group,key in [('files','files'),('fixtureInputs','binaryFiles')]:
 assert set(host[group])==set(host_archive[key])
 for name,wanted in host[group].items():
  current=(REPO/name).read_bytes();saved=host_archive[key][name].encode() if key=='files' else base64.b64decode(host_archive[key][name],validate=True)
  assert current==saved and len(current)==wanted['bytes'] and sha(current)==wanted['sha256'];host_bindings+=1
prior=load('source240-native-exact-github.json');assert prior['commit']=='cbd52dbb075d024b32c82bc62202b1a8b90e71bf' and prior['checkpointPaths']==58 and prior['unionPaths']==1052
loadcommands=subprocess.check_output(['xcrun','otool','-l',str(binary)],text=True);assert 'LC_CODE_SIGNATURE' not in loadcommands
names=['durable-source-r239.json','durable-source-r239.json.gz','health-current-release-source239-r1-predeclared-plan.json','health-current-release-source239-r1-plan.json','health-current-release-source239-r1-outcome.json','health-current-release-source239-r1-audit.json','source239-unsigned-release-r1-build.log.gz','source239-unsigned-release-r1-settings-audit.json',settings['swiftFileList']['retained'],'source239-unsigned-release-r1-planned.py','source239-release-settings-auditor-r1.py']
names += ['durable-source-r240.json','durable-source-r240.json.gz','health-target-change-source239-r1-build.json','health-legacy-target-change-source240-round2-part139-native.json','source240-root-part139-review.json','source240-native-exact-github.json']
result={'hostSource':'durable-source-r240.json','hostBindings':host_bindings,'caseSource':'durable-source-r239.json','currentDebugTestSHA256':sha(test),'priorNativeExactCommit':prior['commit'],'status':'PASS actual optimized instrumented unsigned development Release root audit; independent review pending','sourceBindings':bindings,'releaseBytes':len(raw),'releaseSHA256':sha(raw),'markerCounts':[203,187,16,21],'predeclaredArraysUnchanged':True,'eachAppCompilerCommand':commands,'swiftFileList':{'count':len(paths),'frozen':len(frozen),'generated':generated},'mainExecutableHasLC_CODE_SIGNATURE':False,'scope':'Optimized INSTRUMENTED unsigned development only; no signed distribution, runtime, noninstrumented performance, phone actions or full product acceptance.','provenance':list(map(fact,names)),'checkedAt':time.time()}
target=B/'source239-root-release-audit-r1.json';assert not target.exists();target.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({key:value for key,value in result.items() if key!='provenance'},indent=2))
