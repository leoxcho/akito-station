import Foundation
import CoreFoundation

public struct SettingsField:Identifiable {
 public var id:String;public var section:String;public var key:String;public var value:String;public var kind:String;public var help:String=""
 public var isBoolean:Bool{kind=="boolean" || ["true","false"].contains(value.lowercased())}
}
public struct NativeSettingsDocument {
 public let text:String;public let format:String;public let fields:[SettingsField]
 public init(text:String,format:String)throws {
  self.text=text;self.format=format
  if format=="json" {
   let root=try JSONSerialization.jsonObject(with:Data(text.utf8),options:.fragmentsAllowed)
   var rows:[SettingsField]=[]
   func walk(_ object:Any,_ path:[String],_ names:[String]) {
    if let d=object as? [String:Any]{for key in d.keys.sorted(){walk(d[key]!,path+["k"+key],names+[key])}}
    else if let a=object as? [Any]{for (i,v) in a.enumerated(){walk(v,path+["i"+String(i)],names+[String(i+1)])}}
    else if !(object is NSNull) {
     let kind:String,value:String
     if let n=object as? NSNumber{kind=CFGetTypeID(n)==CFBooleanGetTypeID() ? "boolean":"number";value=kind=="boolean" ? (n.boolValue ? "true":"false"):n.stringValue}
     else{kind="string";value=String(describing:object)}
     let id=String(data:try! JSONEncoder().encode(path),encoding:.utf8)!
     rows.append(SettingsField(id:id,section:names.dropLast().joined(separator:" / "),key:names.last ?? "Value",value:value,kind:kind))
    }
   }
   walk(root,[],[]);fields=rows
  }else if format=="xml" {
   let doc=try XMLDocument(xmlString:text,options:.nodePreserveAll);var rows:[SettingsField]=[]
   func walk(_ element:XMLElement,_ path:String,_ names:[String]) {
    for attribute in element.attributes ?? [] {if let name=attribute.name{rows.append(SettingsField(id:path+"/@"+name,section:names.joined(separator:" / "),key:name,value:attribute.stringValue ?? "",kind:"string"))}}
    let children=(element.children ?? []).compactMap{$0 as? XMLElement}
    if children.isEmpty{rows.append(SettingsField(id:path,section:names.dropLast().joined(separator:" / "),key:names.last ?? "Value",value:element.stringValue ?? "",kind:"string"))}
    else{for (i,c) in children.enumerated(){walk(c,path+"/*[\(i+1)]",names+[c.name ?? "Value"])}}
   }
   if let root=doc.rootElement(){walk(root,"/*",[root.name ?? "Settings"])};fields=rows
  }else{
   fields=NativeSetting.rows(text,format:format).map{SettingsField(id:String($0.id),section:$0.section,key:$0.key,value:$0.value,kind:"literal",help:$0.suffix.trimmingCharacters(in:.whitespaces))}
  }
 }
 public func applying(_ edits:[String:String])throws->String {
  let changed=fields.filter{edits[$0.id] != nil && edits[$0.id] != $0.value}
  guard !changed.isEmpty else{return text}
  if format=="json" {
   var object=try JSONSerialization.jsonObject(with:Data(text.utf8),options:.fragmentsAllowed)
   func replacing(_ node:Any,_ path:ArraySlice<String>,_ value:Any)throws->Any {
    guard let part=path.first else{return value}
    if part.hasPrefix("k"),var d=node as? [String:Any],let old=d[String(part.dropFirst())]{d[String(part.dropFirst())]=try replacing(old,path.dropFirst(),value);return d}
    if part.hasPrefix("i"),let i=Int(part.dropFirst()),var a=node as? [Any],a.indices.contains(i){a[i]=try replacing(a[i],path.dropFirst(),value);return a}
    throw AkitoStationError.message("Settings structure changed; reload the document")
   }
   for f in changed {
    let value=edits[f.id]!,typed:Any
    if f.kind=="boolean"{guard ["true","false"].contains(value) else{throw AkitoStationError.message("\(f.key) requires true or false")};typed=value=="true"}
    else if f.kind=="number"{guard let number=try? JSONSerialization.jsonObject(with:Data(value.utf8),options:.fragmentsAllowed) as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID() else{throw AkitoStationError.message("\(f.key) requires a number")};typed=number}
    else{typed=value}
    let path=try JSONDecoder().decode([String].self,from:Data(f.id.utf8));object=try replacing(object,path[...],typed)
   }
   return String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys,.fragmentsAllowed]),as:UTF8.self)
  }
  if format=="xml" {
   let doc=try XMLDocument(xmlString:text,options:.nodePreserveAll)
   for f in changed{guard let node=try doc.nodes(forXPath:f.id).first else{throw AkitoStationError.message("Settings structure changed")};node.stringValue=edits[f.id]!}
   return String(decoding:doc.xmlData(options:.nodePreserveAll),as:UTF8.self)
  }
  let rows=NativeSetting.rows(text,format:format);var result=text
  for f in changed {
   let value=edits[f.id]!
   guard !value.contains("\n"),!value.contains("\r") else{throw AkitoStationError.message("\(f.key) must stay on one line")}
   if let row=rows.first(where:{String($0.id)==f.id}){result=row.replacing(in:result,with:value)
    if let marker=rows.first(where:{$0.section==row.section && $0.key==row.key+"\\default"}){result=marker.replacing(in:result,with:"false")}}
  }
  return result
 }
}
