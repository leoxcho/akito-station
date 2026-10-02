import Foundation

/// Preparation for the managed RPCS3 executable adapter. Firmware must already be installed
/// in Akito Station-owned storage; never point writable VFS mounts at an existing emulator installation.
public struct RPCS3Launch {
 public let arguments:[String]
 public let environment:[String:String]
 public init(game:URL,profile:GameProfile,managedHome:URL,caches:URL,firmware:URL)throws {
 let fm=FileManager.default
 guard fm.isReadableFile(atPath:game.path) else{throw AkitoStationError.message("PS3 game is unavailable")}
 guard fm.isReadableFile(atPath:firmware.appendingPathComponent("sys/external/liblv2.sprx").path) else{throw AkitoStationError.message("Install PS3 firmware into Akito Station’s managed PS3 system storage before launching.")}
 for folder in [managedHome,caches]{guard fm.isWritableFile(atPath:folder.path) else{throw AkitoStationError.message("PS3 storage is unavailable: \(folder.path)")}}
 let config=managedHome.appendingPathComponent("Library/Application Support/rpcs3")
 try fm.createDirectory(at:config,withIntermediateDirectories:true)
 let cacheLink=managedHome.appendingPathComponent("Library/Caches/rpcs3")
 try fm.createDirectory(at:cacheLink.deletingLastPathComponent(),withIntermediateDirectories:true)
 if fm.fileExists(atPath:cacheLink.path){guard cacheLink.resolvingSymlinksInPath().path==caches.resolvingSymlinksInPath().path else{throw AkitoStationError.message("PS3 cache location has changed; migrate the existing managed cache first.")}}else{try fm.createSymbolicLink(at:cacheLink,withDestinationURL:caches)}
 func quote(_ value:String)->String{String(data:try! JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),encoding:.utf8)!}
 let vfs="\"/dev_flash/\": "+quote(firmware.path+"/")+"\n"
 try Data(vfs.utf8).write(to:config.appendingPathComponent("vfs.yml"),options:.atomic)
 var settings="Core:\n  PPU Decoder: Recompiler (LLVM)\n  SPU Decoder: Recompiler (LLVM)\nVideo:\n  Renderer: Vulkan\n  VSync Mode: \(profile.vsync ? "Full":"Disabled")\n  Resolution Scale: \(profile.resolutionScale*100)\n  Anisotropic Filter Override: \(GraphicsConfiguration.anisotropy(profile))\nAudio:\n  Renderer: Cubeb\n  Master Volume: \(Int(profile.volume*100))\nMiscellaneous:\n  Exit RPCS3 when process finishes: true\n"
 if EmulatorSettings.native(profile){settings=try String(contentsOf:config.appendingPathComponent("config.yml"))}
 let file=config.appendingPathComponent("arm-game.yml");try Data(settings.utf8).write(to:file,options:.atomic)
 arguments=["--no-gui","--config",file.path]+(profile.fullscreen ? ["--fullscreen"]:[])+[game.path]
 var env=ProcessInfo.processInfo.environment;env["HOME"]=managedHome.path;env["CFFIXED_USER_HOME"]=managedHome.path;environment=env
 }
}
