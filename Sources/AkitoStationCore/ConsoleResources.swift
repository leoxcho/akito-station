import Foundation

public enum ConsoleResources {
 public struct Entry:Codable,Identifiable,Sendable {
  public let id:String
  public let filename:String
  public let sha256:String
  public let bytes:Int
  public let imported:Date
  public let installationRequired:Bool
 }
 public static func guidance(_ platform:Platform)->String {
  switch platform {
  case .ps1:return "Import your PlayStation BIOS dump (.bin). Region and checksum compatibility are checked by the selected PS1 engine."
  case .ps2:return "Import your PS2 BIOS dump and any accompanying NVM/MEC files. The PS2 engine must select and validate the BIOS before boot."
  case .ps3:return "Import your PS3 firmware update (.PUP). This package must then be installed by the PS3 runtime; copying the update is not installation."
  case .psvita:return "Import your Vita system firmware and font packages (.PUP). Both require installation by the Vita runtime."
  case .switchConsole:return "Import your own prod.keys/title.keys and firmware archive. Firmware requires installation by the Switch runtime. Keys are stored locally and are never shown in diagnostics."
  case .ps4:return "Import your own required PS4 system resources or firmware package. Requirements depend on the selected PS4 runtime. Firmware packages require an installer."
  case .n3ds:return "Import your own AES key file, seed database or other required 3DS system data. The 3DS runtime must validate the files."
  case .wiiu:return "Import your own keys.txt and Wii U system resources required by your games. Cemu must validate imported resources."
  case .nds:return "Import bios7.bin, bios9.bin and firmware.bin from your Nintendo DS."
  case .gba:return "Optional: import gba_bios.bin from your Game Boy Advance."
  case .gb,.gbc:return "Optional: import your own boot ROM (gb_bios.bin or gbc_bios.bin)."
  case .nes:return "Famicom Disk System games require your disksys.rom BIOS dump. Cartridge games generally do not."
  case .pce:return "CD games require your own system-card BIOS. HuCard games do not."
  case .gc,.wii:return "Import your own IPL, NAND or other system resources if required. NAND archives need runtime installation."
  case .dreamcast,.saturn,.xbox,.xbox360:return "Import your console's required BIOS, firmware or system-data dumps. Runtime validation is required before boot."
  default:return "Import optional system resources if required by the engine or game. Akito Station does not download proprietary BIOS, firmware or keys."
  }
 }
 public static func directory(root:URL,platform:Platform)throws->URL {
  let folder=root.appendingPathComponent("SystemImports/"+platform.rawValue)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  return folder
 }
 public static func entries(root:URL,platform:Platform)throws->[Entry] {
  let folder=try directory(root:root,platform:platform)
  return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:.skipsHiddenFiles).filter{$0.pathExtension=="json"}.map{try JSONStore.read(Entry.self,from:$0)}.sorted{$0.imported>$1.imported}
 }
 /// Imports into managed storage only. Engine activation/installation is a separate operation.
 public static func importFile(_ source:URL,root:URL,platform:Platform)throws->Entry {
  let fm=FileManager.default
  let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
  guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 0)>0 else {throw AkitoStationError.message("Choose a nonempty BIOS, firmware, key or system-data file, not a folder or symbolic link.")}
  let extensions:Set<String>=["bin","ic1","rom","bios","pup","zip","7z","keys","txt","dat","db","nvm","mec","nand","img","sprx","rpx","tik","tmd","cert","app"]
  guard extensions.contains(source.pathExtension.lowercased()) else {throw AkitoStationError.message("Unsupported system-resource file type.")}
  let folder=try directory(root:root,platform:platform),id=UUID().uuidString
  let transaction=folder.appendingPathComponent(".import-"+id),destination=folder.appendingPathComponent(id)
  try fm.createDirectory(at:transaction,withIntermediateDirectories:false)
  do {
   let copied=transaction.appendingPathComponent(source.lastPathComponent)
   try fm.copyItem(at:source,to:copied)
   let checksum=try digest(source)
   guard try digest(copied)==checksum else{throw AkitoStationError.message("Imported resource failed copy verification")}
   try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:copied.path)
   let entry=Entry(id:id,filename:source.lastPathComponent,sha256:checksum,bytes:values.fileSize ?? 0,imported:Date(),installationRequired:["pup","zip","7z","nand"].contains(source.pathExtension.lowercased()))
   try fm.moveItem(at:transaction,to:destination)
   do {try JSONStore.write(entry,to:folder.appendingPathComponent(id+".json"))}
   catch {try? fm.removeItem(at:destination);throw error}
   return entry
  } catch {try? fm.removeItem(at:transaction);throw error}
 }
}
