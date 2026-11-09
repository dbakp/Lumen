"""Compile the actual new native expiry guard in an isolated Swift harness."""
from pathlib import Path
import gzip,hashlib,json,subprocess,tempfile,time
B=Path(__file__).resolve().parent;R=B.parents[2]
p=R/'Lumen/Views/HealthConfirmationLifecycleTrace.swift';raw=p.read_bytes();s=raw.decode()
a=s.index('            if expiryRequested {');z=s.index('            let touchAt',a);guard=s[a:z]
pre='''import Foundation
enum Failure: Error { case invalidRecord }
func accepted(_ closed:[String:Any], _ events:[[String:Any]], expiryRequested:Bool=true) -> Bool {
 do {
'''
post='''  return true
 } catch { return false }
}
let closed: [String:Any] = ["closed":true,"consumed":false,"controlCancelled":true]
let exit: [String:Any] = ["event":"wait-exit","expiryClock":"ContinuousClock","expiryLimitSeconds":90,"expiryElapsedSeconds":Int64(90),"expiryElapsedAttoseconds":Int64(0),"closed":true,"consumed":false,"controlCancelled":true,"taskCancelled":false]
var rows=[[String:Any]]()
func check(_ name:String,_ expected:Bool,_ c:[String:Any],_ e:[[String:Any]], expiry:Bool=true) {
 let result=accepted(c,e,expiryRequested:expiry);precondition(result==expected,name)
 rows.append(["case":name,"accepted":result,"expected":expected])
}
check("real-shaped-90-boundary",true,closed,[exit])
var later=exit;later["expiryElapsedSeconds"]=Int64(91);later["expiryElapsedAttoseconds"]=Int64(999999999999999999)
check("duration-components-boundary",true,closed,[later])
check("missing-exit",false,closed,[])
for (key,value) in [("expiryClock","Date" as Any),("expiryLimitSeconds",89 as Any),("expiryElapsedSeconds",Int64(89) as Any),("expiryElapsedSeconds","90" as Any),("expiryElapsedAttoseconds",Int64(-1) as Any),("expiryElapsedAttoseconds",Int64(1000000000000000000) as Any),("closed",false as Any),("consumed",true as Any),("controlCancelled",false as Any),("taskCancelled",true as Any)] {
 var row=exit;row[key]=value;check("reject-"+key+"-"+String(describing:value),false,closed,[row])
}
for key in exit.keys where key != "event" {
 var row=exit;row.removeValue(forKey:key);check("missing-"+key,false,closed,[row])
}
for key in ["closed","controlCancelled"] { var row=closed;row[key]=false;check("closed-row-"+key,false,row,[exit]) }
check("ordinary-notnow-skips-only-expiry-additional-guard",true,[:],[],expiry:false)
print(String(data:try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]),encoding:.utf8)!)
'''
with tempfile.TemporaryDirectory(prefix='lumen257-expiry-native-guard-') as temp:
 p=Path(temp)/'guard.swift';p.write_text(pre+guard+post);binary=Path(temp)/'guard'
 command=['xcrun','swiftc',str(p),'-o',str(binary)];c=subprocess.run(command,capture_output=True,text=True)
 run=subprocess.run([str(binary)],capture_output=True,text=True) if c.returncode==0 else None
 full={'actualSourceSHA256':hashlib.sha256(raw).hexdigest(),'actualExtractedGuard':guard,'harness':pre+guard+post,'command':command,'compileExit':c.returncode,'stdout':c.stdout,'stderr':c.stderr,'runExit':run.returncode if run else None,'runStdout':run.stdout if run else None,'runStderr':run.stderr if run else None}
 decoded=json.dumps(full).encode();fixture='source257-expiry-guard-controls-r1-fixtures.json.gz';assert not (B/fixture).exists();(B/fixture).write_bytes(gzip.compress(decoded,mtime=0))
 result={'status':'PASS actual extracted native expiry guard' if run and run.returncode==0 else 'FAILED actual native guard controls','fixture':fixture,'decodedBytes':len(decoded),'decodedSHA256':hashlib.sha256(decoded).hexdigest(),'sourceSHA256':full['actualSourceSHA256'],'guardSHA256':hashlib.sha256(guard.encode()).hexdigest(),'compileExit':c.returncode,'runExit':run.returncode if run else None,'cases':json.loads(run.stdout) if run and run.returncode==0 else [],'scope':'Actual additional expiry predicate only, isolated in-memory native types. Synthetic elapsed metadata is not real90second/native UI proof. Ordinary lifecycle outer guard and fresh reads are separate.','checkedAt':time.time()}
 p=B/'source257-expiry-guard-controls-r1.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],len(result['cases']));print(c.stderr);print(run.stderr if run else '')
