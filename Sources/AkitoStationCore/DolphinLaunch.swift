import Foundation

/// Native DolphinNoGUI launch translation. All writable locations belong to Akito Station.
public struct DolphinLaunch {
 public let arguments:[String]
 public let environment:[String:String]
 public init(binary:URL,game:URL,profile:GameProfile,saves:URL,states:URL,caches:URL,screenshots:URL,probe:URL?=nil,bindings:ControllerBindings=ControllerBindings(),useGamepad:Bool=false,nativeSettings:URL?=nil)throws {
  guard profile.renderer == "Metal",(1...8).contains(profile.resolutionScale),(0...1).contains(profile.volume) else{throw AkitoStationError.message("Dolphin requires Metal, resolution scale 1–8, and volume 0–1")}
  guard ["Original","Stretch"].contains(profile.aspect),["Automatic","Keyboard"].contains(profile.controller) else{throw AkitoStationError.message("Unsupported Dolphin display or controller profile")}
  for url in [saves,states,caches,screenshots]{guard FileManager.default.isWritableFile(atPath:url.path) else{throw AkitoStationError.message("Runtime storage unavailable: \(url.path)")}}
  let user=saves.appendingPathComponent("Dolphin"),config=user.appendingPathComponent("Config")
  try FileManager.default.createDirectory(at:config,withIntermediateDirectories:true)
  if EmulatorSettings.native(profile),let nativeSettings=nativeSettings {
   for file in try EmulatorSettings.documents(engine:"dolphin",data:nativeSettings) {
    let relative=String(file.resolvingSymlinksInPath().path.dropFirst(nativeSettings.appendingPathComponent("Dolphin").resolvingSymlinksInPath().path.count+1))
    let target=user.appendingPathComponent(relative);try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
    try Data(contentsOf:file).write(to:target,options:.atomic)
   }
  }
  let ini="[Analytics]\nEnabled = False\nPermissionAsked = True\n[Interface]\nConfirmStop = False\n[Core]\nEnableCheats = False\n"
  if !EmulatorSettings.native(profile){try Data(ini.utf8).write(to:config.appendingPathComponent("Dolphin.ini"),options:.atomic)}
  // Upstream Quartz key names; no installed emulator preferences are read or copied.
  try bindings.validate()
  let automaticGamepad = !EmulatorSettings.native(profile) && useGamepad && profile.controller != "Keyboard" && bindings.gameCubeDevice == "Quartz/0/Keyboard & Mouse"
  if !EmulatorSettings.native(profile){try Data((automaticGamepad ? bindings.dolphinGamepadINI():bindings.dolphinPadINI()).utf8).write(to:config.appendingPathComponent("GCPadNew.ini"),options:.atomic)}
  if automaticGamepad{try Data(bindings.dolphinWiiINI(mode:bindings.wiiMode ?? "Nunchuk").utf8).write(to:config.appendingPathComponent("WiimoteNew.ini"),options:.atomic)}
  var args=["-u",user.path,"-e",game.path];if !EmulatorSettings.native(profile){args += ["-v","Metal"]}
  let settings=["GFX.Settings.InternalResolution":String(profile.resolutionScale),"GFX.Hardware.VSync":profile.vsync ? "True":"False","GFX.Settings.AspectRatio":profile.aspect == "Stretch" ? "3":"0","Dolphin.Display.Fullscreen":profile.fullscreen ? "True":"False","Dolphin.DSP.Volume":String(Int(profile.volume*100))]
  for key in settings.keys.sorted() where !EmulatorSettings.native(profile){args += ["-C",key+"="+settings[key]!]}
  arguments=args
  var env=ProcessInfo.processInfo.environment
  if automaticGamepad{env["ARM_DOLPHIN_AUTO_GAMEPAD"]="1"}else{env.removeValue(forKey:"ARM_DOLPHIN_AUTO_GAMEPAD")}
  env["ARM_DOLPHIN_SYS"]=binary.deletingLastPathComponent().appendingPathComponent("Sys").path
  env["ARM_DOLPHIN_SAVES"]=saves.path;env["ARM_DOLPHIN_CACHE"]=caches.path;env["ARM_DOLPHIN_STATES"]=states.path;env["ARM_DOLPHIN_SCREENSHOTS"]=screenshots.path
  if let probe=probe{env["ARM_DOLPHIN_PROBE"]=probe.path}else{env.removeValue(forKey:"ARM_DOLPHIN_PROBE")}
  environment=env
 }
}
