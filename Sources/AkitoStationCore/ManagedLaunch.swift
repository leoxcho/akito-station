import Foundation

/// Direct game launches into locally imported runtime copies, with Akito Station-owned user data.
public struct ManagedLaunch:Sendable {
 public static let engines:Set<String>=["ppsspp_sdl","duckstation","rpcs3","armsx2","pcsx2","vita3k","eden","ryujinx","shadps4","lime3ds","cemu","xemu","xenia","azahar","dolphin_app","flycast"]
 public static func platforms(for engine:String)->[Platform] {
  if let definition=RuntimeCatalog.definition(engine),definition.desktop{return definition.platforms}
  switch engine {
  case "ppsspp_sdl":return [.psp]
  case "duckstation":return [.ps1]
  case "armsx2","pcsx2":return [.ps2]
  case "rpcs3":return [.ps3]
  case "vita3k":return [.psvita]
  case "eden":return [.switchConsole]
  case "ryujinx":return [.switchConsole]
  case "shadps4":return [.ps4]
  case "lime3ds":return [.n3ds]
  case "cemu":return [.wiiu]
  case "xemu":return [.xbox]
  case "xenia":return [.xbox360]
  default:return []
  }
 }
 public let arguments:[String]
 public let environment:[String:String]
 public let workingDirectory:URL
 public init(engine:String,binary:URL,game:URL,profile:GameProfile,data:URL,caches:URL)throws {
 try EmbeddedRuntime.requirePlayable(engine:engine)
 let fm=FileManager.default;let home=data.appendingPathComponent("home")
 for path in [data,home,caches,home.appendingPathComponent(".config"),home.appendingPathComponent(".local/share")]{try fm.createDirectory(at:path,withIntermediateDirectories:true)}
 var env=ProcessInfo.processInfo.environment;env["HOME"]=home.path;env["CFFIXED_USER_HOME"]=home.path;env["XDG_CONFIG_HOME"]=home.appendingPathComponent(".config").path;env["XDG_DATA_HOME"]=home.appendingPathComponent(".local/share").path;env["XDG_CACHE_HOME"]=caches.path
 if engine == "cemu"{try CemuAudioConfiguration.prepare(data:data,profile:profile)}
 try GraphicsConfiguration.prepare(engine:engine,data:data,profile:profile)
 workingDirectory=data
 switch engine {
 case "rpcs3":
 let firmware=data.appendingPathComponent("dev_flash")
 var boot=try PS3DiscImport.prepare(game,into:data)
 // Digital titles need their title-ID directory under the managed dev_hdd0/game.
 if fm.fileExists(atPath:game.appendingPathComponent("USRDIR/EBOOT.BIN").path){
 let info=try ParamSFO.read(game.appendingPathComponent("PARAM.SFO"));guard let id=info["TITLE_ID"],id.range(of:"^[A-Z0-9]{9}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Invalid PS3 title ID")}
 let target=home.appendingPathComponent("Library/Application Support/rpcs3/dev_hdd0/game/"+id)
 if try !ConsoleContent.linkInstalledGame(game,to:target,platform:.ps3){try Self.copyOnce(game,to:target)};boot=target
 }
 let launch=try RPCS3Launch(game:boot,profile:profile,managedHome:home,caches:caches,firmware:firmware);arguments=launch.arguments;env.merge(launch.environment){_,new in new}
 case "ppsspp_sdl":
 let stick=home.appendingPathComponent(".config/ppsspp"),settings=stick.appendingPathComponent("PSP/SYSTEM/ppsspp.ini"),controls=stick.appendingPathComponent("PSP/SYSTEM/controls.ini")
 guard fm.fileExists(atPath:settings.path),fm.fileExists(atPath:controls.path) else{throw AkitoStationError.message("Import PPSSPP settings and controls in Emulator Settings first.")}
 arguments=["--pause-menu-exit","--appendconfig="+settings.path]+(profile.fullscreen ? ["--fullscreen"]:[])+[game.path]
 case "duckstation":
 guard fm.fileExists(atPath:data.appendingPathComponent("home/Library/Application Support/DuckStation/settings.ini").path) else{throw AkitoStationError.message("Import DuckStation settings in Emulator Settings first.")}
 arguments=["-batch","-nogui"]+(profile.fullscreen ? ["-fullscreen"]:[])+["--",game.path]
 case "armsx2","pcsx2":
 guard fm.fileExists(atPath:data.appendingPathComponent("inis/PCSX2.ini").path) else{throw AkitoStationError.message("Import PS2 settings and BIOS into Akito Station managed storage first.")}
 arguments=["-nogui","-batch","-datapath",data.path]+(EmulatorSettings.native(profile) ? []:[profile.fullscreen ? "-fullscreen":"-nofullscreen"])+["--",game.path]
 case "ryujinx":arguments=["--root-data-dir",data.path]+(profile.fullscreen ? ["--fullscreen"]:[])+[game.path]
 case "lime3ds":arguments=["--no-gui"]+(profile.fullscreen ? ["-f"]:[])+[game.path]
 case "shadps4":arguments=["-g",game.hasDirectoryPath ? game.appendingPathComponent("eboot.bin").path:game.path]+(EmulatorSettings.native(profile) ? []:["-f",profile.fullscreen ? "true":"false"])
 case "cemu":arguments=["--game",game.path,"--mlc",data.appendingPathComponent("mlc01").path]+(profile.fullscreen ? ["--fullscreen"]:[])
 case "xenia":arguments=["--storage_root="+data.path,"--content_root="+data.appendingPathComponent("content").path,"--config="+data.appendingPathComponent("xenia-edge.config.toml").path]+(EmulatorSettings.native(profile) ? []:["--gpu=metal","--fullscreen="+(profile.fullscreen ? "true":"false")])+[game.path]
 case "xemu":
 let config=data.appendingPathComponent("xemu.toml")
 guard fm.fileExists(atPath:config.path) else{throw AkitoStationError.message("Xbox BIOS, MCPX and a formatted hard disk must be configured in Akito Station's managed Xbox storage.")}
 arguments=["-config_path",config.path,"-dvd_path",game.path]+(profile.fullscreen ? ["-full-screen"]:[])
 case "vita3k":
 let info=try ParamSFO.read(game.appendingPathComponent("sce_sys/param.sfo"));guard let id=info["TITLE_ID"],id.range(of:"^[A-Z0-9]{9}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Vita Play requires an installed, decrypted game folder with sce_sys/param.sfo.")}
 let fs=data.appendingPathComponent("fs");let target=fs.appendingPathComponent("ux0/app/"+id);if try !ConsoleContent.linkInstalledGame(game,to:target,platform:.psvita){try Self.copyOnce(game,to:target)}
 let config=data.appendingPathComponent("config.yml")
 arguments=["--config-location",config.path,"--load-config","--installed-path",id]+(profile.fullscreen ? ["--fullscreen"]:[])
 default:throw AkitoStationError.message("Unknown managed executable")
 }
 environment=env
 }
 private static func copyOnce(_ source:URL,to target:URL)throws {
 let fm=FileManager.default;guard !fm.fileExists(atPath:target.path) else{return}
 try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
 let staging=target.deletingLastPathComponent().appendingPathComponent(".import-"+UUID().uuidString)
 do {try StorageMover.copyVerified(from:source,to:staging);try fm.moveItem(at:staging,to:target)}catch{try? fm.removeItem(at:staging);throw error}
 }
}
