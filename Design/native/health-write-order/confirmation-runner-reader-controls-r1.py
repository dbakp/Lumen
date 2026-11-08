"""Compile/run the actual extracted UITest relay reader on isolated real files."""
from pathlib import Path
import gzip,hashlib,json,subprocess,tempfile,time
B=Path(__file__).resolve().parent;R=B.parents[2];original=(R/'LumenUITests/LumenSmokeTests.swift').read_text();start=original.index('                func observeRelay(');end=original.index('                var gate: [String:String]?',start);reader=original[start:end]
pre='''import Foundation
import CryptoKit
import Darwin
let root=URL(fileURLWithPath:CommandLine.arguments[1]);let relayURL=root.appendingPathComponent("relay.json")
let run=UUID(uuidString:"C7ED94D3-DDC6-45DD-ACC9-EC583731AEC7")!
var observations:[[String:Any]]=[];var lastRelayObservation=""
'''
post='''
let u=run.uuidString,v="ED54372B-AF7D-4972-A183-EDA40AD6C4EB"
let armed:[String:String] = ["runID":u,"pid":"123","sessionID":v,"captureID":u,"nonce":v,"appearanceID":u,"domains":"meals","legacyDomains":"meals","omitPhotos":"false","phase":"armed","targetPhase":"host-ready"]
var mutated=armed;mutated["phase"]="mutated";mutated["targetPhase"]="host-target-changed";mutated["nativeCheckpointSHA256"]=String(repeating:"a",count:64)
var cases:[[String:Any]]=[]
func check(_ name:String,_ wanted:Bool,_ value:[String:Any]?=nil,_ raw:Data?=nil,_ phase:String="armed",_ previous:[String:String]?=nil,_ special:String?=nil) throws {
 try? FileManager.default.removeItem(at:relayURL);observations=[];lastRelayObservation=""
 if let special {
  let target=root.appendingPathComponent("target");try? FileManager.default.removeItem(at:target);try Data("target".utf8).write(to:target)
  if special=="symlink" { try FileManager.default.createSymbolicLink(at:relayURL,withDestinationURL:target) }
  if special=="hardlink" { precondition(Darwin.link(target.path,relayURL.path)==0) }
  if special=="fifo" { precondition(mkfifo(relayURL.path,0o600)==0) }
  if special=="directory" { try FileManager.default.createDirectory(at:relayURL,withIntermediateDirectories:false) }
 } else if let raw { try raw.write(to:relayURL) }
 else if let value { try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]).write(to:relayURL) }
 let observed=observeRelay(phase,previous:previous)
 precondition((observed != nil)==wanted,name)
 precondition(!observations.isEmpty,name+" observation missing")
 cases.append(["name":name,"accepted":observed != nil,"expected":wanted,"observations":observations])
}
try check("missing",false)
try check("exact armed",true,armed)
for (key,value) in [("runID",v),("nonce","bad"),("appearanceID",""),("pid","0123"),("pid","0"),("pid"," 123"),("domains","workouts"),("legacyDomains",""),("omitPhotos","true"),("phase","mutated"),("targetPhase","ready"),("nativeCheckpointSHA256",String(repeating:"a",count:64)),("unexpected","value")] {
 var changed=armed;changed[key]=value;try check("armed reject "+key+value,false,changed)
}
var missing=armed;missing.removeValue(forKey:"appearanceID");try check("missing field",false,missing)
try check("exact mutated same gate",true,mutated,nil,"mutated",armed)
for (key,value) in [("nonce",u),("captureID",v),("nativeCheckpointSHA256",String(repeating:"a",count:63)),("nativeCheckpointSHA256",String(repeating:"A",count:64))] {
 var changed=mutated;changed[key]=value;try check("mutated reject "+key+value,false,changed,nil,"mutated",armed)
}
var noCheckpoint=mutated;noCheckpoint.removeValue(forKey:"nativeCheckpointSHA256");try check("missing native checkpoint",false,noCheckpoint,nil,"mutated",armed)
var typed:[String:Any]=armed;typed["omitPhotos"]=false;try check("nonstring value",false,typed)
for (name,bytes) in [("invalidUTF8",Data([255])),("malformedJSON",Data("{".utf8)),("nonobjectJSON",Data("[]".utf8)),("empty",Data()),("oversized",Data(repeating:120,count:4097))] { try check(name,false,nil,bytes) }
for name in ["symlink","fifo","directory","hardlink"] { try check(name,false,nil,nil,"armed",nil,name) }
print(String(data:try JSONSerialization.data(withJSONObject:["cases":cases],options:[.sortedKeys]),encoding:.utf8)!)
'''
source=pre+reader+post
with tempfile.TemporaryDirectory(prefix='lumen248-actual-relay-reader-') as folder:
 root=Path(folder);swift=root/'Reader.swift';swift.write_text(source);binary=root/'Reader';fixtures=root/'fixtures';fixtures.mkdir();command=['xcrun','swiftc','-swift-version','5','-module-cache-path',str(root/'module-cache'),str(swift),'-o',str(binary)];compile=subprocess.run(command,capture_output=True);run=subprocess.run([str(binary),str(fixtures)],capture_output=True) if compile.returncode==0 else None
 full={'actualReader':reader,'fullSource':source,'command':command,'compileExit':compile.returncode,'compileStdout':compile.stdout.decode(),'compileStderr':compile.stderr.decode(),'runExit':run.returncode if run else None,'runStdout':run.stdout.decode() if run else None,'runStderr':run.stderr.decode() if run else None,'binaryBytes':binary.stat().st_size if binary.exists() else None,'binarySHA256':hashlib.sha256(binary.read_bytes()).hexdigest() if binary.exists() else None}
 encoded=json.dumps(full).encode();(B/'source248-actual-relay-reader-controls-r1-fixtures.json.gz').write_bytes(gzip.compress(encoded,mtime=0));passed=compile.returncode==0 and run is not None and run.returncode==0;cases=json.loads(run.stdout)['cases'] if passed else []
 out={'status':'PASS actual extracted Swift reader/current predicate on real isolated files' if passed else 'FAILED actual Swift reader preparation','actualUITestSHA256':hashlib.sha256(original.encode()).hexdigest(),'readerSHA256':hashlib.sha256(reader.encode()).hexdigest(),'compileExit':compile.returncode,'runExit':run.returncode if run else None,'cases':[{k:r[k] for k in ['name','accepted','expected']} for r in cases],'count':len(cases),'decodedBytes':len(encoded),'decodedSHA256':hashlib.sha256(encoded).hexdigest(),'scope':'Actual extracted reader with real Foundation/CryptoKit/Darwin/JSON/files; no real runner path/NSPredicate alert/hostprotocol/native/cancellation acceptance. Full input/outputs archived; known temporary binary/cache removed after run, no manual storage credit.','checkedAt':time.time()};(B/'source248-actual-relay-reader-controls-r1.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'status':out['status'],'count':len(cases),'compileStderr':compile.stderr.decode()[:2000],'runStderr':run.stderr.decode()[:1000] if run else None}));assert passed
