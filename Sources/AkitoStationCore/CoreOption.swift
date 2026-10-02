import Foundation
public struct CoreOption:Codable,Identifiable {
 public var key:String;public var title:String;public var values:[String]
 public var id:String{key}
 public init?(key:String,definition:String){
  guard let split=definition.firstIndex(of:";") else{return nil}
  self.key=key;title=String(definition[..<split]);values=definition[definition.index(after:split)...].trimmingCharacters(in:.whitespaces).components(separatedBy:"|")
  guard !values.isEmpty else{return nil}
 }
}
