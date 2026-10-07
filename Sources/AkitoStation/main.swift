import SwiftUI
import AkitoStationCore
import RetroHost

BuildEdition.migrateLegacyPreferences()
let args=CommandLine.arguments
if (Bundle.main.bundleIdentifier?.hasSuffix(".player") == true) && !args.contains("--game") { exit(0) }
#if AKITO_DEVELOPER
if args.contains("--runtime-manager-self-test") {
 Task{@MainActor in do{try await runtimeManagerSelfTest();print("Developer runtime workflow checks passed");exit(0)}catch{fputs("\(error)\n",stderr);exit(2)}}
 dispatchMain()
}
if args.contains("--settings-audit"),let i=args.firstIndex(of:"--saves"),i+1<args.count {
 do{
  var report:[String:Any]=[:];let saves=URL(fileURLWithPath:args[i+1])
  for engine in EmulatorSettings.files.keys.sorted(){
   var fields:[String]=[];let files=try EmulatorSettings.documents(engine:engine,data:saves.appendingPathComponent("Systems/"+engine))
   for file in files{let doc=try NativeSettingsDocument(text:String(contentsOf:file),format:file.pathExtension);fields += doc.fields.map{$0.section+" / "+$0.key}}
   report[engine]=["files":files.count,"fields":fields.count,"graphics":fields.filter{let v=$0.lowercased();return ["resolution","res_scale","surface_scale","vsync","v-sync","presentmode","allow_tearing","filter"].contains{v.contains($0)}}]
  }
  print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
 }catch{fputs("\(error)\n",stderr);exit(2)};exit(0)
}
#endif
if args.contains("--core-options") {
 func arg(_ key:String)->String{guard let i=args.firstIndex(of:key),i+1<args.count else{return ""};return args[i+1]}
 guard arm_query_options(arg("--core")) != 0 else{fputs(String(cString:arm_error())+"\n",stderr);exit(3)}
 let rows=(0..<arm_option_count()).compactMap{i -> CoreOption? in
  CoreOption(key:String(cString:arm_option_key(i)),definition:String(cString:arm_option_definition(i)))
 }
 do{try JSONStore.write(rows,to:URL(fileURLWithPath:arg("--output")));print("Registered \(rows.count) core options; no game loaded")}catch{fputs("\(error)\n",stderr);exit(2)}
 exit(0)
}
if args.contains("--verify-runtime-core"),let i=args.firstIndex(of:"--core"),i+1<args.count {if arm_inspect(args[i+1]) != 0{print("Native libretro ABI verified; game boot not tested");exit(0)};fputs(String(cString:arm_error())+"\n",stderr);exit(3)}
#if AKITO_DEVELOPER
if args.contains("--inspect-core"),let i=args.firstIndex(of:"--core"),i+1<args.count {if arm_inspect(args[i+1]) != 0{print("Native libretro ABI verified; game boot not tested");exit(0)};fputs(String(cString:arm_error())+"\n",stderr);exit(3)}
if args.contains("--probe") {
 func arg(_ key:String)->String{guard let i=args.firstIndex(of:key),i+1<args.count else{return ""};return args[i+1]}
 let core=arg("--core"),rom=arg("--rom"),output=arg("--output");let folder=URL(fileURLWithPath:output)
 do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}catch{fputs("\(error)\n",stderr);exit(2)}
 let testProfile=(try? JSONStore.read(GameProfile.self,from:URL(fileURLWithPath:arg("--profile")))) ?? GameProfile()
 let system=arg("--system").isEmpty ? folder.path:arg("--system")
 guard arm_load(core,rom,system,folder.path,testProfile.coreOptions) != 0 else{fputs("\(String(cString:arm_error()))\n",stderr);exit(3)}
 let count=max(1,Int(arg("--frames")) ?? 180);let deadline=Date().addingTimeInterval(90);var ready=false
 while Date()<deadline{arm_run();Thread.sleep(forTimeInterval:1.0/arm_fps());if arm_frames()>=UInt64(count),let pixels=arm_pixels(){let n=Int(arm_width()*arm_height());if n>1{let first=pixels[0];ready=(1..<n).contains{pixels[$0] != first};if ready{break}}}}
 if !ready{fputs("No nonblank frame before boot deadline\n",stderr);exit(4)}
 let frames=arm_frames();let w=Int(arm_width()),h=Int(arm_height());var unique=Set<UInt32>();if let p=arm_pixels(){for i in 0..<(w*h){unique.insert(p[i])};let data=Data(bytes:p,count:w*h*4);try? data.write(to:folder.appendingPathComponent("frame.bgra"))}
 let state=folder.appendingPathComponent("probe.state");let saved=arm_state(state.path,1);let restored=saved != 0 ? arm_state(state.path,0):0
 let report:[String:Any] = ["core":String(cString:arm_core_name()),"frames":frames,"width":w,"height":h,"uniqueColors":unique.count,"saveState":saved != 0,"loadState":restored != 0,"rom":rom]
 if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:folder.appendingPathComponent("report.json"));print(String(decoding:data,as:UTF8.self))};arm_stop();exit(frames>0 && unique.count>1 && restored != 0 ? 0:4)
}
if args.contains("--configure") {
 func arg(_ key:String)->String?{guard let i=args.firstIndex(of:key),i+1<args.count else{return nil};return args[i+1]}
 do {
 guard let rootPath=arg("--data-root"),let library=arg("--library") else{throw AkitoStationError.message("--data-root and --library are required")}
 let root=URL(fileURLWithPath:rootPath);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 let preferences=arg("--config").map{URL(fileURLWithPath:$0)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AkitoStation/preferences.json")
 guard !FileManager.default.fileExists(atPath:preferences.path) else{throw AkitoStationError.message("Preferences already exist; use Settings to change them")}
 var storage=StorageConfiguration(root:Location(root));storage.libraries=[Location(URL(fileURLWithPath:library))]
 if let firmware=arg("--firmware"){storage.overrides["firmware"]=Location(URL(fileURLWithPath:firmware))}
 let games=try LibraryScanner.scan(storage.libraries);try JSONStore.write(games,to:storage.directory(.metadata).appendingPathComponent("library.json"))
 try FileManager.default.createDirectory(at:preferences.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONStore.write(storage,to:preferences)
 print("Configured \(games.count) games. Preferences: \(preferences.path)")
 }catch{fputs("\(error)\n",stderr);exit(1)};exit(0)
}
if args.contains("--rescan") {
 do {
 let preferences:URL
 if let i=args.firstIndex(of:"--config"),i+1<args.count{preferences=URL(fileURLWithPath:args[i+1])}else{preferences=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AkitoStation/preferences.json")}
 let storage=try JSONStore.read(StorageConfiguration.self,from:preferences)
 let db=try storage.directory(.metadata).appendingPathComponent("library.json")
 let previous=(try? JSONStore.read([Game].self,from:db)) ?? []
 let games=LibraryScanner.merge(try LibraryScanner.scan(storage.libraries),existing:previous)
 try JSONStore.write(games,to:db)
 print("Indexed \(games.count) games; PS3: \(games.filter{$0.platform == .ps3}.count)")
 }catch{fputs("\(error)\n",stderr);exit(1)};exit(0)
}
if args.contains("--index") {
 func arg(_ key:String)->String{guard let i=args.firstIndex(of:key),i+1<args.count else{return ""};return args[i+1]}
 do{let games=try LibraryScanner.scan([Location(URL(fileURLWithPath:arg("--library")))]);try JSONStore.write(games,to:URL(fileURLWithPath:arg("--output")));print("Indexed \(games.count) games")}catch{fputs("\(error)\n",stderr);exit(1)};exit(0)
}
#endif
final class AppDelegate:NSObject,NSApplicationDelegate {
 var player:Player?
 func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)}
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  LibraryPersistence.flush{DispatchQueue.main.async{sender.reply(toApplicationShouldTerminate:true)}}
  return .terminateLater
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{CommandLine.arguments.contains("--game")}
 func applicationWillTerminate(_ notification:Notification){MainActor.assumeIsolated{player?.stop()}}
}
struct AkitoStationApplication:App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
 @StateObject var store=LibraryStore(loadLibrary:!args.contains("--game"))
 @State var player:Player?
 var body:some Scene{WindowGroup{if args.contains("--game"){Group{if let player=player{PlayerView(player:player)}else{ProgressView("Starting runtime…")}}.onAppear{if player==nil{let p=Player(arguments:args);player=p;delegate.player=p}}}else{LibraryView().environmentObject(store)}}.windowStyle(.hiddenTitleBar).defaultSize(width:1200,height:800)
 Settings{AkitoStationSettings().environmentObject(store).frame(width:900,height:650)}
 }
}
AkitoStationApplication.main()
