import Foundation
import CoreML
@main struct Inspect {
 static func main() throws {
  let config=MLModelConfiguration();config.computeUnits = .cpuOnly
  let model=try MLModel(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]),configuration:config)
  func array(_ values:[Int32])throws->MLMultiArray {
   let a=try MLMultiArray(shape:[1,256],dataType:.int32)
   for (i,v) in values.enumerated(){a[i]=NSNumber(value:v)};return a
  }
  let features=try MLDictionaryFeatureProvider(dictionary:["input_ids":array([101,2023,2003,1037,3231,102]+Array(repeating:0,count:250)),"attention_mask":array(Array(repeating:1,count:6)+Array(repeating:0,count:250)),"token_type_ids":array(Array(repeating:0,count:256))])
  let p=try model.prediction(from:features),v=p.featureValue(for:"div_1")!.multiArrayValue!
  let values=(0..<v.count).map{v[$0].doubleValue},finite=values.filter(\.isFinite)
  let report:[String:Any]=["shape":v.shape.map(\.intValue),"count":values.count,"finiteCount":finite.count,"nanCount":values.filter(\.isNaN).count,"infiniteCount":values.filter{ $0.isInfinite }.count,"normFromFiniteValues":sqrt(finite.reduce(0){$0+$1*$1}),"scope":"Direct synthetic-token output inspection; does not weaken production encoder guards"]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
 }
}
