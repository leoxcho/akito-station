import SwiftUI
import AkitoStationCore
import GameController
import ImageIO

@MainActor final class LibraryStore:ObservableObject {
 @Published var games:[Game]=[]{didSet{gamesRevision+=1;refreshVisible()}};@Published var storage:StorageConfiguration?;@Published var message:String?;@Published var busy=false;@Published var activity="Ready";@Published var runtimes:[RuntimeManifest]=[];@Published var selected:Game?;@Published var controllerName="Keyboard";@Published var search=""{didSet{refreshVisible()}};@Published var filter="all"{didSet{refreshVisible()}};@Published var sort="Title"{didSet{refreshVisible()}};@Published var assistantLog="Akito Station Assistant uses deterministic diagnostics. Successful launches never wait for a model.";@Published var systemProfiles:[String:GameProfile]=[:]
 private var gameProfileErrors:[String:String]=[:]
 private var cachedGameProfiles:[String:GameProfile]=[:]
 private var selectedRuntimeVersions:[String:String]=[:]
 private var loadRevision=0
 @Published var damagedRuntimes:[RuntimeManager.Damage]=[]
 @Published var missingRuntime:Platform?
 @Published var runtimeConsole:Platform?
 @Published var runtimeRemoval:String?
 @Published var runtimeSources:[RuntimeSource]=[]
 @Published var runtimeUpdateStatus:[String:String]=[:]
 @Published var releaseBrowser:RuntimeReleaseBrowser?
 @Published var controllerBindings=ControllerBindings()
 @Published var scrapingArtwork=false
 @Published var artworkProgress=""
 private var artworkTask:Task<Void,Never>?
 var children:[String:Process]=[:]
 let preferenceURL:URL
 init(loadLibrary:Bool=true){
 let args=CommandLine.arguments
 preferenceURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AkitoStationPublic/preferences.json")
 guard loadLibrary else{return}
 do {if FileManager.default.fileExists(atPath:preferenceURL.path){storage=try JSONStore.read(StorageConfiguration.self,from:preferenceURL)}else{let root=preferenceURL.deletingLastPathComponent().appendingPathComponent("Data");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);storage=StorageConfiguration(root:Location(root));try savePreferences()};busy=true;Task{defer{busy=false};do{try await reloadAsync();try seedRuntimes()}catch{message=error.localizedDescription}}}catch{message=error.localizedDescription}
 GCController.startWirelessControllerDiscovery(completionHandler:nil)
 NotificationCenter.default.addObserver(forName:.GCControllerDidConnect,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.refreshControllers()}}
 NotificationCenter.default.addObserver(forName:.GCControllerDidDisconnect,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.refreshControllers()}}
 refreshControllers()
 }
 func refreshControllers(){controllerName=GCController.controllers().first?.vendorName ?? "Keyboard";for c in GCController.controllers(){c.extendedGamepad?.buttonA.pressedChangedHandler={[weak self]_,_,pressed in if pressed{Task{@MainActor in guard let self=self,self.children.isEmpty,!self.busy,NSApp.isActive,let game=self.selected ?? self.visible.first else{return};self.play(game)}}};c.extendedGamepad?.dpad.valueChangedHandler={[weak self]_,x,y in Task{@MainActor in guard let self=self,self.children.isEmpty,!self.busy,NSApp.isActive else{return};let list=self.visible;guard !list.isEmpty else{return};let current=list.firstIndex(where:{$0.id==self.selected?.id}) ?? 0;let step=(x>0.5 || y < -0.5) ? 1 : ((x < -0.5 || y>0.5) ? -1:0);if step != 0{self.selected=list[max(0,min(list.count-1,current+step))]}}}}}
 @Published private var visibleGames:[Game]=[]
 private var gamesRevision=0
 private let presentationIndex=LibraryPresentationIndex()
 private var visibleRevision=0
 private var visibleTask:Task<Void,Never>?
 var visible:[Game]{visibleGames}
 private func refreshVisible(){
  visibleRevision+=1;let revision=visibleRevision,libraryRevision=gamesRevision,source=games,query=search,category=filter,order=sort
  visibleTask?.cancel()
  visibleTask=Task{
   guard let list=try? await presentationIndex.visible(source,revision:libraryRevision,query:query,category:category,order:order),!Task.isCancelled,visibleRevision==revision else{return};visibleGames=list
  }
 }
 func reloadAsync()async throws {
  guard let configuration=storage else{throw AkitoStationError.message("Choose storage in Settings")}
  loadRevision+=1;let revision=loadRevision
  let snapshot=try await LibrarySnapshotLoader.load(configuration)
  guard loadRevision==revision,storage?.root==configuration.root,storage?.overrides==configuration.overrides else{return}
  gameProfileErrors=snapshot.profileErrors;selectedRuntimeVersions=snapshot.selections;cachedGameProfiles=snapshot.profiles;runtimeSources=snapshot.sources;games=snapshot.games;systemProfiles=snapshot.systems;runtimes=snapshot.inventory.manifests;damagedRuntimes=snapshot.inventory.damaged;controllerBindings=snapshot.controllers

 }
 func directory(_ k:StorageKind)throws->URL{guard let s=storage else{throw AkitoStationError.message("Choose storage in Settings")};return try s.directory(k)}
 func savePreferences()throws{guard let s=storage else{return};try FileManager.default.createDirectory(at:preferenceURL.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONStore.write(s,to:preferenceURL)}
 func reload()throws {Task{busy=true;defer{busy=false};do{try await reloadAsync()}catch{message=error.localizedDescription}}}
 func currentRuntimeVersion(_ id:String)->String{selectedRuntimeVersions[id] ?? ""}
 func runtimeSummary(_ id:String,version:String?=nil)->RuntimeManifest? {
  let candidates=runtimes.filter{runtime in runtime.id==id && runtime.validated && !damagedRuntimes.contains(where:{$0.engine==id && $0.version==runtime.version})}
  if let version{return candidates.first{$0.version==version}}
  return candidates.first{$0.version==selectedRuntimeVersions[id]} ?? candidates.first
 }

 func saveControllers(){attempt{try controllerBindings.validate();try JSONStore.write(controllerBindings,to:directory(.controllers).appendingPathComponent("bindings.json"));activity="Controller mappings saved"}}
 func persist()throws{
  guard let configuration=storage else{throw AkitoStationError.message("Choose storage in Settings")}
  LibraryPersistence.submit(games,configuration:configuration){[weak self] error in if let error{Task{@MainActor in self?.message="Library could not be saved: "+error.localizedDescription}}}
 }
 func scan(){guard let locations=storage?.libraries,!busy else{return};busy=true;activity="Indexing game libraries…";Task{do{let result=try await Task.detached(priority:.userInitiated){try LibraryScanner.scan(locations)}.value;games=LibraryScanner.merge(result,existing:games);try persist();activity="\(games.count) games indexed"}catch{message=error.localizedDescription;activity="Scan stopped; existing index preserved"};busy=false}}
 func chooseDirectory()->URL?{let p=NSOpenPanel();p.canChooseFiles=false;p.canChooseDirectories=true;p.canCreateDirectories=true;p.prompt="Choose";return p.runModal() == .OK ? p.url:nil}
 func addLibrary(){guard let u=chooseDirectory() else{return};if storage?.libraries.contains(where:{$0.path==u.path})==false{storage?.libraries.append(Location(u));attempt{try savePreferences()};scan()}}
 func setLocation(_ kind:StorageKind?){guard let u=chooseDirectory() else{return};attempt{if let k=kind{storage?.overrides[k.rawValue]=Location(u)}else{storage?.root=Location(u)};try savePreferences();try reload();try seedRuntimes()}}
 var canResetSettings:Bool{!busy && !scrapingArtwork && children.isEmpty}
 func resetStorage(_ kind:StorageKind? = nil,all:Bool=false){
  guard canResetSettings else{message="Stop games and wait for current work before resetting settings.";return}
  attempt{
   guard var next=storage else{return}
   let defaults=try SettingsReset.defaultStorage(preferences:preferenceURL)
   if all{next=defaults}else if let kind{next.overrides.removeValue(forKey:kind.rawValue)}else{next.root=defaults.root}
   if FileManager.default.fileExists(atPath:preferenceURL.path){try FileManager.default.copyItem(at:preferenceURL,to:preferenceURL.appendingPathExtension("before-reset-"+UUID().uuidString))}
   try JSONStore.write(next,to:preferenceURL);storage=next;selected=nil
   try reload();try seedRuntimes();activity="Storage locations reset. Existing files remain in their original locations."
  }
 }
 func resetAllSettings(){
  guard canResetSettings else{message="Stop games and wait for current work before resetting settings.";return}
  attempt{
   guard let current=storage else{return}
   let defaults=try SettingsReset.defaultStorage(preferences:preferenceURL)
   let files=try SettingsReset.configurationFiles(storage:current)+SettingsReset.configurationFiles(storage:defaults)
   try SettingsReset.archive(files)
   UserDefaults.standard.removeObject(forKey:"disableArtworkDownloads")
   UserDefaults.standard.removeObject(forKey:"runtimeUpdateChannel")
   search="";filter="all";sort="Title";runtimeUpdateStatus=[:];releaseBrowser=nil
   resetStorage(all:true)
  }
 }
 func migrateRoot(){guard let parent=chooseDirectory(),let old=storage else{return};let destination=parent.appendingPathComponent("Akito Station Data \(Int(Date().timeIntervalSince1970))");busy=true;Task{do{try await Task.detached{try StorageMover.copyVerified(from:old.root.resolve(),to:destination)}.value;storage?.root=Location(destination);try savePreferences();try reload();activity="Data moved and verified. Original retained at \(old.root.path)."}catch{message=error.localizedDescription};busy=false}}
 func attempt(_ work:()throws->Void){do{try work()}catch{message=error.localizedDescription}}
 func favorite(_ game:Game){if let i=games.firstIndex(where:{$0.id==game.id}){games[i].favorite.toggle();selected=games[i];attempt{try persist()}}}
 func profile(_ game:Game)throws->GameProfile {
  if let error=gameProfileErrors[game.id]{throw AkitoStationError.message("Game profile is damaged; original and backup preserved: "+error)}
  var p=cachedGameProfiles[game.id] ?? systemProfiles[game.platform.rawValue] ?? GameProfile()
  let core=RuntimeCatalog.selected(platform:game.platform,system:systemProfiles[game.platform.rawValue]?.options["arm.runtime.engine"],game:p.options["arm.runtime.override"],installed:runtimes)
  if let pinned=p.options["arm.runtime.engine"],pinned != core {p.knownGoodRuntime=nil;p.verifiedAt=nil}
  p.options=(systemProfiles[game.platform.rawValue]?.options ?? [:]).merging(p.options){_,value in value}
  p.options["arm.runtime.engine"]=core
  if let version=p.knownGoodRuntime,let core=core,(!runtimes.contains(where:{$0.id==core && $0.version==version}) || damagedRuntimes.contains(where:{$0.engine==core && $0.version==version})){p.knownGoodRuntime=nil;p.verifiedAt=nil}
  return p
 }
 func engine(_ game:Game)->String? {(try? profile(game))?.options["arm.runtime.engine"]}

 func saveProfile(_ p:GameProfile,game:Game)throws{let u=try directory(.profiles).appendingPathComponent(game.id+".json");if FileManager.default.fileExists(atPath:u.path){try Data(contentsOf:u).write(to:u.appendingPathExtension("previous"),options:.atomic)};try JSONStore.write(p,to:u);cachedGameProfiles[game.id]=p;gameProfileErrors.removeValue(forKey:game.id)}
 func rollbackProfile(_ game:Game){attempt{let u=try directory(.profiles).appendingPathComponent(game.id+".json");let data=try Data(contentsOf:u.appendingPathExtension("previous"));_=try JSONDecoder().decode(GameProfile.self,from:data);try data.write(to:u,options:.atomic);cachedGameProfiles[game.id]=try JSONDecoder().decode(GameProfile.self,from:data);activity="Previous profile restored"}}
 func engine(_ platform:Platform)->String?{EmulatorEngines.selected(for:platform,choice:systemProfiles[platform.rawValue]?.options["arm.runtime.engine"],installed:runtimes)}
 func switchEngine(_ choice:String,for platform:Platform){
  guard !busy,!hasRunningRuntime(engine(platform) ?? ""),!hasRunningRuntime(choice),EmulatorEngines.choices(for:platform,installed:runtimes).contains(choice),let configuration=storage else{return}
  busy=true
  var profile=systemProfiles[platform.rawValue] ?? GameProfile()
  profile.options["arm.runtime.engine"]=choice;profile.options["arm.settings.native"]=String(EmulatorSettings.files[choice] != nil);profile.knownGoodRuntime=nil;profile.verifiedAt=nil
  var updated=systemProfiles;updated[platform.rawValue]=profile
  Task{busy=true;defer{busy=false};do{
   try await Task.detached(priority:.userInitiated){_=try RuntimeManager(root:configuration.directory(.runtimes)).selected(choice);try JSONStore.write(updated,to:configuration.directory(.profiles).appendingPathComponent("systems.json"))}.value
   systemProfiles=updated
  }catch{message=error.localizedDescription}}
 }
 func showRuntimeFolder(_ id:String){
  guard !busy,let configuration=storage else{return};busy=true
  Task{defer{busy=false};do{let binary=try await Task.detached{try RuntimeManager(root:configuration.directory(.runtimes)).selected(id).1}.value;NSWorkspace.shared.activateFileViewerSelecting([binary])}catch{message=error.localizedDescription}}
 }
 func runtimeOperation(_ text:String,work:@escaping(RuntimeManager)throws->Void){
  guard !busy,let configuration=storage else{return};busy=true;activity=text
  Task{defer{busy=false};do{try await Task.detached(priority:.userInitiated){try work(RuntimeManager(root:configuration.directory(.runtimes)))}.value;try await reloadAsync();activity=text+" · complete"}catch{message=error.localizedDescription}}
 }
 func controllerProfileURL(_ platform:Platform)throws->URL{let folder=try directory(.controllers);let specific=folder.appendingPathComponent(platform.rawValue+".json");return FileManager.default.fileExists(atPath:specific.path) ? specific:folder.appendingPathComponent("bindings.json")}
 func saveSystem(_ p:GameProfile,_ platform:Platform){systemProfiles[platform.rawValue]=p;attempt{try JSONStore.write(systemProfiles,to:directory(.profiles).appendingPathComponent("systems.json"))}}
 func health(_ game:Game)->String {
  guard let core=engine(game),let manifest=runtimeSummary(core) else{return "No emulator installed · open Emulators"}
  return (manifest.externalLocation == nil ? "Managed Runtime":"External Runtime")+" · "+manifest.revision
 }

 func importedResources(_ game:Game)throws->[URL]{let root=try directory(.saves);let folder=try ConsoleResources.directory(root:root,platform:game.platform);return try ConsoleResources.entries(root:root,platform:game.platform).filter{!$0.installationRequired}.map{folder.appendingPathComponent($0.id).appendingPathComponent($0.filename)}}
 func resolveGame(_ game:Game)throws->URL{guard let l=storage?.libraries.first(where:{$0.path==game.libraryPath}) else{throw AkitoStationError.message("The game's library is no longer configured")};let url=try l.resolve().appendingPathComponent(game.relativePath);guard FileManager.default.isReadableFile(atPath:url.path) else{throw AkitoStationError.message("Game unavailable on the configured volume")};return url}
 func managedExternalApplication(_ platform:Platform)->URL?{guard let root=try? directory(.runtimes) else{return nil};return try? ExternalEmulator.managedApplication(platform,root:root)}
 func hasRunningRuntime(_ core:String)->Bool{
 if let manifest=runtimeSummary(core),RuntimeCatalog.definition(core)?.desktop==true || manifest.custom != nil,let base=try? (manifest.externalLocation?.resolve() ?? directory(.runtimes).appendingPathComponent(core+"/"+manifest.version)) {
  let binary=base.appendingPathComponent(manifest.library)
  let bundle=binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  if NSWorkspace.shared.runningApplications.contains(where:{$0.bundleURL?.resolvingSymlinksInPath()==bundle.resolvingSymlinksInPath()}){return true}
 }

 if let root=try? directory(.runtimes).appendingPathComponent(core).resolvingSymlinksInPath(),NSWorkspace.shared.runningApplications.contains(where:{$0.bundleURL?.resolvingSymlinksInPath().path.hasPrefix(root.path+"/")==true}){return true}
 return children.keys.contains{id in games.first{$0.id==id}.map{engine($0)==core} ?? false}}
 func openExternal(_ platform:Platform,game:Game?=nil){attempt{
 guard let name=ExternalEmulator.name(platform),let app=managedExternalApplication(platform) else{throw AkitoStationError.message("Install the emulator using Add installed emulator in this console’s settings first.")}
 let config=NSWorkspace.OpenConfiguration();config.activates=true
 if let game=game {
  if NSWorkspace.shared.runningApplications.contains(where:{$0.bundleURL?.standardizedFileURL==app.standardizedFileURL}){throw AkitoStationError.message("Quit \(name) before launching another game from Akito Station, or select the game in its existing window.")}
  config.arguments=try ExternalEmulator.arguments(platform,game:resolveGame(game))
 }
 NSWorkspace.shared.openApplication(at:app,configuration:config){[weak self] _,error in
  Task{@MainActor in guard let self=self else{return};if let error=error{self.message=error.localizedDescription;return}
   self.activity="Opened \(game?.title ?? name) in \(name)"
   if let game=game,let i=self.games.firstIndex(where:{$0.id==game.id}){self.games[i].lastPlayed=Date();self.attempt{try self.persist()}}
  }
 }
 }}
 func play(_ game:Game){
  guard !busy,let core=engine(game) else{missingRuntime=game.platform;return}
  do {
   let root=try directory(.runtimes),version=try profile(game).knownGoodRuntime
   busy=true;activity="Validating emulator…"
   Task{do{let runtime=try await Task.detached(priority:.userInitiated){try RuntimeManager(root:root).selected(core,version:version)}.value;busy=false;playValidated(game,core:core,runtime:runtime)}catch{busy=false;message=error.localizedDescription}}
  }catch{message=error.localizedDescription}
 }
 private func playValidated(_ game:Game,core:String,runtime:(RuntimeManifest,URL)){
 if let custom=runtime.0.custom {
  if custom.effectiveGameLaunchMethod == .openDocument {launchDocument(game,engine:core,binary:runtime.1,custom:custom)}else{startGame(game)}
  return
 }
 if runtime.0.capabilities.contains("startupBlocked"){message="This emulator cannot start on this Mac.";return}
 if RuntimeCatalog.definition(core)?.desktop==true && (runtime.0.externalLocation != nil || ["eden","vita3k","shadps4","ryujinx","azahar","dolphin_app","flycast"].contains(core)){launchDesktop(game,engine:core,binary:runtime.1);return}

 guard children[game.id]==nil else{return}
 guard let core=engine(game),ManagedLaunch.engines.contains(core) else{startGame(game);return}
 guard !children.keys.contains(where:{id in games.first(where:{$0.id==id}).map{engine($0)==core} ?? false}) else{message="Stop the running \(game.platform.title) game before starting another session.";return}
 guard !busy else{return};busy=true;activity="Preparing \(game.title)… first import may take several minutes"
 Task {defer{busy=false};do{
 let rom=try resolveGame(game),profile=try profile(game)
 let runtimeRoot=try directory(.runtimes)
 let (_,binary)=try await Task.detached{try RuntimeManager(root:runtimeRoot).selected(core,version:profile.knownGoodRuntime)}.value
 let data=try directory(.saves).appendingPathComponent("Systems/"+core),cache=try directory(.caches).appendingPathComponent(core)
 let launch=try await Task.detached(priority:.userInitiated){try ManagedLaunch(engine:core,binary:binary,game:rom,profile:profile,data:data,caches:cache)}.value
 guard let configuration=storage else{return}
 let ready=try await Task.detached{let manifest=try RuntimeManager(root:runtimeRoot).selected(core,version:profile.knownGoodRuntime).0;return (manifest,try Self.prepareSystem(configuration,game:game,core:core,binary:binary,custom:manifest.custom != nil))}.value
 startGameValidated(game,managed:launch,pair:(ready.0,binary),system:ready.1)
 }catch{message=error.localizedDescription;activity="Preparation failed"}}
 }
 nonisolated private static func prepareSystem(_ configuration:StorageConfiguration,game:Game,core:String,binary:URL,custom:Bool)throws->URL? {
  if custom{return nil}
  let saves=try configuration.directory(.saves),folder=try ConsoleResources.directory(root:saves,platform:game.platform)
  let imported=try ConsoleResources.entries(root:saves,platform:game.platform).filter{!$0.installationRequired}.map{folder.appendingPathComponent($0.id).appendingPathComponent($0.filename)}
  return try SystemResourceRouter.prepare(core:core,source:configuration.directory(.firmware),cache:configuration.directory(.caches),runtime:binary,imported:imported)
 }
 func startGame(_ game:Game,managed:ManagedLaunch?=nil){
  guard !busy,children[game.id]==nil,let core=engine(game),let configuration=storage else{return}
  do{let version=try profile(game).knownGoodRuntime;busy=true
   Task{do{let ready=try await Task.detached(priority:.userInitiated){let pair=try RuntimeManager(root:configuration.directory(.runtimes)).selected(core,version:version);return (pair,try Self.prepareSystem(configuration,game:game,core:core,binary:pair.1,custom:pair.0.custom != nil))}.value;busy=false;startGameValidated(game,managed:managed,pair:ready.0,system:ready.1)}catch{busy=false;message=error.localizedDescription}}
  }catch{message=error.localizedDescription}
 }
 private func startGameValidated(_ game:Game,managed:ManagedLaunch?,pair:(RuntimeManifest,URL),system:URL?){guard children[game.id]==nil else{return};attempt{
 guard let core=engine(game) else{throw AkitoStationError.message("\(game.platform.title): native managed integration is not available in this build. See Systems for the required engine. No standalone emulator will be opened.")}
 try EmbeddedRuntime.requirePlayable(engine:core)
 let rom=try resolveGame(game);let profile=try profile(game);let manager=try RuntimeManager(root:directory(.runtimes));let (runtime,binary)=pair
 let log=try directory(.logs).appendingPathComponent(game.id+".log");FileManager.default.createFile(atPath:log.path,contents:Data("Akito Station runtime \(runtime.id) \(runtime.version)\n".utf8));let output=try FileHandle(forWritingTo:log);try output.seekToEnd()
 let process=Process()
 if let custom=runtime.custom {
  let launch=try ManagedLaunch(custom:custom,runtimeDirectory:manager.runtimeDirectory(runtime),game:rom)
  if game.platform == .switchConsole {let record=SwitchLaunchRecord(runtime:core,executable:binary.path,game:rom.path,arguments:launch.arguments);try JSONStore.write(record,to:log.deletingPathExtension().appendingPathExtension("launch.json"))}
  process.executableURL=binary;process.arguments=launch.arguments;process.environment=launch.environment;process.currentDirectoryURL=launch.workingDirectory
 }else{
 guard system != nil else{throw AkitoStationError.message("Runtime resources were not prepared")}
 let saves=try directory(.saves).appendingPathComponent(game.id);try FileManager.default.createDirectory(at:saves,withIntermediateDirectories:true)
 let states=try directory(.states).appendingPathComponent(game.id);try FileManager.default.createDirectory(at:states,withIntermediateDirectories:true)
 let launchProfiles=try directory(.caches).appendingPathComponent("launch-profiles");try FileManager.default.createDirectory(at:launchProfiles,withIntermediateDirectories:true);let profileURL=launchProfiles.appendingPathComponent(game.id+".json");try JSONStore.write(profile,to:profileURL)

 if core == "dolphin"{try FileManager.default.createDirectory(at:directory(.caches).appendingPathComponent("dolphin"),withIntermediateDirectories:true)}
 process.executableURL=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Akito Station Player.app/Contents/MacOS/AkitoStation");process.arguments=["--game",rom.path,"--core",binary.path,"--system",(system ?? URL(fileURLWithPath:"/")).path,"--saves",saves.path,"--states",states.path,"--screenshots",try directory(.screenshots).path,"--controller-profile",try controllerProfileURL(game.platform).path,"--profile",profileURL.path,"--title",game.title];if core == "dolphin"{let launch=try DolphinLaunch(binary:binary,game:rom,profile:profile,saves:saves,states:states,caches:directory(.caches).appendingPathComponent("dolphin"),screenshots:directory(.screenshots),bindings:controllerBindings,useGamepad:!GCController.controllers().isEmpty,nativeSettings:directory(.saves).appendingPathComponent("Systems/dolphin"));process.executableURL=binary;process.arguments=launch.arguments;process.environment=launch.environment};if let launch=managed{process.executableURL=binary;process.arguments=launch.arguments;process.environment=launch.environment;process.currentDirectoryURL=launch.workingDirectory};
 };process.standardOutput=output;process.standardError=output;let started=Date();let id=game.id
 process.terminationHandler={[weak self] p in try? output.close();Task{@MainActor in guard let self=self else{return};self.children.removeValue(forKey:id);if p.terminationStatus != 0,game.platform == .switchConsole {self.message="Switch runtime failed to launch the selected game (exit \(p.terminationStatus)). See \(log.path).";self.activity="Game launch failed"};if let i=self.games.firstIndex(where:{$0.id==id}){self.games[i].playSeconds += Date().timeIntervalSince(started);self.games[i].status=p.terminationStatus==0 ? "Session ended":"Runtime exited \(p.terminationStatus)";self.attempt{try self.persist()}}}}
 try process.run();children[id]=process;if let i=games.firstIndex(where:{$0.id==id}){games[i].lastPlayed=started;try persist()};activity="Playing \(game.title)"
 }}
 func seedRuntimes()throws{}

 func checkUpdates(){checkAllRuntimeUpdates()}

 func inspectResources(){busy=true;Task{do{let root=try directory(.firmware);let records=try await Task.detached{try ResourceScanner.inspect(root)}.value;try JSONStore.write(records,to:directory(.metadata).appendingPathComponent("resources.json"));assistantLog="\(records.count) supplied system resources indexed. Hashes saved in metadata/resources.json. Engine-specific validation remains necessary."}catch{message=error.localizedDescription};busy=false}}
}
extension LibraryStore {

}
extension LibraryStore {
 func migrateLocation(_ kind:StorageKind){guard let parent=chooseDirectory() else{return};attempt{let source=try directory(kind);let destination=parent.appendingPathComponent("Akito Station-\(kind.rawValue)-\(Int(Date().timeIntervalSince1970))");busy=true;Task{defer{busy=false};do{try await Task.detached{try StorageMover.copyVerified(from:source,to:destination)}.value;storage?.overrides[kind.rawValue]=Location(destination);try savePreferences();try reload();activity="\(kind.title) copied and verified; original retained"}catch{message=error.localizedDescription}}}}
}
extension LibraryStore {
 func cancelArtworkScrape(){artworkTask?.cancel()}
 func scrapeAllArtwork(){
 guard !scrapingArtwork else{return}
 let pending=games.filter{$0.artwork == nil || !FileManager.default.fileExists(atPath:$0.artwork!)}
 scrapingArtwork=true
 artworkProgress="Preparing \(pending.count) missing covers…"
 artworkTask=Task{
 defer{scrapingArtwork=false;artworkTask=nil}
 var added=0,unmatched=0,failed=0,completed=0
 for game in pending {
 if Task.isCancelled{break}
 artworkProgress="Scraping \(completed+1)/\(pending.count): \(game.title)"
 do{
 if let result=try await ArtworkCache.shared.scrape(game){
 let data=try await ArtworkCache.shared.download(result)
 try Task.checkCancellation()
 if let current=games.first(where:{$0.id==game.id}),current.artwork == nil || !FileManager.default.fileExists(atPath:current.artwork!){
 try await installArtwork(data,for:current,source:result.url.absoluteString);added+=1
 }
 }else{unmatched+=1}
 }catch{if Task.isCancelled{break};failed+=1}
 completed+=1
 }
 artworkProgress="\(Task.isCancelled ? "Cancelled" : "Finished"): \(added) covers added · \(unmatched) unmatched · \(failed) failed · \(completed)/\(pending.count) checked"
 }
 }
 func installArtwork(_ data:Data,for game:Game,source:String)async throws{
  guard data.count<=8*1024*1024,let configuration=storage else{throw AkitoStationError.message("Choose an image smaller than 8 MB")}
  let target=try await Task.detached(priority:.userInitiated){
   guard let image=CGImageSourceCreateWithData(data as CFData,nil),let thumbnail=CGImageSourceCreateThumbnailAtIndex(image,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{throw AkitoStationError.message("Choose a valid image")}
   let png=NSMutableData();guard let output=CGImageDestinationCreateWithData(png,"public.png" as CFString,1,nil) else{throw AkitoStationError.message("Cannot encode cover")}
   CGImageDestinationAddImage(output,thumbnail,nil);guard CGImageDestinationFinalize(output) else{throw AkitoStationError.message("Cannot encode cover")}
   let cache=try configuration.directory(.metadata).appendingPathComponent("artwork");try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
   let target=cache.appendingPathComponent(game.id+"-"+UUID().uuidString+".png");try (png as Data).write(to:target,options:.atomic)
   try JSONStore.write(["source":source,"game":game.title],to:target.appendingPathExtension("source.json"));return target
  }.value
  if let i=games.firstIndex(where:{$0.id==game.id}){games[i].artwork=target.path;try persist()}
 }
 func loadArtwork(_ game:Game)async {guard game.artwork==nil,!UserDefaults.standard.bool(forKey:"disableArtworkDownloads") else{return};do{let cache=try directory(.metadata).appendingPathComponent("artwork");if let image=try await ArtworkCache.shared.fetch(game,cache:cache),let i=games.firstIndex(where:{$0.id==game.id}),games[i].artwork==nil{games[i].artwork=image.path;try persist()}}catch{/* Artwork is optional; offline libraries remain usable. */}}
}
