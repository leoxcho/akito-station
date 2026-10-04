import SwiftUI
import AkitoStationCore
import RetroHost

BuildEdition.migrateLegacyPreferences()
let args=CommandLine.arguments
if (Bundle.main.bundleIdentifier?.hasSuffix(".player") == true) && !args.contains("--game") { exit(0) }
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
final class AppDelegate:NSObject,NSApplicationDelegate {
 var player:Player?
 func applicationDidFinishLaunching(_ notification:Notification){NSApp.applicationIconImage=AppLogo.selected.image;NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)}
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
 var body:some Scene{WindowGroup{if args.contains("--game"){Group{if let player=player{PlayerView(player:player)}else{ProgressView("Starting runtime…")}}.onAppear{if player==nil{let p=Player(arguments:args);player=p;delegate.player=p}}}else{LibraryView().environmentObject(store).task { await PremiumStore.shared.start() }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await PremiumStore.shared.refresh() } }}}.windowStyle(.hiddenTitleBar).defaultSize(width:1200,height:800)
 Settings{AkitoStationSettings().environmentObject(store).frame(width:900,height:650)}
 }
}
AkitoStationApplication.main()
