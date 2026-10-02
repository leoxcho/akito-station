import SwiftUI
import AkitoStationCore

struct RuntimeReleaseBrowser:Identifiable {
 let id=UUID();let name:String;let repository:String;let engine:String;let releases:[RuntimeRelease]
}
extension LibraryStore {
 func uninstallRuntime(_ id:String){removeOptionalRuntime(id)}
 func importEmulator(_ engine:String,for platform:Platform){
  guard !busy,ManagedLaunch.platforms(for:engine).contains(platform),!hasRunningRuntime(self.engine(platform) ?? "") else{return}
  let panel=NSOpenPanel();panel.title="Add \(engine) to \(platform.title)";panel.allowedFileTypes=["app"];panel.canChooseDirectories=false;panel.canChooseFiles=true
  guard panel.runModal() == .OK,let app=panel.url else{return}
  busy=true;activity="Importing \(engine) for \(platform.title)…"
  Task{defer{busy=false};do{
   guard let definition=RuntimeCatalog.definition(engine) else{throw AkitoStationError.message("Unknown emulator")}
   let root=try directory(.runtimes),log=try directory(.logs).appendingPathComponent("import-"+engine+".log"),host=Bundle.main.executableURL!
   _=try await Task.detached{try await RuntimeManager(root:root).importCatalog(input:app,definition:definition,platform:platform,managed:true,host:host,log:log)}.value
   try await reloadAsync();busy=false;if self.engine(platform)==nil || !runtimes.contains(where:{$0.id==self.engine(platform) && $0.validated}){switchEngine(engine,for:platform)};activity="Added \(engine) to \(platform.title) · game untested"
  }catch{message=error.localizedDescription;activity="Emulator import failed"}}
 }
 var installedEngines:[RuntimeManifest] {
  Dictionary(grouping:runtimes,by:{$0.id}).keys.sorted().compactMap{id in
   let versions=runtimes.filter{$0.id==id}
   let selected=try? RuntimeManager(root:directory(.runtimes)).selection(id).current
   return versions.first{$0.version==selected} ?? versions.first
  }
 }
 func removeRuntimeSource(_ source:RuntimeSource){attempt{
  let updated=runtimeSources.filter{$0.id != source.id}
  try JSONStore.write(updated,to:directory(.metadata).appendingPathComponent("runtime-sources.json"));runtimeSources=updated
 }}
 func checkAllRuntimeUpdates(channel:String="stable"){guard !busy else{return};busy=true
  let entries=installedEngines.compactMap{runtime -> (String,String,String)? in
   guard let definition=RuntimeCatalog.definition(runtime.id),let repository=definition.releaseRepository ?? (definition.installation == .sourceBuild ? definition.officialSource:nil) else{runtimeUpdateStatus[runtime.id]="Check the official website and register the updated installation.";return nil}
   return (runtime.id,repository,channel)
  }
  Task{defer{busy=false};for (id,repo,channel) in entries {
   do {let releases=try await GitHubUpdates.releases(repository:repo,channel:BuildEdition.isDeveloper ? channel : "stable");runtimeUpdateStatus[id]=releases.first.map{"Latest release: "+$0.tag_name} ?? "No published releases. Source builds are available for integrated cores."}
   catch{runtimeUpdateStatus[id]=error.localizedDescription}
  };assistantLog=entries.map{($0.0)+": "+(runtimeUpdateStatus[$0.0] ?? "")}.joined(separator:"\n")}
 }
 func browseRuntimeReleases(name:String,repository:String,engine:String,channel:String="stable",statusID:String){guard !busy else{return};busy=true
  Task{defer{busy=false};do{
   let releases=try await GitHubUpdates.releases(repository:repository,channel:BuildEdition.isDeveloper ? channel : "stable")
   guard !releases.isEmpty else{throw AkitoStationError.message("This repository has no published releases for the selected channel.")}
   runtimeUpdateStatus[statusID]="Latest release: "+releases[0].tag_name
   releaseBrowser=RuntimeReleaseBrowser(name:name,repository:repository,engine:engine,releases:releases)
  }catch{runtimeUpdateStatus[statusID]=error.localizedDescription;message=error.localizedDescription}}
 }
 func downloadRuntimeAsset(_ asset:ReleaseAsset,release:RuntimeRelease,browser:RuntimeReleaseBrowser,install:Bool){guard !busy else{return};busy=true
  Task{defer{busy=false};do{
   activity="Downloading "+asset.name
   var trust=install ? try RuntimeCatalog.definition(browser.engine).map{try RuntimeDownloadTrust(definition:$0,asset:asset,release:release,repository:browser.repository)}:nil
   if let initial=trust{trust=try await initial.resolvingOfficialChecksum(release:release,folder:directory(.downloads))}
   let archive=try await GitHubUpdates.download(trust?.asset ?? asset,repository:browser.repository,into:directory(.downloads))
   if install {
    guard RuntimeCatalog.definition(browser.engine)?.releaseRepository==browser.repository,ManagedLaunch.engines.contains(browser.engine),!hasRunningRuntime(browser.engine) else{throw AkitoStationError.message("This emulator needs an Akito Station launch adapter before installation.")}
    guard archive.pathExtension.lowercased()=="zip" else{throw AkitoStationError.message("Automatic installation currently supports ZIP releases. Open the official DMG/archive and use Choose Existing Installation; no Developer Tools are needed for app import.")}
    guard let definition=RuntimeCatalog.definition(browser.engine) else{throw AkitoStationError.message("Unknown emulator")}
    let log=try directory(.logs).appendingPathComponent(browser.engine+"-release-install.log")
    let staging=archive.deletingLastPathComponent().appendingPathComponent(".extract-"+UUID().uuidString)
    let root=try directory(.runtimes),host=Bundle.main.executableURL!
    activity="Checking and installing "+browser.name
    _=try await Task.detached(priority:.userInitiated){
     defer{try? FileManager.default.removeItem(at:staging)}
     try await RuntimeArchive.extractZIP(archive,to:staging,log:log)
     let apps=try RuntimeArchive.applications(in:staging)
     guard apps.count==1,let app=apps.first else{throw AkitoStationError.message("Expected exactly one upstream emulator application")}
     return try await RuntimeManager(root:root).importCatalog(input:app,definition:definition,platform:definition.platforms[0],managed:true,host:host,log:log,downloadTrust:trust)
    }.value
    try await reloadAsync();activity="Update installed · game untested. Previous runtime retained."
   }else{activity="Downloaded "+asset.name;NSWorkspace.shared.activateFileViewerSelecting([archive])}
   runtimeUpdateStatus[browser.engine.isEmpty ? browser.repository:browser.engine]=activity
   releaseBrowser=nil
  }catch{message=error.localizedDescription;activity="Update not deployed"}}
 }
 func selectRuntime(_ runtime:RuntimeManifest){guard !busy,!hasRunningRuntime(runtime.id) else{return};runtimeOperation("Selecting runtime"){try $0.activate(runtime.id,version:runtime.version)}}
 func rollbackRuntime(_ id:String){guard !busy,!hasRunningRuntime(id) else{return};runtimeOperation("Restoring previous runtime"){try $0.rollback(id)}}
 func updateRuntime(_ runtime:RuntimeManifest,channel:String="stable"){guard !busy else{return}
  guard runtime.custom==nil else{message="Update this custom emulator through its provider, then use Edit to relink and verify the new executable.";return}
  if ManagedLaunch.engines.contains(runtime.id){browseRuntimeReleases(name:runtime.id,repository:GitHubUpdates.releaseRepository(engine:runtime.id,upstream:runtime.upstream),engine:runtime.id,channel:channel,statusID:runtime.id);return}
  let game=games.first{$0.platform.core==runtime.id}
  if runtime.id=="dolphin" && game==nil{message="A GameCube or Wii game is required to validate the Dolphin update.";return}
  busy=true;Task{defer{busy=false};do{
   activity="Checking source update for "+runtime.id
   let revision=try await GitHubUpdates.sourceRevision(repository:runtime.upstream,channel:BuildEdition.isDeveloper ? channel : "stable")
   if revision==runtime.revision{runtimeUpdateStatus[runtime.id]="Already using the latest source revision";activity="Runtime is up to date";return}
   guard let tools=Bundle.main.resourceURL?.appendingPathComponent("Tools") else{throw AkitoStationError.message("Runtime tools are missing")}
   let dolphin=runtime.id=="dolphin"
   var args=[tools.appendingPathComponent(dolphin ? "manage-dolphin.py":"manage-runtime.py").path,"build","--root",try directory(.runtimes).path,"--work",try directory(.downloads).path,"--revision",revision,"--activate"]
   if !dolphin{args += ["--core",runtime.id,"--host",Bundle.main.executableURL!.path]}
   // Public validates the libretro ABI; library contents never select Developer probes.
   if dolphin,let game=game{args += ["--rom",try resolveGame(game).path]}else{args += PublicRuntimeUpdateValidation.coreArguments(gamePath:nil)}
   let log=try directory(.logs).appendingPathComponent(runtime.id+"-update.log")
   var env=ProcessInfo.processInfo.environment;env["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
   activity="Building and validating "+runtime.id
   let result=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/python3"),arguments:args,log:log,timeout:3600,environment:env)
   guard result.exitCode==0 else{throw AkitoStationError.message("Candidate failed validation; current runtime retained. Details: \(log.path)")}
   try await reloadAsync();activity="Update installed · compatibility checked, game untested; previous runtime retained"
   runtimeUpdateStatus[runtime.id]=activity
  }catch{runtimeUpdateStatus[runtime.id]=error.localizedDescription;message=error.localizedDescription;activity="Update not deployed"}}
 }
}
