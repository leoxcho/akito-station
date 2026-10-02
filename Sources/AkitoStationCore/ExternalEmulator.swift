import Foundation

/// Desktop handoff while native integration is deferred. Uses the installed app's own data.
public enum ExternalEmulator {
 public static func name(_ platform:Platform)->String? {
  switch platform {case .psvita:return "Vita3K";case .switchConsole:return "Eden";case .ps4:return "shadPS4";default:return nil}
 }
 public static func application(_ platform:Platform, roots:[URL]?=nil)->URL? {
  guard let name=name(platform) else{return nil}
  let home=FileManager.default.homeDirectoryForCurrentUser
  let locations=roots ?? [home.appendingPathComponent("Applications/Emulation"),home.appendingPathComponent("Applications"),URL(fileURLWithPath:"/Applications")]
  for root in locations {
   let apps=((try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []).filter {
    let stem=$0.deletingPathExtension().lastPathComponent.lowercased()
    return $0.pathExtension.lowercased()=="app" && (stem==name.lowercased() || stem.hasPrefix(name.lowercased()+" (")) && Bundle(url:$0)?.executableURL.map{FileManager.default.isExecutableFile(atPath:$0.path)} == true
   }.sorted{$0.lastPathComponent.compare($1.lastPathComponent,options:.numeric) == .orderedDescending}
   if let app=apps.first{return app}
  }
  return nil
 }
 public static let optionalEngines:Set<String> = ["eden","vita3k","shadps4"]
 public static func managedApplication(_ platform:Platform,root:URL)throws->URL {
  guard name(platform) != nil else{throw AkitoStationError.message("No external emulator assigned")}
  let id=platform == .switchConsole ? "eden":platform.core!
  let (manifest,binary)=try RuntimeManager(root:root).selected(id)
  guard !manifest.capabilities.contains("startupBlocked") else{throw AkitoStationError.message("This emulator cannot start on this Mac.")}
  let app=binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  guard app.pathExtension.lowercased()=="app",Bundle(url:app)?.executableURL?.standardizedFileURL==binary.standardizedFileURL else{throw AkitoStationError.message("Runtime does not contain a valid emulator app")}
  return app
 }
 public static func arguments(_ platform:Platform,game:URL)throws->[String] {
  switch platform {
  case .psvita,.switchConsole:return [game.path]
  case .ps4:
   var directory:ObjCBool=false
   guard FileManager.default.fileExists(atPath:game.path,isDirectory:&directory) else{throw AkitoStationError.message("PS4 game is unavailable")}
   let boot=directory.boolValue ? game.appendingPathComponent("eboot.bin"):game
   guard boot.lastPathComponent.lowercased()=="eboot.bin",FileManager.default.isReadableFile(atPath:boot.path) else{throw AkitoStationError.message("shadPS4 requires an extracted game folder containing eboot.bin.")}
   return ["-g",boot.path]
  default:throw AkitoStationError.message("No external emulator assigned")
  }
 }
}
