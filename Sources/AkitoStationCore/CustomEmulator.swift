import Foundation

/// Custom launch settings extend the existing versioned runtime manifest. Arguments are
/// individual argv entries, never a shell command; spaces in game paths stay intact.
public enum GameLaunchMethod:String,Codable,Sendable {case arguments, openDocument}

public struct CustomEmulatorConfiguration:Codable,Equatable,Sendable {
 public var name:String
 public var gameLaunchMethod:GameLaunchMethod?
 /// Older Astris registrations used CLI defaults, but its native frontend handles open-document events.
 public var effectiveGameLaunchMethod:GameLaunchMethod {gameLaunchMethod ?? (bundleIdentifier?.lowercased() == "v380-ori.astris" ? .openDocument:.arguments)}
 public var bundleIdentifier:String?
 public var iconRelativePath:String?
 public var arguments:[String]=[]
 public var gameArgument:String="{game}"
 public var additionalArguments:[String]=[]
 public var testArguments:[String]=[]
 public var workingDirectory:String=""
 public var environment:[String:String]=[:]
 public var saveLocation:String=""
 public var configLocation:String=""
 public var recognizedEngine:String?
 public init(name:String){self.name=name}
 public func validate()throws {
  guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=200 else{throw AkitoStationError.message("Enter an emulator name.")}
  for value in arguments+additionalArguments+testArguments+[gameArgument,workingDirectory]+Array(environment.values) {
   guard !value.contains("\0"),value.count<=16384 else{throw AkitoStationError.message("Launch configuration contains an invalid argument.")}
   var remainder=value
   for placeholder in ["{game}","{gameDirectory}","{runtimeDirectory}"]{remainder=remainder.replacingOccurrences(of:placeholder,with:"")}
   guard !remainder.contains("{"),!remainder.contains("}") else{throw AkitoStationError.message("Use only {game}, {gameDirectory} or {runtimeDirectory} placeholders.")}
  }
  guard !testArguments.contains(where:{$0.contains("{game}") || $0.contains("{gameDirectory}")}) else{throw AkitoStationError.message("Test arguments must not require a game.")}
  for key in environment.keys {
   guard key.range(of:"^[A-Za-z_][A-Za-z0-9_]*$",options:.regularExpression) != nil else{throw AkitoStationError.message("Environment names must use letters, digits and underscores.")}
  }
 }
}

public struct EmulatorDetection:Sendable {
 public var name:String;public var executable:URL;public var base:URL
 public var bundleIdentifier:String?;public var version:String;public var architecture:String
 public var iconRelativePath:String?;public var recognizedEngine:String?
 public var supportedPlatforms:[Platform]
 public static func inspect(_ input:URL,executableOverride:String="")throws->EmulatorDetection {
  let fm=FileManager.default,input=input.standardizedFileURL.resolvingSymlinksInPath()
  let app=input.pathExtension.lowercased()=="app"
  guard fm.fileExists(atPath:input.path) else{throw AkitoStationError.message("Executable not found. Choose its current location to relink it.")}
  var info:[String:Any]=[:]
  if app {
   guard let data=try? Data(contentsOf:input.appendingPathComponent("Contents/Info.plist")),let value=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else{throw AkitoStationError.message("This application has no readable Info.plist.")}
   info=value
  }
  let relative=executableOverride.isEmpty ? "Contents/MacOS/"+(info["CFBundleExecutable"] as? String ?? ""):executableOverride
  if app {guard !relative.hasPrefix("/"),!relative.split(separator:"/").contains("..") else{throw AkitoStationError.message("Choose an executable inside the application bundle.")}}
  let exe=app ? input.appendingPathComponent(relative).resolvingSymlinksInPath():input
  guard !app || exe.path.hasPrefix(input.path+"/") else{throw AkitoStationError.message("Executable escapes the application bundle.")}
  guard fm.isExecutableFile(atPath:exe.path),(try? exe.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true else{throw AkitoStationError.message("Executable not found or not executable. Choose a macOS application or executable.")}
  let architecture=try detectArchitecture(exe)
  let name=info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? input.deletingPathExtension().lastPathComponent
  let identifier=info["CFBundleIdentifier"] as? String
  let identity=(name+" "+input.lastPathComponent+" "+(identifier ?? "")).lowercased()
  let aliases:[(String,String)]=[("pcsx2","pcsx2"),("rpcs3","rpcs3"),("duckstation","duckstation"),("armsx2","armsx2"),("vita3k","vita3k"),("shadps4","shadps4"),("ryujinx","ryujinx"),("azahar","azahar"),("lime3ds","lime3ds"),("dolphin","dolphin_app"),("ppsspp","ppsspp_sdl"),("flycast","flycast"),("cemu","cemu"),("xemu","xemu"),("xenia","xenia"),("eden","eden")]
  let engine=aliases.first{identity.contains($0.0)}?.1
  var icon:String?
  if app,let filename=info["CFBundleIconFile"] as? String {
   let candidate="Contents/Resources/"+filename+(URL(fileURLWithPath:filename).pathExtension.isEmpty ? ".icns":"")
   let url=input.appendingPathComponent(candidate).resolvingSymlinksInPath()
   if url.path.hasPrefix(input.path+"/"),fm.fileExists(atPath:url.path){icon=candidate}
  }
  return EmulatorDetection(name:name,executable:exe,base:app ? input:input.deletingLastPathComponent(),bundleIdentifier:identifier,version:info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "Unknown",architecture:architecture,iconRelativePath:icon,recognizedEngine:engine,supportedPlatforms:engine.flatMap{RuntimeCatalog.definition($0)?.platforms} ?? [])
 }
 private static func detectArchitecture(_ binary:URL)throws->String {
  let handle=try FileHandle(forReadingFrom:binary);defer{try? handle.close()}
  let header=try handle.read(upToCount:4096) ?? Data()
  if header.starts(with:[35,33]){return "script"}
  let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/file");process.arguments=["-b",binary.path];process.standardOutput=pipe;process.standardError=FileHandle.nullDevice;try process.run()
  let description=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);process.waitUntilExit()
  guard description.contains("Mach-O"),description.contains("executable") else{throw AkitoStationError.message("Choose a macOS executable. A core dylib needs a supported core adapter; Windows and Linux executables cannot be launched directly.")}
  if description.contains("arm64"){return description.contains("x86_64") ? "universal":"arm64"}
  if description.contains("x86_64"){return "x86_64"}
  throw AkitoStationError.message("This executable does not support this Mac's architecture.")
 }
}

extension ManagedLaunch {
 public init(custom:CustomEmulatorConfiguration,runtimeDirectory:URL,game:URL?=nil)throws {
  try custom.validate()
  func expand(_ template:String)throws->String {
   if game==nil && (template.contains("{game}") || template.contains("{gameDirectory}")){throw AkitoStationError.message("This launch setting needs a game. Use a separate test argument or remove game placeholders from the working directory/environment.")}
   return template.replacingOccurrences(of:"{game}",with:game?.path ?? "").replacingOccurrences(of:"{gameDirectory}",with:game?.deletingLastPathComponent().path ?? "").replacingOccurrences(of:"{runtimeDirectory}",with:runtimeDirectory.path)
  }
  if game != nil {
   let templates=custom.arguments+(custom.effectiveGameLaunchMethod == .openDocument || custom.gameArgument.isEmpty ? []:[custom.gameArgument])+custom.additionalArguments
   guard custom.effectiveGameLaunchMethod == .openDocument || templates.contains(where:{$0.contains("{game}")}) else{throw AkitoStationError.message("Direct game launch is not configured. Add {game} to the emulator's game arguments or choose Open game as document.")}
  }
  var launchArguments=custom.arguments
  // Repair only the old automatic Eden defaults; preserve explicit user argument layouts.
  if game != nil,custom.recognizedEngine == "eden",launchArguments.isEmpty,custom.gameArgument == "{game}",custom.additionalArguments.isEmpty{launchArguments=["-g"]}
  arguments=try (game==nil ? custom.testArguments:launchArguments+(custom.effectiveGameLaunchMethod == .openDocument || custom.gameArgument.isEmpty ? []:[custom.gameArgument])+custom.additionalArguments).map(expand)
  let workingPath=custom.workingDirectory.isEmpty ? runtimeDirectory.path:try expand(custom.workingDirectory)
  guard workingPath.hasPrefix("/") else{throw AkitoStationError.message("Choose an absolute working directory or use {runtimeDirectory}.")}
  workingDirectory=URL(fileURLWithPath:workingPath)
  guard workingDirectory.path.hasPrefix("/"),(try? workingDirectory.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true else{throw AkitoStationError.message("Working directory not found. Choose an existing folder.")}
  var env=ProcessInfo.processInfo.environment
  for (key,value) in custom.environment {env[key]=try expand(value)}
  environment=env
 }
}

extension RuntimeManager {
 /// Verify the candidate and write a new version before activation. Old versions remain for rollback.
 @discardableResult public func registerCustom(input:URL,executableOverride:String="",platform:Platform,configuration:CustomEmulatorConfiguration,managed:Bool=false,id:String?=nil)throws->RuntimeManifest {
  guard platform != .unknown else{throw AkitoStationError.message("Choose a supported console.")}
  try configuration.validate()
  let detection=try EmulatorDetection.inspect(input,executableOverride:executableOverride)
  if let known=configuration.recognizedEngine,let definition=RuntimeCatalog.definition(known){guard definition.platforms.contains(platform) else{throw AkitoStationError.message("The recognized emulator does not support this console.")}}
  let identifier=id ?? "custom-"+UUID().uuidString.lowercased()
  guard identifier.hasPrefix("custom-"),identifier.range(of:"^[a-zA-Z0-9_-]+$",options:.regularExpression) != nil else{throw AkitoStationError.message("Invalid custom emulator identifier.")}
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let storage=root.resolvingSymlinksInPath(),source=input.resolvingSymlinksInPath()
  guard source != storage,!source.path.hasPrefix(storage.path+"/"),!storage.path.hasPrefix(source.path+"/") else{throw AkitoStationError.message("Choose an original installation outside runtime storage.")}
  let parent=root.appendingPathComponent(identifier)
  try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
  guard parent.resolvingSymlinksInPath().deletingLastPathComponent().path==storage.path else{throw AkitoStationError.message("Runtime storage escapes its configured directory.")}
  let version=UUID().uuidString.lowercased(),stage=parent.appendingPathComponent(".register-"+version),destination=parent.appendingPathComponent(version)
  try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false)
  defer{try? FileManager.default.removeItem(at:stage)}
  var config=configuration;config.bundleIdentifier=detection.bundleIdentifier;config.iconRelativePath=detection.iconRelativePath
  let relative=detection.executable.path.dropFirst(detection.base.path.count+1)
  var library=String(relative),base=detection.base
  if managed {
   if source.pathExtension.lowercased()=="app" {
    try FileManager.default.copyItem(at:source,to:stage.appendingPathComponent(source.lastPathComponent))
    library=source.lastPathComponent+"/"+library;config.iconRelativePath=config.iconRelativePath.map{source.lastPathComponent+"/"+$0}
   }else{try FileManager.default.copyItem(at:source,to:stage.appendingPathComponent(source.lastPathComponent));library=source.lastPathComponent}
   base=stage
  }
  _=try ManagedLaunch(custom:config,runtimeDirectory:base,game:URL(fileURLWithPath:"/tmp/Akito sample game.iso"))
  var manifest=RuntimeManifest(id:identifier,version:version,upstream:"",revision:detection.version,library:library,sha256:try digest(base.appendingPathComponent(library)),license:"User-selected installation",validated:true)
  manifest.trustStatus=managed ? .userImported:.customExternal;manifest.custom=config;manifest.platforms=[platform];manifest.architecture=detection.architecture;manifest.capabilities=["customLaunch","nativeWindow","gameUntested"];manifest.channel=managed ? "custom-managed":"external"
  if !managed{manifest.externalLocation=Location(detection.base);manifest.capabilities.append("externalRuntime")}
  try JSONStore.write(manifest,to:stage.appendingPathComponent("manifest.json"))
  try FileManager.default.moveItem(at:stage,to:destination)
  do{try activate(identifier,version:version)}catch{try? FileManager.default.removeItem(at:destination);throw error}
  return manifest
 }
 public func runtimeDirectory(_ manifest:RuntimeManifest)throws->URL {try manifest.externalLocation?.resolve() ?? root.appendingPathComponent(manifest.id+"/"+manifest.version)}
}

extension RuntimeManager {
 @discardableResult public func editCustom(_ runtime:RuntimeManifest,platform:Platform,configuration:CustomEmulatorConfiguration,input:URL?=nil,executableOverride:String="")throws->RuntimeManifest {
  guard runtime.custom != nil,platform != .unknown else{throw AkitoStationError.message("Choose a custom emulator and supported console.")}
  try configuration.validate()
  if let known=configuration.recognizedEngine,let definition=RuntimeCatalog.definition(known),!definition.platforms.contains(platform){throw AkitoStationError.message("The recognized emulator does not support this console.")}
  var updated=runtime
  let base=try runtimeDirectory(runtime)
  if let input=input {
   let detection=try EmulatorDetection.inspect(input,executableOverride:executableOverride)
   guard detection.executable.path.hasPrefix(base.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Choose Relink to register an installation outside the current runtime directory.")}
   updated.library=String(detection.executable.path.dropFirst(base.resolvingSymlinksInPath().path.count+1));updated.sha256=try digest(detection.executable);updated.architecture=detection.architecture;updated.revision=detection.version
  }else{_=try selected(runtime.id,version:runtime.version)}
  _=try ManagedLaunch(custom:configuration,runtimeDirectory:base,game:URL(fileURLWithPath:"/tmp/Akito sample game.iso"))
  updated.custom=configuration;updated.platforms=[platform]
  // The selected manifest validates identifiers/path containment before any write.
  guard runtime.id.range(of:"^custom-[a-zA-Z0-9_-]+$",options:.regularExpression) != nil,runtime.version.range(of:"^[a-zA-Z0-9_-]+$",options:.regularExpression) != nil else{throw AkitoStationError.message("Invalid custom runtime manifest.")}
  let folder=root.appendingPathComponent(runtime.id+"/"+runtime.version)
  guard folder.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Runtime path escapes its storage directory.")}
  try JSONStore.write(updated,to:folder.appendingPathComponent("manifest.json"))
  return updated
 }
}
