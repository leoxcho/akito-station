import Foundation
public struct CemuGraphicsPack:Identifiable,Sendable {
 public var id:String;public var title:String;public var presets:[String:[String]]
 public static func discover(base:URL)throws->[CemuGraphicsPack] {
  let root=base.appendingPathComponent("graphicPacks");guard let e=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey],options:.skipsHiddenFiles) else{return []}
  var result:[CemuGraphicsPack]=[]
  for case let file as URL in e {
   if (try file.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true{e.skipDescendants();continue}
   guard file.lastPathComponent=="rules.txt",file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else{continue}
   var section="",block:[String:String]=[:],title=file.deletingLastPathComponent().lastPathComponent,presets:[String:[String]]=[:]
   func finish(){if section=="Definition"{title=block["path"] ?? block["name"] ?? title};if section=="Preset",let name=block["name"]{let category=block["category"] ?? "";if !(presets[category] ?? []).contains(name){presets[category,default:[]].append(name)}};block=[:]}
   for line in try String(contentsOf:file).components(separatedBy:"\n") {
    let line=line.trimmingCharacters(in:.whitespaces)
    if line.hasPrefix("["),line.hasSuffix("]"){finish();section=String(line.dropFirst().dropLast());continue}
    if !line.hasPrefix("#"),let split=line.firstIndex(of:"="){block[line[..<split].trimmingCharacters(in:.whitespaces)]=line[line.index(after:split)...].trimmingCharacters(in:.whitespaces).trimmingCharacters(in:CharacterSet(charactersIn:"\""))}
   }
   finish();result.append(CemuGraphicsPack(id:String(file.path.dropFirst(base.path.count+1)),title:title,presets:presets))
  }
  return result.sorted{$0.title<$1.title}
 }
 public func selection(in text:String)throws->(Bool,[String:String]) {
  let doc=try XMLDocument(xmlString:text,options:[])
  guard let entry=doc.rootElement()?.elements(forName:"GraphicPack").first?.elements(forName:"Entry").first(where:{$0.attribute(forName:"filename")?.stringValue==id}) else{return(false,[:])}
  var values:[String:String]=[:];for p in entry.elements(forName:"Preset"){values[p.elements(forName:"category").first?.stringValue ?? ""]=p.elements(forName:"preset").first?.stringValue ?? ""}
  return(entry.attribute(forName:"disabled")?.stringValue != "true",values)
 }
 public func updating(_ text:String,enabled:Bool,category:String?=nil,preset:String="")throws->String {
  if let category=category,!preset.isEmpty,!(presets[category] ?? []).contains(preset){throw AkitoStationError.message("Unknown graphics-pack preset")}
  let doc=try XMLDocument(xmlString:text,options:.nodePreserveAll);guard let root=doc.rootElement() else{throw AkitoStationError.message("Invalid Cemu settings")}
  let list=root.elements(forName:"GraphicPack").first ?? XMLElement(name:"GraphicPack");if list.parent==nil{root.addChild(list)}
  let entry=list.elements(forName:"Entry").first(where:{$0.attribute(forName:"filename")?.stringValue==id}) ?? XMLElement(name:"Entry")
  if entry.parent==nil{entry.addAttribute(XMLNode.attribute(withName:"filename",stringValue:id) as! XMLNode);list.addChild(entry)}
  entry.removeAttribute(forName:"disabled");if !enabled{entry.addAttribute(XMLNode.attribute(withName:"disabled",stringValue:"true") as! XMLNode)}
  if let category=category {
   for p in entry.elements(forName:"Preset") where (p.elements(forName:"category").first?.stringValue ?? "")==category{p.detach()}
   if !preset.isEmpty{let p=XMLElement(name:"Preset");p.addChild(XMLElement(name:"category",stringValue:category));p.addChild(XMLElement(name:"preset",stringValue:preset));entry.addChild(p)}
  }
  return String(decoding:doc.xmlData(options:.nodePreserveAll),as:UTF8.self)
 }
}
