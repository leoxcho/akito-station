import SwiftUI
import AkitoStationCore

extension LibraryStore {
 func emulatorName(_ id:String)->String {installedEngines.first{$0.id==id && $0.custom != nil}?.custom?.name ?? RuntimeCatalog.definition(id)?.name ?? id}
 func customEmulators(_ platform:Platform)->[RuntimeManifest] {
  installedEngines.filter{$0.custom != nil && $0.platforms?.contains(platform)==true}
 }
 func saveCustomEmulator(input:URL,executableOverride:String,platform:Platform,configuration:CustomEmulatorConfiguration,managed:Bool,id:String?=nil)async throws {
  guard !busy,id.map({!hasRunningRuntime($0)}) ?? true else{throw AkitoStationError.message("Quit this emulator before editing it.")}
  let manager=try RuntimeManager(root:directory(.runtimes))
  // User-owned storage must never become the source or destination of a managed copy.
  let source=input.resolvingSymlinksInPath()
  if managed {
   for kind in [StorageKind.saves,.states,.firmware,.screenshots,.profiles,.controllers,.metadata] {
    let protected=try directory(kind).resolvingSymlinksInPath()
    guard source != protected,!source.path.hasPrefix(protected.path+"/"),!protected.path.hasPrefix(source.path+"/") else{throw AkitoStationError.message("Choose the emulator application, not a user-data directory.")}
   }
   for location in storage?.libraries ?? [] {let library=try location.resolve().resolvingSymlinksInPath();guard source != library,!source.path.hasPrefix(library.path+"/"),!library.path.hasPrefix(source.path+"/") else{throw AkitoStationError.message("Emulator installation overlaps a game library; copying refused.")}}
  }
  busy=true;defer{busy=false}
  let manifest=try await Task.detached(priority:.userInitiated){try manager.registerCustom(input:input,executableOverride:executableOverride,platform:platform,configuration:configuration,managed:managed,id:id)}.value
  try await reloadAsync()
  if engine(platform)==nil || !(runtimes.contains{$0.id==engine(platform) && $0.validated}){switchEngine(manifest.id,for:platform)}
  activity="Emulator saved · "+configuration.name
 }
 func updateCustomEmulator(_ runtime:RuntimeManifest,platform:Platform,configuration:CustomEmulatorConfiguration,input:URL?=nil,executableOverride:String="")async throws {
  guard !busy,!hasRunningRuntime(runtime.id) else{throw AkitoStationError.message("Quit this emulator before editing it.")}
  let manager=try RuntimeManager(root:directory(.runtimes))
  busy=true;defer{busy=false}
  _=try await Task.detached(priority:.userInitiated){try manager.editCustom(runtime,platform:platform,configuration:configuration,input:input,executableOverride:executableOverride)}.value
  try await reloadAsync();activity="Emulator configuration saved"
 }
 func testEmulator(_ runtime:RuntimeManifest){
  guard !busy,!hasRunningRuntime(runtime.id) else{message="Quit this emulator before testing it.";return}
  busy=true;activity="Testing "+emulatorName(runtime.id)+" without a game…"
  Task{defer{busy=false};do{
   let manager=try RuntimeManager(root:directory(.runtimes))
   let pair=try await Task.detached{try manager.selected(runtime.id,version:runtime.version)}.value
   let log=try directory(.logs).appendingPathComponent("test-"+runtime.id+".log")
   if runtime.custom==nil && !ManagedLaunch.engines.contains(runtime.id) && runtime.id != "dolphin" {
    let result=try await ProcessRunner.run(executable:Bundle.main.executableURL!,arguments:["--verify-runtime-core","--core",pair.1.path],log:log,timeout:30)
    guard result.exitCode==0 else{throw AkitoStationError.message("Core validation failed. Choose a compatible native core.")}
    activity="✓ Emulator core verified · no game launched"
   }else{
    let launch=try runtime.custom.map{try ManagedLaunch(custom:$0,runtimeDirectory:manager.runtimeDirectory(runtime))}
    try await ProcessRunner.testRuntime(executable:pair.1,arguments:launch?.arguments ?? [],workingDirectory:launch?.workingDirectory,environment:launch?.environment,log:log)
    activity="✓ Emulator launched successfully · startup checked; gameplay untested"
   }
  }catch{activity="Could not launch emulator";message="Could not launch emulator. "+error.localizedDescription}}
 }
}
