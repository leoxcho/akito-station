import Foundation
public enum NativeSettingsImport {
 public static func merge(incoming:String,existing:String,engine:String,format:String)throws->String {
  guard incoming.utf8.count<=4*1024*1024 else{throw AkitoStationError.message("Settings import exceeds 4 MiB")}
  let sections:[String:[String]]=["ppsspp_sdl":["Graphics","Control","SystemParam","DisplayLayout","TouchControls"],"duckstation":["GPU","Display","ControllerPorts","InputSources","Hotkeys","TextureReplacements","PostProcessing","Pad"],"dolphin":["Display","Input","Controls","SDL_Hints","DSP","BluetoothPassthrough","Hardware","Settings","Enhancements","Hacks","GCPad","Wiimote"],"dolphin_app":["Display","Input","Controls","Hardware","Settings","Enhancements","Hacks"],"pcsx2":["EmuCore/GS","InputSources","Hotkeys","Pad","InputProfile"],"armsx2":["EmuCore/GS","InputSources","Hotkeys","Pad","InputProfile"],"rpcs3":["Video","Input/Output"],"lime3ds":["Renderer","Layout","Controls","Shortcuts","MotionTouch"],"azahar":["Renderer","Layout","Controls","Shortcuts","MotionTouch"],"shadps4":["GPU","Vulkan","Input","Bindings"],"xemu":["display","input"],"vita3k":["backend-renderer","resolution-multiplier","v-sync","screen-filter","anisotropic-filtering","keyboard-","controller-"]]
  if format=="xml",engine=="cemu" {
   guard !incoming.contains("<!DOCTYPE"),!incoming.contains("<!ENTITY"),!existing.contains("<!DOCTYPE"),!existing.contains("<!ENTITY") else{throw AkitoStationError.message("Settings XML cannot include external entities")}
   let source=try XMLDocument(xmlString:incoming),destination=try XMLDocument(xmlString:existing.isEmpty ? "<content/>":existing)
   guard let src=source.rootElement(),let dst=destination.rootElement() else{throw AkitoStationError.message("Invalid settings XML")}
   for name in ["Graphic","GraphicPack","Input","fullscreen"]{if let node=src.elements(forName:name).first{for old in dst.elements(forName:name){old.detach()};dst.addChild(node.copy() as! XMLNode)}}
   return String(decoding:destination.xmlData(options:.nodePrettyPrint),as:UTF8.self)
  }
  if format=="json",engine=="ryujinx" {
   let source=try JSONSerialization.jsonObject(with:Data(incoming.utf8)) as? [String:Any] ?? [:]
   var destination=existing.isEmpty ? [:]:try JSONSerialization.jsonObject(with:Data(existing.utf8)) as? [String:Any] ?? [:]
   let keys:Set<String>=["res_scale","res_scale_custom","max_anisotropy","aspect_ratio","anti_aliasing","scaling_filter","enable_vsync","vsync_mode","enable_shader_cache","start_fullscreen","enable_keyboard","enable_mouse","hotkeys","input_config","graphics_backend","preferred_gpu","docked_mode"]
   for (key,value) in source where keys.contains(key){destination[key]=value}
   return String(decoding:try JSONSerialization.data(withJSONObject:destination,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self)
  }
  guard let allowed=sections[engine],["ini","toml","yml","yaml"].contains(format) else{throw AkitoStationError.message("Native settings import does not support this configuration yet. Use the emulator's own settings interface.")}
  let yaml=["yml","yaml"].contains(format)
  let expression=try NSRegularExpression(pattern:yaml ? "(?m)^([^\\s#][^:\\n]*):":"(?m)^\\[([^\\n]+)\\][^\\n]*\\n")
  func blocks(_ text:String)->[(String,String)] {
   let matches=expression.matches(in:text,range:NSRange(text.startIndex...,in:text))
   return matches.enumerated().compactMap{index,match in
    guard let name=Range(match.range(at:1),in:text),let start=Range(match.range,in:text)?.lowerBound else{return nil}
    let end=index+1<matches.count ? Range(matches[index+1].range,in:text)!.lowerBound:text.endIndex
    return(String(text[name]),String(text[start..<end]))
   }
  }
  var destination=blocks(existing)
  for (name,block) in blocks(incoming) where allowed.contains(where:{name==$0 || name.hasPrefix($0+"/") || (($0=="Pad" || $0.hasSuffix("-")) && name.hasPrefix($0))}) {
   if let i=destination.firstIndex(where:{$0.0==name}){destination[i]=(name,block)}else{destination.append((name,block))}
  }
  let prefix=expression.firstMatch(in:existing,range:NSRange(existing.startIndex...,in:existing)).flatMap{Range($0.range,in:existing)}.map{String(existing[..<$0.lowerBound])} ?? existing
  return prefix+destination.map{$0.1.trimmingCharacters(in:.whitespacesAndNewlines)+"\n"}.joined(separator:"\n")
 }
 public static func importFile(_ source:URL,to destination:URL,managedRoot:URL,engine:String)throws {
  let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
  guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 0)<=4*1024*1024 else{throw AkitoStationError.message("Choose a regular configuration file no larger than 4 MiB")}
  guard destination.resolvingSymlinksInPath().path.hasPrefix(managedRoot.resolvingSymlinksInPath().path+"/"),source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else{throw AkitoStationError.message("Settings destination must be managed storage, separate from the original")}
  let incoming=try String(contentsOf:source),existing=(try? String(contentsOf:destination)) ?? ""
  let merged=try merge(incoming:incoming,existing:existing,engine:engine,format:destination.pathExtension)
  try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
  // Recheck after creating parents in case a configured path traverses symlinks.
  guard destination.resolvingSymlinksInPath().path.hasPrefix(managedRoot.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Settings path escapes storage")}
  if FileManager.default.fileExists(atPath:destination.path){try EmulatorSettings.save(merged,to:destination,original:existing)}else{try Data(merged.utf8).write(to:destination,options:.atomic)}
 }
}
