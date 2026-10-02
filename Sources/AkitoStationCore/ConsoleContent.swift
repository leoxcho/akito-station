import Foundation

public struct ConsolePackage:Codable,Sendable {
 public let platform:Platform
 public let contentID:String
 public var titleID:String {String(contentID.dropFirst(7).prefix(9))}
 public let bytes:UInt64
 public static func inspect(_ file:URL)throws->ConsolePackage {
  let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
  guard values.isRegularFile==true,values.isSymbolicLink != true,file.pathExtension.lowercased()=="pkg",!file.lastPathComponent.hasPrefix("._") else{throw AkitoStationError.message("Choose a console PKG file, not a folder, shortcut or AppleDouble file.")}
  let handle=try FileHandle(forReadingFrom:file);defer{try? handle.close()}
  let header=try handle.read(upToCount:256) ?? Data()
  guard header.count>=192 else{throw AkitoStationError.message("Package header is incomplete.")}
  let size=UInt64(values.fileSize ?? 0)
  if header.prefix(4)==Data([0x7f,0x43,0x4e,0x54]){return ConsolePackage(platform:.ps4,contentID:"",bytes:size)}
  guard header.prefix(4)==Data([0x7f,0x50,0x4b,0x47]) else{throw AkitoStationError.message("This is not a recognized PlayStation console package.")}
  func number(_ offset:Int,_ length:Int)->UInt64{header[offset..<offset+length].reduce(0){($0<<8)|UInt64($1)}}
  let total=number(24,8),dataOffset=number(32,8),dataSize=number(40,8)
  guard total<=size,total>=192,dataOffset<=total,dataSize<=total-dataOffset else{throw AkitoStationError.message("Package is truncated or has invalid data ranges.")}
  let content=String(decoding:header[48..<96].prefix(while:{$0 != 0}),as:UTF8.self)
  guard ConsoleContent.validContentID(content) else{throw AkitoStationError.message("Package has an invalid content ID.")}
  var offset=number(8,4);let count=number(12,4)
  guard count<=4096 else{throw AkitoStationError.message("Package metadata is invalid.")}
  var contentType:UInt64?
  for _ in 0..<count {
   guard offset<=total,total-offset>=8 else{throw AkitoStationError.message("Package metadata is truncated.")}
   try handle.seek(toOffset:offset);let record=try handle.read(upToCount:12) ?? Data()
   guard record.count>=8 else{throw AkitoStationError.message("Package metadata is truncated.")}
   let kind=record.prefix(4).reduce(UInt64(0)){($0<<8)|UInt64($1)},length=record[4..<8].reduce(UInt64(0)){($0<<8)|UInt64($1)}
   guard length<=total-offset-8 else{throw AkitoStationError.message("Package metadata range is invalid.")}
   if kind==2, length>=4,record.count==12{contentType=record[8..<12].reduce(0){($0<<8)|UInt64($1)}}
   offset += 8+length
  }
  let family=number(6,2),vitaTypes:Set<UInt64>=[0x15,0x16,0x17,0x1f]
  let platform:Platform
  if family==1, !vitaTypes.contains(contentType ?? 0), !content.dropFirst(7).hasPrefix("PCS"){platform = .ps3}
  else if family==2,vitaTypes.contains(contentType ?? 0),content.dropFirst(7).hasPrefix("PCS"){platform = .psvita}
  else{throw AkitoStationError.message("Package platform is unsupported or its header disagrees with its content type. It will not be installed into another console’s folder.")}
  return ConsolePackage(platform:platform,contentID:content,bytes:size)
 }
 public func require(_ selected:Platform)throws{guard platform==selected else{throw AkitoStationError.message("This package is for \(platform.title), but \(selected.title) is selected.")}}
}
public enum ConsoleContent {
 public struct Receipt:Codable,Identifiable,Sendable {
  public var id:String;public var platform:Platform;public var filename:String;public var status:String;public var destination:String;public var date:Date
  public init(platform:Platform,filename:String,status:String,destination:String){id=UUID().uuidString;self.platform=platform;self.filename=filename;self.status=status;self.destination=destination;date=Date()}
 }
 public static func validContentID(_ id:String)->Bool {id.range(of:"^[A-Z]{2}[0-9]{4}-[A-Z0-9]{9}_[0-9]{2}-[A-Za-z0-9_-]{1,32}$",options:.regularExpression) != nil}
 public static func romDirectory(library:URL,platform:Platform)throws->URL {
  guard [.ps3,.ps4,.psvita].contains(platform) else{throw AkitoStationError.message("This console package installer is unavailable.")}
  guard FileManager.default.isWritableFile(atPath:library.path) else{throw AkitoStationError.message("The selected ROM library is unavailable or read-only.")}
  if ["ps3","ps4","psvita"].contains(library.lastPathComponent.lowercased()),library.lastPathComponent.lowercased() != platform.rawValue{throw AkitoStationError.message("Choose a common ROM root or the folder for the selected console.")}
  // A console-specific library is already its destination; don't create ps3/ps3.
  return library.lastPathComponent.lowercased()==platform.rawValue ? library:library.appendingPathComponent(platform.rawValue)
 }
 public static func history(root:URL)throws->[Receipt] {
  let folder=root.appendingPathComponent("ContentImports")
  guard FileManager.default.fileExists(atPath:folder.path) else{return []}
  return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.map{try JSONStore.read(Receipt.self,from:$0)}.sorted{$0.date>$1.date}
 }
 public static func record(_ receipt:Receipt,root:URL)throws {
  let folder=root.appendingPathComponent("ContentImports");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  try JSONStore.write(receipt,to:folder.appendingPathComponent(receipt.id+".json"))
 }
 public static func licenseDestination(_ source:URL,platform:Platform,root:URL)throws->(URL,String) {
  let v=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
  guard v.isRegularFile==true,v.isSymbolicLink != true,(v.fileSize ?? 0)>0,(v.fileSize ?? 0)<=1024*1024,!source.lastPathComponent.hasPrefix("._") else{throw AkitoStationError.message("Choose a nonempty license file up to 1 MB, not a shortcut or AppleDouble file.")}
  let ext=source.pathExtension.lowercased(),base=source.deletingPathExtension().lastPathComponent
  let system=root.appendingPathComponent("Systems/"+(platform.core ?? "unknown"))
  switch platform {
  case .ps3:
   if ext=="rap" || ext=="edat" {
    guard validContentID(base),ext != "rap" || v.fileSize==16 else{throw AkitoStationError.message("PS3 RAP files must contain 16 bytes and use their content ID as the filename.")}
    return(system.appendingPathComponent("home/Library/Application Support/rpcs3/dev_hdd0/home/00000001/exdata/"+base+"."+ext),"Installed in PS3 exdata · runtime validation required")
   }
   guard ["rif","riff","dat"].contains(ext) else{throw AkitoStationError.message("PS3 uses RAP/EDAT licenses. RIF and activation data can be retained for reference; Vita work.bin files belong to Vita.")}
   return(system.appendingPathComponent("ImportedLicenses/"+UUID().uuidString+"/"+source.lastPathComponent),"Imported · this RPCS3 adapter requires RAP/EDAT for activation")
  case .psvita:
   guard ["rif","riff"].contains(ext) || source.lastPathComponent.lowercased()=="work.bin",v.fileSize==512 else{throw AkitoStationError.message("Vita requires a 512-byte work.bin or RIF license file.")}
   let data=try Data(contentsOf:source),id=String(decoding:data[16..<64].prefix(while:{$0 != 0}),as:UTF8.self)
   guard validContentID(id),id.dropFirst(7).hasPrefix("PCS") else{throw AkitoStationError.message("This license does not contain a valid Vita content ID.")}
   let title=String(id.dropFirst(7).prefix(9))
   return(system.appendingPathComponent("fs/ux0/license/"+title+"/"+id+".rif"),"Installed in Vita license storage · runtime validation required")
  case .ps4:
   guard ["rif","riff","dat","bin"].contains(ext) else{throw AkitoStationError.message("Choose your PS4 license or activation-data file.")}
   return(system.appendingPathComponent("ImportedLicenses/"+UUID().uuidString+"/"+source.lastPathComponent),"Imported · shadPS4 has no license-install interface")
  default:throw AkitoStationError.message("Select PS3, PS4 or PlayStation Vita.")
  }
 }
 public static func importLicense(_ source:URL,platform:Platform,root:URL)throws->Receipt {
  let(dest,status)=try licenseDestination(source,platform:platform,root:root)
  let fm=FileManager.default
  let resolvedRoot=root.resolvingSymlinksInPath().path+"/"
  guard dest.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else{throw AkitoStationError.message("License destination escapes Akito Station storage.")}
  try fm.createDirectory(at:dest.deletingLastPathComponent(),withIntermediateDirectories:true)
  if fm.fileExists(atPath:dest.path) {
   guard try digest(source)==digest(dest) else{throw AkitoStationError.message("A different license is already installed for this content ID. The existing license was preserved.")}
  }else{
   let data=try Data(contentsOf:source);try data.write(to:dest,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:dest.path)
   guard try digest(source)==digest(dest) else{throw AkitoStationError.message("License copy verification failed.")}
  }
  let receipt=Receipt(platform:platform,filename:source.lastPathComponent,status:status,destination:dest.path);try record(receipt,root:root);return receipt
 }
 /// Installer-created library games are linked into the runtime's virtual disk, avoiding a second game copy.
 public static func linkInstalledGame(_ source:URL,to target:URL,platform:Platform)throws->Bool {
  let marker=source.appendingPathComponent(".arm-install.json")
  guard FileManager.default.fileExists(atPath:marker.path) else{return false}
  let record=try JSONStore.read([String:String].self,from:marker)
  guard record["platform"]==platform.rawValue,record["titleID"]==source.lastPathComponent else{throw AkitoStationError.message("Installed game record does not match its console or title.")}
  let fm=FileManager.default
  try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
  if fm.fileExists(atPath:target.path) || (try? fm.destinationOfSymbolicLink(atPath:target.path)) != nil {
   if target.resolvingSymlinksInPath()==source.resolvingSymlinksInPath(){return true}
   throw AkitoStationError.message("The runtime already has a different copy of this title. Existing game data was preserved.")
  }
  try fm.createSymbolicLink(at:target,withDestinationURL:source);return true
 }
}
