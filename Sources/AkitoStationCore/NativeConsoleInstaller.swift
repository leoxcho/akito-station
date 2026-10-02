import Foundation
import RuntimeSupport

public enum NativeConsoleInstaller {
 public struct Result:Sendable {public let destination:URL;public let status:String}
 public static func encodeSuppliedVitaLicense(_ data:Data)throws->String {
  guard data.count==512 else{throw AkitoStationError.message("Vita requires a supplied 512-byte RIF")}
  var output=Data(count:akito_zlib_bound(data.count)),length=output.count
  let status=data.withUnsafeBytes{input in output.withUnsafeMutableBytes{buffer in akito_zlib_compress(input.bindMemory(to:UInt8.self).baseAddress!,data.count,buffer.bindMemory(to:UInt8.self).baseAddress!,&length)}}
  guard status==0 else{throw AkitoStationError.message("Could not encode supplied Vita license")}
  output.count=length;return output.base64EncodedString()
 }
 public static func validateTree(_ root:URL)throws {
  let values=try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
  guard values.isDirectory==true,values.isSymbolicLink != true,let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey]) else{throw AkitoStationError.message("Choose a regular content folder")}
  for case let file as URL in files {
   let value=try file.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
   guard value.isSymbolicLink != true,(value.isDirectory==true || value.isRegularFile==true),file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Content includes a symlink, special file or escaping path")}
  }
 }
 /// Publish a verified merge in a fresh sibling. Existing Akito title is retained as backup.
 @discardableResult public static func publish(_ source:URL,to destination:URL,platform:Platform,title:String)throws->URL? {
  let source=source.resolvingSymlinksInPath().standardizedFileURL,destination=destination.standardizedFileURL
  guard title.range(of:"^[A-Z0-9]{9}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Invalid title identifier")}
  try validateTree(source)
  let fm=FileManager.default,src=source.resolvingSymlinksInPath().path,dst=destination.resolvingSymlinksInPath().path
  guard src != dst,!src.hasPrefix(dst+"/"),!dst.hasPrefix(src+"/"),(try? destination.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true else{throw AkitoStationError.message("Content locations overlap or destination is a symlink")}
  try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
  if fm.fileExists(atPath:destination.path){
   let marker=try? JSONStore.read([String:String].self,from:destination.appendingPathComponent(".arm-install.json"))
   guard marker?["platform"]==platform.rawValue,marker?["titleID"]==title else{throw AkitoStationError.message("An existing non-Akito title occupies the destination; originals preserved")}
  }
  let prepared=destination.deletingLastPathComponent().appendingPathComponent(".prepare-"+UUID().uuidString)
  defer{if fm.fileExists(atPath:prepared.path){try? fm.removeItem(at:prepared)}}
  if fm.fileExists(atPath:destination.path){try StorageMover.copyVerified(from:destination,to:prepared)}else{try fm.createDirectory(at:prepared,withIntermediateDirectories:false)}
  guard let files=fm.enumerator(at:source,includingPropertiesForKeys:[.isDirectoryKey,.isRegularFileKey]) else{throw AkitoStationError.message("Cannot enumerate content")}
  for case let file as URL in files {
   let relative=String(file.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(source.path.count+1)),target=prepared.appendingPathComponent(relative),value=try file.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey])
   if value.isDirectory==true{try fm.createDirectory(at:target,withIntermediateDirectories:true)}
   else {
    try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
    if fm.fileExists(atPath:target.path){guard (try target.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile==true else{throw AkitoStationError.message("Content update has a conflicting file type")};try fm.removeItem(at:target)}
    try fm.copyItem(at:file,to:target);guard try digest(file)==digest(target) else{throw AkitoStationError.message("Content copy verification failed")}
   }
  }
  try JSONStore.write(["platform":platform.rawValue,"titleID":title],to:prepared.appendingPathComponent(".arm-install.json"))
  var backup:URL?
  if fm.fileExists(atPath:destination.path){let backups=destination.deletingLastPathComponent().appendingPathComponent(".arm-backups");try fm.createDirectory(at:backups,withIntermediateDirectories:true);let prior=backups.appendingPathComponent(title+"-"+UUID().uuidString);try fm.moveItem(at:destination,to:prior);backup=prior}
  do{try fm.moveItem(at:prepared,to:destination)}catch{if let backup=backup{try? fm.moveItem(at:backup,to:destination)};throw error}
  return backup
 }
 public static func install(file:URL,platform:Platform,library:URL,data:URL,runtime:URL?,work:URL,license:URL?=nil,folder:Bool=false,log:URL)async throws->Result {
  let fm=FileManager.default
  let console=try ConsoleContent.romDirectory(library:library,platform:platform)
  try fm.createDirectory(at:console,withIntermediateDirectories:true)
  guard console.resolvingSymlinksInPath().path==library.resolvingSymlinksInPath().path || console.resolvingSymlinksInPath().path.hasPrefix(library.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Console destination escapes library")}
  if folder {
   guard platform == .ps4,fm.fileExists(atPath:file.appendingPathComponent("eboot.bin").path) else{throw AkitoStationError.message("Choose an extracted PS4 game folder")}
   let title=try ParamSFO.read(file.appendingPathComponent("sce_sys/param.sfo"))["TITLE_ID"] ?? ""
   guard title.range(of:"^CUSA[0-9]{5}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Invalid extracted PS4 title")}
   let destination=console.appendingPathComponent(title);_=try publish(file,to:destination,platform:platform,title:title)
   return Result(destination:destination,status:"Installed extracted PS4 game; gameplay untested")
  }
  let package=try ConsolePackage.inspect(file);try package.require(platform)
  guard [.ps3,.psvita].contains(platform),let runtime=runtime,fm.isExecutableFile(atPath:runtime.path) else{throw AkitoStationError.message("A compatible installed PS3/Vita runtime is required; PS4 PKG installation is unavailable")}
  let title=package.titleID,stage=work.appendingPathComponent(".package-"+UUID().uuidString),home=stage.appendingPathComponent("home")
  try fm.createDirectory(at:home,withIntermediateDirectories:true)
  defer{if fm.fileExists(atPath:stage.path){try? fm.removeItem(at:stage)}}
  var env=ProcessInfo.processInfo.environment
  env["HOME"]=home.path;env["CFFIXED_USER_HOME"]=home.path;env["XDG_CONFIG_HOME"]=home.appendingPathComponent(".config").path;env["XDG_DATA_HOME"]=home.appendingPathComponent(".local/share").path;env["XDG_CACHE_HOME"]=stage.appendingPathComponent("cache").path
  var outputs:[(URL,URL,URL)]=[],licenseData:Data?,licenseTarget:URL?
  if platform == .ps3 {
   let firmware=data.appendingPathComponent("dev_flash"),config=home.appendingPathComponent("Library/Application Support/rpcs3")
   guard fm.fileExists(atPath:firmware.appendingPathComponent("sys/external/liblv2.sprx").path) else{throw AkitoStationError.message("Requires user-supplied PS3 firmware in managed PS3 storage")}
   try fm.createDirectory(at:config,withIntermediateDirectories:true);try StorageMover.copyVerified(from:firmware,to:config.appendingPathComponent("dev_flash"))
   let result=try await ProcessRunner.run(executable:runtime,arguments:["--headless","--installpkg",file.resolvingSymlinksInPath().path],log:log,timeout:1800,environment:env,workingDirectory:stage)
   let source=config.appendingPathComponent("dev_hdd0/game/"+title)
   let evidence=try readLogs(stage)+((try? String(contentsOf:log)) ?? "")
   guard fm.fileExists(atPath:source.path),evidence.contains("Successfully installed "+file.resolvingSymlinksInPath().path+" (title_id="+title+","),(result.exitCode==0 || evidence.contains("manual_typemap")) else{throw AkitoStationError.message("RPCS3 did not confirm isolated installation; live games unchanged")}
   outputs=[(source,console.appendingPathComponent(title),data.appendingPathComponent("home/Library/Application Support/rpcs3/dev_hdd0/game/"+title))]
  }else{
   let supplied=license ?? data.appendingPathComponent("fs/ux0/license/"+title+"/"+package.contentID+".rif")
   let values=try supplied.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
   guard values.isRegularFile==true,values.isSymbolicLink != true,values.fileSize==512 else{throw AkitoStationError.message("Choose the matching user-supplied 512-byte Vita license")}
   let bytes=try Data(contentsOf:supplied)
   guard String(decoding:bytes[16..<64].prefix(while:{$0 != 0}),as:UTF8.self)==package.contentID else{throw AkitoStationError.message("Vita license does not match package content ID")}
   let encoded=try encodeSuppliedVitaLicense(bytes),fs=stage.appendingPathComponent("fs"),configDirectory=home.appendingPathComponent("Library/Application Support/Vita3K/Vita3K")
   guard !fm.fileExists(atPath:runtime.deletingLastPathComponent().appendingPathComponent("config.yml").path),!fm.fileExists(atPath:runtime.deletingLastPathComponent().appendingPathComponent("portable").path) else{throw AkitoStationError.message("Portable runtime configuration prevents isolated package installation")}
   try fm.createDirectory(at:fs,withIntermediateDirectories:true);try fm.createDirectory(at:configDirectory,withIntermediateDirectories:true)
   _=try await ProcessRunner.run(executable:runtime,arguments:["--help"],log:log,timeout:30,environment:env,workingDirectory:stage)
   let config=configDirectory.appendingPathComponent("config.yml"),text=try String(contentsOf:config)
   guard text.contains("keyboard-button-select") else{throw AkitoStationError.message("Vita runtime did not create a complete isolated configuration")}
   let pref=String(decoding:try JSONEncoder().encode(fs.path+"/"),as:UTF8.self)
   try Data((text.split(separator:"\n",omittingEmptySubsequences:false).filter{!$0.hasPrefix("pref-path:")}.joined(separator:"\n")+"\npref-path: "+pref+"\n").utf8).write(to:config,options:.atomic)
   let result=try await ProcessRunner.run(executable:runtime,arguments:["--console","--pkg",file.resolvingSymlinksInPath().path,"--zrif",encoded],log:log,timeout:1800,environment:env,workingDirectory:stage)
   let evidence=try readLogs(stage)+((try? String(contentsOf:log)) ?? "")
   guard result.exitCode==0,!["|E|","|C|","[error]","[critical]"].contains(where:evidence.contains) else{throw AkitoStationError.message("Vita installer reported an error; live games unchanged")}
   for area in ["app","patch","addcont","theme"] {
    let source=fs.appendingPathComponent("ux0/"+area+"/"+title)
    if fm.fileExists(atPath:source.path){
     if area=="app"{guard fm.fileExists(atPath:source.appendingPathComponent("eboot.bin").path),fm.fileExists(atPath:source.appendingPathComponent("sce_sys/param.sfo").path) else{throw AkitoStationError.message("Incomplete Vita installation")}}
     outputs.append((source,area=="app" ? console.appendingPathComponent(title):console.appendingPathComponent(".content/"+area+"/"+title),data.appendingPathComponent("fs/ux0/"+area+"/"+title)))
    }
   }
   guard !outputs.isEmpty else{throw AkitoStationError.message("Vita installer produced no matching isolated title")}
   licenseData=bytes;licenseTarget=data.appendingPathComponent("fs/ux0/license/"+title+"/"+package.contentID+".rif")
   if let target=licenseTarget,fm.fileExists(atPath:target.path){guard try Data(contentsOf:target)==bytes else{throw AkitoStationError.message("Different Vita license already installed; original preserved")}}
  }
  var committed:[(URL,URL?)]=[],links:[URL]=[]
  do {
   for (source,destination,target) in outputs {
    guard target.resolvingSymlinksInPath().deletingLastPathComponent().path.hasPrefix(data.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Runtime content path escapes managed storage")}
    let backup=try publish(source,to:destination,platform:platform,title:title);committed.append((destination,backup))
    let existed=fm.fileExists(atPath:target.path) || (try? fm.destinationOfSymbolicLink(atPath:target.path)) != nil
    _=try ConsoleContent.linkInstalledGame(destination,to:target,platform:platform);if !existed{links.append(target)}
   }
   if let target=licenseTarget,let bytes=licenseData,!fm.fileExists(atPath:target.path){
    guard target.resolvingSymlinksInPath().path.hasPrefix(data.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("License path escapes managed storage")}
    try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true);try bytes.write(to:target,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
   }
  }catch{
   for target in links.reversed(){try? fm.removeItem(at:target)}
   for (destination,backup) in committed.reversed(){try? fm.removeItem(at:destination);if let backup=backup{try? fm.moveItem(at:backup,to:destination)}}
   throw error
  }
  return Result(destination:outputs[0].1,status:"Installed package; gameplay untested")
 }
 private static func readLogs(_ root:URL)throws->String {
  guard let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey]) else{return ""}
  var text=""
  for case let file as URL in files where file.lastPathComponent.contains(".log") {
   let values=try file.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]);if values.isRegularFile==true,(values.fileSize ?? 0)<16*1024*1024,file.pathExtension != "gz"{text+=(try? String(contentsOf:file)) ?? ""}
  }
  return text
 }
}
