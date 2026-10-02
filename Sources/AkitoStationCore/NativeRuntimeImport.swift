import Foundation

extension RuntimeManager {
 /// Uses OS tools only. User imports are never re-signed or mistaken for verified publishers.
 @discardableResult public func importCatalog(input:URL,definition:RuntimeDefinition,platform:Platform,managed:Bool,host:URL,log:URL,downloadTrust:RuntimeDownloadTrust?=nil,executableOverride:String="")async throws->RuntimeManifest {
  guard definition.platforms.contains(platform) else{throw AkitoStationError.message("Unsupported catalog import")}
  let fm=FileManager.default
  let original=input.resolvingSymlinksInPath(),proposed=root.resolvingSymlinksInPath()
  guard original.path != proposed.path,!original.path.hasPrefix(proposed.path+"/"),!proposed.path.hasPrefix(original.path+"/") else{throw AkitoStationError.message("Original installation and runtime storage must not overlap")}
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  let source=original,storage=root.resolvingSymlinksInPath()
  guard source != storage,!source.path.hasPrefix(storage.path+"/"),!storage.path.hasPrefix(source.path+"/") else{throw AkitoStationError.message("Original installation and runtime storage must not overlap")}
  var binary:URL,base:URL,architecture:String,revision:String
  var bundleFiles:[String:String]?;var trust:String?
  if definition.desktop || definition.id=="dolphin" {
   let detection=try EmulatorDetection.inspect(input,executableOverride:executableOverride)
   guard (definition.id=="dolphin" ? detection.bundleIdentifier=="app.akitostation.dolphin":detection.recognizedEngine==definition.id) else{throw AkitoStationError.message("Selected app does not match this catalog emulator. Use Add Custom Emulator for an unrecognized app.")}
   binary=detection.executable;base=detection.base;architecture=detection.architecture;revision=detection.version
   if downloadTrust != nil,!["arm64","universal"].contains(architecture){throw AkitoStationError.message("Automatic installation requires a native Apple Silicon build. Intel builds use manual import and may require Rosetta")}
   if definition.id=="dolphin" {
    guard architecture=="arm64" || architecture=="universal",fm.fileExists(atPath:binary.deletingLastPathComponent().appendingPathComponent("Sys").path) else{throw AkitoStationError.message("Akito Dolphin adapter requires native code and adjacent Sys assets")}
    let bytes=try Data(contentsOf:binary,options:.mappedIfSafe)
    guard bytes.range(of:Data("ARM_DOLPHIN_PROBE".utf8)) != nil else{throw AkitoStationError.message("This Dolphin build lacks the Akito adapter protocol; use standard Dolphin registration")}
   }
   trust=try RuntimeBundleIntegrity.publisher(base,expectedTeam:downloadTrust?.expectedTeam);bundleFiles=try RuntimeBundleIntegrity.fingerprint(base)
  }else{
   guard input.pathExtension=="dylib" else{throw AkitoStationError.message("Choose a macOS libretro core dylib")}
   let result=try await ProcessRunner.run(executable:host,arguments:["--verify-runtime-core","--core",source.path],log:log,timeout:30)
   guard result.exitCode==0 else{throw AkitoStationError.message("Core ABI verification failed; previous version retained")}
   binary=source;base=source.deletingLastPathComponent();architecture="arm64";revision="local"
  }
  let hash=try digest(binary),version=UUID().uuidString.lowercased()
  let parent=root.appendingPathComponent(definition.id),stage=parent.appendingPathComponent(".import-"+version),destination=parent.appendingPathComponent(version)
  try fm.createDirectory(at:parent,withIntermediateDirectories:true)
  guard parent.resolvingSymlinksInPath().deletingLastPathComponent().path==storage.path else{throw AkitoStationError.message("Registration escapes storage")}
  try fm.createDirectory(at:stage,withIntermediateDirectories:false);defer{if fm.fileExists(atPath:stage.path){try? fm.removeItem(at:stage)}}
  var relative=String(binary.path.dropFirst(base.path.count+1))
  if managed {
   try fm.copyItem(at:source,to:stage.appendingPathComponent(source.lastPathComponent))
   relative=(definition.desktop || definition.id=="dolphin") ? source.lastPathComponent+"/"+relative:source.lastPathComponent
   if definition.id=="ppsspp"{
    let assets=base.appendingPathComponent("PPSSPP")
    guard fm.fileExists(atPath:assets.appendingPathComponent("compat.ini").path) else{throw AkitoStationError.message("PPSSPP core requires its adjacent official PPSSPP assets")}
    try fm.copyItem(at:assets,to:stage.appendingPathComponent("PPSSPP"))
   }
   guard try digest(stage.appendingPathComponent(relative))==hash else{throw AkitoStationError.message("Import copy integrity failed")}
   if definition.desktop || definition.id=="dolphin"{let copied=stage.appendingPathComponent(source.lastPathComponent);try RuntimeBundleIntegrity.inspect(copied);guard try RuntimeBundleIntegrity.fingerprint(copied)==bundleFiles else{throw AkitoStationError.message("Nested bundle copy integrity failed")}}
  }
  var manifest=RuntimeManifest(id:definition.id,version:version,upstream:definition.officialSource,revision:revision,library:relative,sha256:hash,license:definition.license,validated:true)
  manifest.bundleFiles=bundleFiles;manifest.publisherTrust=trust;manifest.trustStatus = .userImported
  if let policy=downloadTrust {
   guard policy.engine==definition.id,policy.repository==definition.releaseRepository else{throw AkitoStationError.message("Download policy does not match imported runtime")}
   let description=trust ?? ""
   let team=description.range(of:"Team ").map{String(description[$0.upperBound...].dropLast())}
   manifest.trustStatus=try policy.status(signed:description.hasPrefix("Signed") || description.hasPrefix("Trusted"),adhoc:description.hasPrefix("Ad-hoc"),team:policy.expectedTeam ?? team)
   manifest.channel="official-download";manifest.revision=policy.release
  }
  manifest.architecture=architecture;manifest.platforms=definition.platforms
  manifest.capabilities=(definition.desktop || definition.id=="dolphin") ? ["nativeWindow","gameUntested"]:["libretro","softwareVideo","abiOnly","gameUntested"]
  if downloadTrust==nil{manifest.channel=managed ? "local-import":"external"}
  if !managed{manifest.externalLocation=Location(base);manifest.capabilities.append("externalRuntime")}
  try JSONStore.write(manifest,to:stage.appendingPathComponent("manifest.json"));try fm.moveItem(at:stage,to:destination)
  do{try activate(definition.id,version:version)}catch{try? fm.removeItem(at:destination);throw error}
  return manifest
 }
}
public enum RuntimeBundleIntegrity {
 public static func inspect(_ app:URL)throws {
  let fm=FileManager.default,base=app.resolvingSymlinksInPath()
  guard let files=fm.enumerator(at:app,includingPropertiesForKeys:[.isSymbolicLinkKey],options:[]) else{throw AkitoStationError.message("Cannot inspect runtime bundle")}
  for case let file as URL in files {
   guard file.resolvingSymlinksInPath().path.hasPrefix(base.path+"/") else{throw AkitoStationError.message("Runtime bundle contains an escaping symlink")}
  }
  // Existing signatures must verify deeply. Truly unsigned user imports are allowed,
  // explicitly recorded as user-selected; ad-hoc signing proves no publisher identity.
  let signature=app.appendingPathComponent("Contents/_CodeSignature")
  if fm.fileExists(atPath:signature.path){
   let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/codesign");process.arguments=["--verify","--deep","--strict",app.path];process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice;try process.run();process.waitUntilExit()
   guard process.terminationStatus==0 else{throw AkitoStationError.message("Runtime bundle signature or nested code integrity failed")}
  }
 }
}

extension RuntimeBundleIntegrity {
 public static func fingerprint(_ app:URL)throws->[String:String] {
  let app=app.resolvingSymlinksInPath().standardizedFileURL
  try inspect(app)
  let fm=FileManager.default
  guard let files=fm.enumerator(at:app,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]) else{throw AkitoStationError.message("Cannot inventory runtime bundle")}
  var result:[String:String]=[:]
  for case let file as URL in files {
   let relative=String(file.path.dropFirst(app.path.count+1)),values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
   if values.isSymbolicLink==true{result[relative]="symlink:"+(try fm.destinationOfSymbolicLink(atPath:file.path));files.skipDescendants()}
   else if values.isRegularFile==true{result[relative]=try RuntimeFileHashes.hash(file)}
  }
  return result
 }
 public static func classify(signed:Bool,adhoc:Bool,team:String?,expectedTeam:String?)throws->String {
  if let expected=expectedTeam {
   guard signed,!adhoc,team==expected else{throw AkitoStationError.message("Runtime publisher Team ID mismatch")}
   return "Trusted publisher: "+expected
  }
  if !signed{return "Unsigned upstream / user-selected build; publisher unverified"}
  if adhoc{return "Ad-hoc signed; publisher unverified"}
  return "Signed, publisher unverified"+(team.map{" (Team "+$0+")"} ?? "")
 }
 public static func publisher(_ app:URL,expectedTeam:String?=nil)throws->String {
  try inspect(app)
  let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/codesign");process.arguments=["--display","--verbose=4",app.path];process.standardOutput=FileHandle.nullDevice;process.standardError=pipe;try process.run()
  let details=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);process.waitUntilExit()
  let signed=process.terminationStatus==0
  if signed {
   let verify=Process();verify.executableURL=URL(fileURLWithPath:"/usr/bin/codesign");verify.arguments=["--verify","--deep","--strict",app.path];verify.standardOutput=FileHandle.nullDevice;verify.standardError=FileHandle.nullDevice;try verify.run();verify.waitUntilExit()
   guard verify.terminationStatus==0 else{throw AkitoStationError.message("Signed upstream nested code integrity failed")}
  }
  let team=details.split(separator:"\n").first{$0.hasPrefix("TeamIdentifier=")}.map{String($0.dropFirst("TeamIdentifier=".count))}
  return try classify(signed:signed,adhoc:details.contains("Signature=adhoc"),team:team,expectedTeam:expectedTeam)
 }
}
