import Foundation
import AkitoStationCore
import RetroHost

struct RuntimeCapabilities {var video=["Metal"];var input=["joypad","keyboard","pointer"];var audio=true;var saveState=true;var loadState=true;var nativeResolutionOnly=true}
struct RuntimeGameStatus {var state:String;var frames:UInt64;var error:String?}
struct GameLoadRequest {let core:URL;let game:URL;let system:URL;let saves:URL;let profile:GameProfile}
@MainActor protocol ARMSystemAdapter:AnyObject {
 func loadGame(_ request:GameLoadRequest)throws
 func start()throws
 func stop()
 func pause()
 func resume()
 func reset()
 func configureVideo(_ profile:GameProfile)throws
 func configureAudio(_ profile:GameProfile)throws
 func configureInput(_ profile:GameProfile)throws
 func saveState(_ url:URL)throws
 func loadState(_ url:URL)throws
 func readRuntimeLogs(_ url:URL)throws->String
 func reportCapabilities()->RuntimeCapabilities
 func reportGameStatus()->RuntimeGameStatus
}
@MainActor final class LibretroSystemAdapter:ARMSystemAdapter {
 private var state="idle"
 func loadGame(_ r:GameLoadRequest)throws{guard state=="idle" || state=="stopped" else{throw AkitoStationError.message("Stop the current game before loading another")};try configureVideo(r.profile);try configureAudio(r.profile);try configureInput(r.profile);guard arm_load(r.core.path,r.game.path,r.system.path,r.saves.path,r.profile.coreOptions) != 0 else{state="failed";throw AkitoStationError.message(String(cString:arm_error()))};state="loaded"}
 func start()throws{guard state=="loaded" || state=="paused" else{throw AkitoStationError.message("No game is loaded")};state="running"}
 func runFrame(){if state=="running"{arm_run()}}
 func stop(){arm_stop();state="stopped"}
 func pause(){if state=="running"{state="paused"}}
 func resume(){if state=="paused"{state="running"}}
 func reset(){if state=="running" || state=="paused"{arm_reset()}}
 func configureVideo(_ p:GameProfile)throws{guard p.renderer=="Metal",p.resolutionScale==1,["Original","Stretch"].contains(p.aspect) else{throw AkitoStationError.message("This core supports Metal presentation at native internal resolution")}}
 func configureAudio(_ p:GameProfile)throws{guard (0...1).contains(p.volume) else{throw AkitoStationError.message("Audio volume must be between 0 and 1")}}
 func configureInput(_ p:GameProfile)throws{guard ["Automatic","Keyboard"].contains(p.controller) else{throw AkitoStationError.message("Unsupported controller selection")}}
 func saveState(_ u:URL)throws{guard arm_state(u.path,1) != 0 else{throw AkitoStationError.message("Runtime could not serialize this game")}}
 func loadState(_ u:URL)throws{guard arm_state(u.path,0) != 0 else{throw AkitoStationError.message("No compatible save state")}}
 func readRuntimeLogs(_ u:URL)throws->String{String(try String(contentsOf:u).suffix(16000))}
 func reportCapabilities()->RuntimeCapabilities{RuntimeCapabilities()}
 func reportGameStatus()->RuntimeGameStatus{RuntimeGameStatus(state:state,frames:arm_frames(),error:state=="failed" ? String(cString:arm_error()):nil)}
}
