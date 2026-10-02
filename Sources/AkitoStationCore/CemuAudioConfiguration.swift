import Foundation

public enum CemuAudioConfiguration {
 public static func prepare(data:URL,profile:GameProfile)throws {
  guard profile.options["arm.cemu.audio.native"] != "true" else{return}
  let file=data.appendingPathComponent("home/Library/Application Support/Cemu/settings.xml")
  let fm=FileManager.default
  let original=fm.fileExists(atPath:file.path) ? try Data(contentsOf:file):Data("<content/>".utf8)
  let document=try XMLDocument(data:original,options:.nodePreserveAll)
  guard let root=document.rootElement(),root.name=="content" else{throw AkitoStationError.message("Invalid Cemu settings document")}
  let audio=root.elements(forName:"Audio").first ?? XMLElement(name:"Audio")
  if audio.parent==nil{root.addChild(audio)}
  let volume=String(Int((min(1,max(0,profile.volume.isFinite ? profile.volume:0.8))*100).rounded()))
  // Cemu's Cubeb backend uses 'default' for the current macOS output; an empty device disables audio.
  for (key,value) in [("api","3"),("TVDevice","default"),("PadDevice","default"),("TVChannels","1"),("PadChannels","1"),("TVVolume",volume),("PadVolume",volume)] {
   let nodes=audio.elements(forName:key)
   if let node=nodes.first{node.stringValue=value;for duplicate in nodes.dropFirst(){duplicate.detach()}}
   else{audio.addChild(XMLElement(name:key,stringValue:value))}
  }
  try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
  let backup=file.appendingPathExtension("before-akito-audio")
  if fm.fileExists(atPath:file.path),!fm.fileExists(atPath:backup.path){try original.write(to:backup,options:.atomic)}
  try document.xmlData(options:.nodePrettyPrint).write(to:file,options:.atomic)
 }
}
