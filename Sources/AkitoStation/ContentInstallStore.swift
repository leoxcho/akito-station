import SwiftUI
import AkitoStationCore

extension LibraryStore {
 func installConsolePackage(file:URL,platform:Platform,library:Location,license:URL?=nil,folder:Bool=false){
  guard !busy else{return}
  guard !hasRunningRuntime(platform.core ?? "") else{message="Stop the running \(platform.title) game before installing content.";return}
  busy=true;activity="Preparing \(platform.title) installation…"
  Task{defer{busy=false};do{
   let romRoot=try library.resolve();_=try ConsoleContent.romDirectory(library:romRoot,platform:platform)
   if !folder{let info=try ConsolePackage.inspect(file);try info.require(platform);guard info.platform != .ps4 else{throw AkitoStationError.message("The current PS4 runtime does not install PKGs. Import an extracted PS4 game folder instead.")}}
   let work=try directory(.downloads)
   let data=try directory(.saves).appendingPathComponent("Systems/"+(platform.core ?? "unknown"))
   let log=try directory(.logs).appendingPathComponent("package-"+platform.rawValue+"-"+UUID().uuidString+".log")
   let runtimeRoot=try directory(.runtimes)
   activity="Installing into selected library…"
   let installed=try await Task.detached(priority:.userInitiated){
    let binary=folder ? nil:try RuntimeManager(root:runtimeRoot).selected(platform.core!).1
    return try await NativeConsoleInstaller.install(file:file,platform:platform,library:romRoot,data:data,runtime:binary,work:work,license:license,folder:folder,log:log)
   }.value
   try ConsoleContent.record(.init(platform:platform,filename:file.lastPathComponent,status:installed.status,destination:installed.destination.path),root:directory(.saves))
   activity="Installed in \(installed.destination.path)"
   // Refresh the configured ROM libraries so new installed games immediately appear.
   let locations=storage?.libraries ?? []
   let discovered=try await Task.detached{try LibraryScanner.scan(locations)}.value
   games=LibraryScanner.merge(discovered,existing:games);try persist()
  }catch{message=error.localizedDescription;activity="Installation stopped — inspect the reported details"}}
 }
 func importDigitalLicenses(_ files:[URL],platform:Platform){guard !busy else{return};guard !hasRunningRuntime(platform.core ?? "") else{message="Stop the game before importing its license.";return};busy=true
  Task{defer{busy=false};do{let root=try directory(.saves);let receipts=try await Task.detached{try files.map{try ConsoleContent.importLicense($0,platform:platform,root:root)}}.value;activity="Imported \(receipts.count) license file(s) for \(platform.title)"}catch{message=error.localizedDescription}}
 }
}
