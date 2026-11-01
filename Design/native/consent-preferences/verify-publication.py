import pathlib,subprocess,json,hashlib,datetime,sys
root=pathlib.Path('/Users/davidbakposada/Documents/ChatGPT/Lumen')
evidence=root/'Design/native/consent-preferences'
def run(*args): return subprocess.check_output(args,cwd=root)
def api(path): return json.loads(run('gh','api',path))
head=run('git','rev-parse','HEAD').decode().strip()
assert len(sys.argv)==2 and sys.argv[1]==head, 'Pass the exact published HEAD explicitly'
assert not run('git','status','--porcelain').strip(), 'Publish/read back a clean coherent commit first'
reference=api('repos/dbakp/Lumen/git/ref/heads/main')
assert reference['object']['sha']==head, 'GitHub main does not match the intended commit'
commit=api('repos/dbakp/Lumen/git/commits/'+head)
tree_id=run('git','rev-parse','HEAD^{tree}').decode().strip()
assert commit['tree']['sha']==tree_id
remote=api('repos/dbakp/Lumen/git/trees/'+tree_id+'?recursive=1')
assert not remote.get('truncated',False)
remote_files={entry['path']:entry for entry in remote['tree'] if entry['type']=='blob'}
needed=set()
for name in ['application-source-r14.json','logic-source-r3.json','source-r23.json']:
 source=json.loads((evidence/name).read_text())
 for path,digest in source.items():
  assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest, path
 needed.update(source)
needed.update(str(p.relative_to(root)) for p in evidence.rglob('*') if p.is_file())
needed.update(['README.md','AGENTS.md','Design/DIRECTION.md','docs/PREFERENCE_SAVES.md','docs/CONTINUE_ON_NEW_COMPUTER.md','docs/ROADMAP.md','docs/VERIFICATION.md'])
rows=[]
for path in sorted(needed):
 file=root/path
 assert file.is_file() and not file.is_symlink(), path
 data=file.read_bytes(); blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
 assert path in remote_files and remote_files[path]['sha']==blob, path
 rows.append({'path':path,'gitBlobSHA1':blob,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
assert api('repos/dbakp/Lumen/git/ref/heads/main')['object']['sha']==head
out={'verifiedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'commit':head,'tree':tree_id,'githubMainMatches':True,'githubTreeMatches':True,'checkedFiles':len(rows),'method':'Fresh authenticated GitHub REST ref/commit/recursive-tree read-back; each needed working file is SHA256-hashed and its Git blob SHA1 equals the remote tree entry. No remote file body download or raw-result retention claim.','files':rows,'scope':'Required current source/resources, useful native originals, compact outcomes/failure history, supplied-policy documentation and provenance before scoped deletion'}
(evidence/'publication-readback.json').write_text(json.dumps(out,indent=2)+'\n')
print('Verified GitHub main/tree and',len(rows),'source/evidence blob identities for',head)
