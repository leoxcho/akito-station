import Foundation

/// Only settings with a verified mapping into the installed runtime are exposed.
public enum GraphicsConfiguration {
 public static let scalableEngines:Set<String> = ["dolphin", "rpcs3", "armsx2", "pcsx2", "vita3k", "ryujinx"]
 public static func applyPreset(_ name:String, to profile:inout GameProfile) {
  profile.resolutionScale = name == "Quality" ? 3 : name == "Balanced" ? 2 : 1
  profile.vsync = true
  profile.options["arm.graphics.anisotropy"] = name == "Quality" ? "16" : name == "Balanced" ? "4" : "1"
 }
 public static func anisotropy(_ profile:GameProfile)->Int {
  let value=Int(profile.options["arm.graphics.anisotropy"] ?? "1") ?? 1
  return [1,2,4,8,16].contains(value) ? value : 1
 }
 // Replace a scalar within one section, retaining unrelated controller, firmware and game settings.
 public static func setting(_ text:String,section:String?,key:String,value:String,separator:String="=")->String {
  var lines=text.components(separatedBy:"\n")
  var start=0;var end=lines.count
  if let section=section {
   if let i=lines.firstIndex(where:{$0.trimmingCharacters(in:.whitespaces)=="[\(section)]"}) {
    start=i+1;end=lines[start...].firstIndex(where:{$0.trimmingCharacters(in:.whitespaces).hasPrefix("[")}) ?? lines.count
   } else {lines.append("[\(section)]");start=lines.count;end=lines.count}
  }
  let matches=(start..<end).filter { i in
   guard let split=lines[i].range(of:separator) else{return false}
   return lines[i][..<split.lowerBound].trimmingCharacters(in:.whitespaces)==key
  }
  if let first=matches.first {lines[first]="\(key)\(separator)\(value)";for i in matches.dropFirst().reversed(){lines.remove(at:i)}}
  else {lines.insert("\(key)\(separator)\(value)",at:end)}
  return lines.joined(separator:"\n")
 }
 public static func prepare(engine:String,data:URL,profile:GameProfile)throws {
  if EmulatorSettings.native(profile){return}
  guard (1...8).contains(profile.resolutionScale) else {throw AkitoStationError.message("Resolution must be between 1× and 8×")}
  if engine == "cemu" {try prepareCemu(data:data,profile:profile);return}
  let fm=FileManager.default
  let relative:String
  switch engine {case "armsx2","pcsx2":relative="inis/PCSX2.ini";case "vita3k":relative="config.yml";case "ryujinx":relative="Config.json";default:return}
  let file=data.appendingPathComponent(relative)
  guard fm.fileExists(atPath:file.path) else {throw AkitoStationError.message("Import \(engine) settings into Akito Station before configuring graphics.")}
  let original=try Data(contentsOf:file)
  var result:Data
  if engine == "ryujinx" {
   guard var json=try JSONSerialization.jsonObject(with:original) as? [String:Any] else{throw AkitoStationError.message("Invalid Switch settings")}
   json["graphics_backend"]="Vulkan";json["res_scale"]=profile.resolutionScale
   json["max_anisotropy"]=anisotropy(profile);json["enable_vsync"]=profile.vsync
   json["enable_shader_cache"]=true
   result=try JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys])
  } else {
   guard var text=String(data:original,encoding:.utf8) else{throw AkitoStationError.message("Invalid runtime settings encoding")}
   if engine == "armsx2" || engine == "pcsx2" {
    for (key,value) in [("Renderer","17"),("upscale_multiplier",String(profile.resolutionScale)),("VsyncEnable",String(profile.vsync)),("MaxAnisotropy",String(anisotropy(profile)))] {
     text=setting(text,section:"EmuCore/GS",key:key,value:value)
    }
   } else {
    // A previous import appended keys after YAML's end-of-document marker.
    text=text.components(separatedBy:"\n").filter{$0.trimmingCharacters(in:.whitespaces) != "..."}.joined(separator:"\n")
    for (key,value) in [("backend-renderer","Vulkan"),("resolution-multiplier",String(profile.resolutionScale)),("v-sync",String(profile.vsync)),("anisotropic-filtering",String(anisotropy(profile)))] {
     text=setting(text,section:nil,key:key,value:" "+value,separator:":")
    }
   }
   result=Data(text.utf8)
  }
  let backup=file.appendingPathExtension("before-arm-graphics")
  if !fm.fileExists(atPath:backup.path){try original.write(to:backup,options:.atomic)}
  try result.write(to:file,options:.atomic)
 }
 public static func prepareCemu(data:URL,profile:GameProfile)throws {
  let file=data.appendingPathComponent("home/Library/Application Support/Cemu/settings.xml")
  let original=try Data(contentsOf:file)
  let document=try XMLDocument(data:original,options:.nodePreserveAll)
  guard let root=document.rootElement(),root.name == "content" else {throw AkitoStationError.message("Invalid Cemu settings document")}
  let graphics: XMLElement
  if let existing=root.elements(forName:"Graphic").first {graphics=existing}
  else {graphics=XMLElement(name:"Graphic");root.addChild(graphics)}
  let filter=profile.options["arm.cemu.filter"] ?? "1"
  guard ["0","1","2","3"].contains(filter) else {throw AkitoStationError.message("Unsupported Wii U scaling filter")}
  for (key,value) in [("api","1"),("VSync",profile.vsync ? "1":"0"),("UpscaleFilter",filter),("FullscreenScaling",profile.aspect == "Stretch" ? "1":"0"),("AsyncCompile",profile.options["arm.cemu.async"] ?? "true")] {
   if let element=graphics.elements(forName:key).first {element.stringValue=value}
   else {graphics.addChild(XMLElement(name:key,stringValue:value))}
  }
  let backup=file.appendingPathExtension("before-arm-graphics")
  if !FileManager.default.fileExists(atPath:backup.path){try original.write(to:backup,options:.atomic)}
  try document.xmlData(options:.nodePrettyPrint).write(to:file,options:.atomic)
 }

}
