import SwiftUI
import AkitoStationCore

extension LibraryStore {
 func launchDocument(_ game:Game,engine:String,binary:URL,custom:CustomEmulatorConfiguration){attempt{
  guard !hasRunningRuntime(engine) else{throw AkitoStationError.message("Quit this emulator before launching another game.")}
  let rom=try resolveGame(game)
  var app=binary.deletingLastPathComponent()
  while app.pathExtension != "app",app.path != "/"{app=app.deletingLastPathComponent()}
  guard app.pathExtension == "app",Bundle(url:app)?.executableURL?.resolvingSymlinksInPath()==binary.resolvingSymlinksInPath() else{throw AkitoStationError.message("Open game as document requires the registered application's main executable. Relink the app or configure direct game arguments.")}
  let configuration=NSWorkspace.OpenConfiguration();configuration.activates=true
  guard custom.workingDirectory.isEmpty else{throw AkitoStationError.message("Open-document launches use the application working directory. Clear the custom working directory or choose command-line arguments.")}
  let manager=try RuntimeManager(root:directory(.runtimes))
  let manifest=try manager.selected(engine,version:try profile(game).knownGoodRuntime).0
  let launch=try ManagedLaunch(custom:custom,runtimeDirectory:manager.runtimeDirectory(manifest),game:rom)
  configuration.arguments=launch.arguments;configuration.environment=launch.environment
  let log=try directory(.logs).appendingPathComponent(game.id+"-launch.json")
  try JSONStore.write(["runtime":engine,"executable":binary.path,"method":"openDocument","game":rom.path],to:log)
  activity="Sending \(game.title) to \(custom.name)…"
  NSWorkspace.shared.open([rom],withApplicationAt:app,configuration:configuration){[weak self] _,error in Task{@MainActor in
   guard let self else{return}
   if let error {self.message="Direct game handoff failed: "+error.localizedDescription;self.activity="Game launch failed";return}
   self.activity="Game sent to \(custom.name): \(game.title)"
   if let i=self.games.firstIndex(where:{$0.id==game.id}){self.games[i].lastPlayed=Date();self.attempt{try self.persist()}}
  }}
 }}
 func launchDesktop(_ game:Game,engine:String,binary:URL){attempt{
  guard !hasRunningRuntime(engine) else{throw AkitoStationError.message("Quit this emulator before launching another game.")}
  var app=binary.deletingLastPathComponent()
  while app.pathExtension != "app",app.path != "/"{app=app.deletingLastPathComponent()}
  guard app.pathExtension=="app" else{throw AkitoStationError.message("Registered application is unavailable")}
  if Bundle(url:app)?.executableURL?.resolvingSymlinksInPath() != binary.resolvingSymlinksInPath(){launchRelinkedExecutable(game,engine:engine,binary:binary);return}
  let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true;configuration.activates=true
  configuration.arguments=try RuntimeCatalog.desktopArguments(engine:engine,platform:game.platform,game:resolveGame(game))
  NSWorkspace.shared.openApplication(at:app,configuration:configuration){[weak self] _,error in Task{@MainActor in
   guard let self=self else{return};if let error=error{self.message=error.localizedDescription;return}
   self.activity="Game sent: \(game.title) to \(RuntimeCatalog.definition(engine)?.name ?? engine)"
   if let index=self.games.firstIndex(where:{$0.id==game.id}){self.games[index].lastPlayed=Date();self.attempt{try self.persist()}}
  }}
 }}
 func launchRelinkedExecutable(_ game:Game,engine:String,binary:URL){attempt{
  guard children[game.id]==nil,!hasRunningRuntime(engine) else{throw AkitoStationError.message("Quit this emulator before launching another game")}
  let process=Process();process.executableURL=binary;process.arguments=try RuntimeCatalog.desktopArguments(engine:engine,platform:game.platform,game:resolveGame(game));process.currentDirectoryURL=binary.deletingLastPathComponent()
  let log=try directory(.logs).appendingPathComponent(game.id+"-relinked.log");FileManager.default.createFile(atPath:log.path,contents:nil);let output=try FileHandle(forWritingTo:log);process.standardOutput=output;process.standardError=output
  let started=Date()
  process.terminationHandler={[weak self] child in try? output.close();Task{@MainActor in guard let self else{return};self.children.removeValue(forKey:game.id);if let i=self.games.firstIndex(where:{$0.id==game.id}){self.games[i].playSeconds+=Date().timeIntervalSince(started);self.games[i].status="Runtime exited "+String(child.terminationStatus);self.attempt{try self.persist()}}}}
  do{try process.run()}catch{try? output.close();throw error};children[game.id]=process
  if let i=games.firstIndex(where:{$0.id==game.id}){games[i].lastPlayed=started;try persist()};activity="Playing "+game.title+" in relinked "+engine
 }}
 func addExistingRuntime(_ definition:RuntimeDefinition,platform:Platform,managed:Bool=false,chooseExecutable:Bool=false){
  guard !busy,!hasRunningRuntime(definition.id),definition.platforms.contains(platform) else{return}
  let panel=NSOpenPanel();panel.title=managed ? "Install a managed copy":"Choose Existing Installation";panel.allowedFileTypes=(definition.desktop || definition.id=="dolphin") ? ["app"]:["dylib"];panel.canChooseDirectories=false
  guard panel.runModal() == .OK,let input=panel.url else{return}
  var executableOverride=""
  if input.pathExtension=="app",chooseExecutable || Bundle(url:input)?.executableURL.map({!FileManager.default.isExecutableFile(atPath:$0.path)}) != false {
   let executable=NSOpenPanel();executable.title="Choose the replacement executable inside this app";executable.canChooseDirectories=false;executable.directoryURL=input.appendingPathComponent("Contents/MacOS")
   guard executable.runModal() == .OK,let selected=executable.url else{return}
   let base=input.resolvingSymlinksInPath(),file=selected.resolvingSymlinksInPath()
   guard file.path.hasPrefix(base.path+"/") else{message="Choose an executable inside the selected app";return}
   executableOverride=String(file.path.dropFirst(base.path.count+1))
  }
  busy=true;activity=managed ? "Installing managed runtime…":"Registering external runtime…"
  Task{defer{busy=false};do{
   let root=try directory(.runtimes),log=try directory(.logs).appendingPathComponent("register-"+definition.id+".log"),host=Bundle.main.executableURL!
   let operation=Task.detached(priority:.userInitiated){try await RuntimeManager(root:root).importCatalog(input:input,definition:definition,platform:platform,managed:managed,host:host,log:log,executableOverride:executableOverride)}
   _=try await operation.value
   try await reloadAsync();busy=false;if engine(platform)==nil || !runtimes.contains(where:{$0.id==engine(platform) && $0.validated}){switchEngine(definition.id,for:platform)};activity=managed ? "Managed Runtime installed":"External Runtime registered; originals retained"
  }catch{message=error.localizedDescription;activity="Runtime was not registered"}}
 }
 func installOptionalRuntime(_ definition:RuntimeDefinition,platform:Platform){
  guard !busy,!hasRunningRuntime(definition.id) else{return}
  if let repo=definition.releaseRepository {
   busy=true;activity="Checking official releases…"
   Task{do{
    let releases=try await GitHubUpdates.releases(repository:repo)
    guard let release=releases.first else{throw AkitoStationError.message("No official release is currently available. Use the official website or choose an existing installation.")}
    let assets=release.assets.filter{$0.isMacCandidate && ["zip","dmg","gz","xz","7z"].contains(URL(fileURLWithPath:$0.name).pathExtension.lowercased())}
    busy=false
    let browser=RuntimeReleaseBrowser(name:definition.name,repository:repo,engine:definition.id,releases:releases)
    if assets.count==1,assets[0].name.lowercased().hasSuffix(".zip"){downloadRuntimeAsset(assets[0],release:release,browser:browser,install:true)}else{releaseBrowser=browser}
   }catch{busy=false;message=error.localizedDescription}}
  }else if definition.installation == .sourceBuild {
   busy=true;activity="Building \(definition.name) from official source…"
   Task{defer{busy=false};do{
    let tools=Bundle.main.resourceURL!.appendingPathComponent("Tools")
    var args=[tools.appendingPathComponent("manage-runtime.py").path,"build","--core",definition.id,"--root",try directory(.runtimes).path,"--work",try directory(.downloads).path,"--host",Bundle.main.executableURL!.path,"--abi-only","--activate"]
    if runtimes.contains(where:{$0.id==definition.id}) {let revision=try await GitHubUpdates.sourceRevision(repository:definition.officialSource);args += ["--revision",revision]}
    var environment=ProcessInfo.processInfo.environment;environment["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    let result=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/python3"),arguments:args,log:directory(.logs).appendingPathComponent("install-"+definition.id+".log"),timeout:3600,environment:environment)
    guard result.exitCode==0 else{throw AkitoStationError.message("Source installation failed. Install the required build tools or choose an existing core. Current runtime retained; see the install log.")}
    try await reloadAsync();busy=false;if engine(platform)==nil || !runtimes.contains(where:{$0.id==engine(platform) && $0.validated}){switchEngine(definition.id,for:platform)};activity="Installed · ABI checked · game untested"
   }catch{message=error.localizedDescription;activity="Installation failed"}}
  }else if let url=URL(string:definition.officialSource){NSWorkspace.shared.open(url)}
 }
 func checkOptionalUpdate(_ definition:RuntimeDefinition){
  guard !busy else{return}
  guard let repository=definition.releaseRepository ?? (definition.installation == .sourceBuild ? definition.officialSource:nil) else{runtimeUpdateStatus[definition.id]="Update through the official website, then register the updated installation.";return}
  busy=true;Task{defer{busy=false};do{
   if definition.installation == .sourceBuild {
    let revision=try await GitHubUpdates.sourceRevision(repository:repository)
    let current=runtimeSummary(definition.id)?.revision
    runtimeUpdateStatus[definition.id]="Latest Version: "+revision+(current==revision ? " · up to date":" · Update available");return
   }
   let latest=try await GitHubUpdates.releases(repository:repository).first
   guard let latest=latest else{runtimeUpdateStatus[definition.id]="No published release. Check the official source.";return}
   let current=runtimeSummary(definition.id)?.revision
   runtimeUpdateStatus[definition.id]="Latest Version: "+latest.tag_name+(current==latest.tag_name ? " · up to date":" · Update available")
  }catch{runtimeUpdateStatus[definition.id]=error.localizedDescription}}
 }
 func removeOptionalRuntime(_ id:String){
  guard !busy,!hasRunningRuntime(id),let configuration=storage else{message="Quit this emulator before removing it.";return}
  let registrations=runtimes.filter{$0.id==id && $0.externalLocation != nil},managed=runtimes.filter{$0.id==id && $0.externalLocation == nil}
  runtimeOperation("Removing runtime; preserving user files"){manager in
   let target=manager.root.appendingPathComponent(id).resolvingSymlinksInPath()
   for kind in [StorageKind.saves,.states,.firmware,.screenshots,.profiles,.controllers,.metadata] {
    let protected=try configuration.directory(kind).resolvingSymlinksInPath()
    guard target != protected,!protected.path.hasPrefix(target.path+"/"),!target.path.hasPrefix(protected.path+"/") else{throw AkitoStationError.message("Runtime storage overlaps user data; removal refused")}
   }
   for location in configuration.libraries {let library=try location.resolve().resolvingSymlinksInPath();guard target != library,!target.path.hasPrefix(library.path+"/"),!library.path.hasPrefix(target.path+"/") else{throw AkitoStationError.message("Runtime storage overlaps a game library; removal refused")}}
   if managed.isEmpty{for registration in registrations{try manager.unregister(id,version:registration.version)}}else{try manager.uninstall(id)}
  }
 }
}
