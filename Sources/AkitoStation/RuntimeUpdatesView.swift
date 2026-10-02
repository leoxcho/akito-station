import SwiftUI
import AkitoStationCore

struct RuntimeUpdatesView:View {
 @EnvironmentObject var store:LibraryStore
 @State private var adding=false
 @AppStorage("runtimeUpdateChannel") private var savedChannel="stable"
 var channel:String{BuildEdition.isDeveloper ? savedChannel : "stable"}
 var body:some View {
  VStack(alignment:.leading,spacing:18){
   HStack{Button("Check all for updates"){store.checkAllRuntimeUpdates(channel:channel)}
}
    .disabled(store.busy)
   if store.busy{HStack{ProgressView().controlSize(.small);Text(store.activity).font(.caption)}}
   Text("Updates retain the previous runtime for rollback. Games with a saved known-good version keep that version until their profile is changed.").font(.caption).foregroundStyle(.secondary)
   ForEach(store.installedEngines){runtime in
    if runtime.custom != nil {HStack{Text(store.emulatorName(runtime.id));Button("Test Emulator"){store.testEmulator(runtime)};if let platform=runtime.platforms?.first{Button("Open Emulator Manager"){store.runtimeConsole=platform}}}}else if let definition=RuntimeCatalog.definition(runtime.id){
     VStack(alignment:.leading){Text(definition.name+" · Installed Version: "+runtime.revision);if definition.releaseRepository != nil || definition.installation == .sourceBuild{Button("Check for Updates"){store.checkOptionalUpdate(definition)}};Button("Open Emulator Manager"){store.runtimeConsole=definition.platforms.first};if let status=store.runtimeUpdateStatus[runtime.id]{Text(status).font(.caption)}}
    }
   }
   if store.installedEngines.isEmpty{Text("No emulators installed. Choose a console in Emulators to install or register one.")}

  }
  .sheet(item:$store.releaseBrowser){browser in RuntimeReleaseView(browser:browser).environmentObject(store)}
 }
 func runtimeRow(_ runtime:RuntimeManifest)->some View {
  VStack(alignment:.leading,spacing:8){
   HStack{Text(runtime.id).font(.headline);Spacer();Text(runtime.architecture+" · "+(runtime.capabilities.contains("gameUntested") || runtime.capabilities.contains("abiOnly") ? "Game untested":"Installed")).font(.caption).foregroundStyle(.secondary)}
   Text(ManagedLaunch.platforms(for:runtime.id).map(\.title).joined(separator:", ")).font(.caption)
   Text("Current: \(runtime.version)").font(.caption).textSelection(.enabled)
   if let url=URL(string:runtime.upstream){Link(runtime.upstream,destination:url).font(.caption)}
   HStack{
    if runtime.id=="eden"{Link("Download update…",destination:URL(string:"https://eden-emu.dev/downloads/")!);Button("Install downloaded app…"){store.importEmulator("eden",for:.switchConsole)}}else{
    Button("Update…"){store.updateRuntime(runtime,channel:channel)}
    Button("Releases…"){store.browseRuntimeReleases(name:runtime.id,repository:GitHubUpdates.releaseRepository(engine:runtime.id,upstream:runtime.upstream),engine:ManagedLaunch.engines.contains(runtime.id) ? runtime.id:"",channel:channel,statusID:runtime.id)}
    }
    Button("Uninstall"){store.uninstallRuntime(runtime.id)}.disabled(store.hasRunningRuntime(runtime.id))
    Button("Roll back"){store.rollbackRuntime(runtime.id)}.disabled(!hasPrevious(runtime.id))
   }.disabled(store.busy)
   if !ManagedLaunch.engines.contains(runtime.id){Text("Update builds and validates the embedded core from upstream source.").font(.caption).foregroundStyle(.secondary)}
   if let status=store.runtimeUpdateStatus[runtime.id]{Text(status).font(.caption).textSelection(.enabled)}
   DisclosureGroup("Installed versions"){
    ForEach(store.runtimes.filter{$0.id==runtime.id},id:\.version){version in
     HStack{Text(version.version).font(.caption);Spacer();if version.version==runtime.version{Text("Current").font(.caption)}else{Button("Activate"){store.selectRuntime(version)}.disabled(store.busy || !version.validated)}}
    }
   }.font(.caption)
  }.padding().background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
 }
 func hasPrevious(_ id:String)->Bool{(try? RuntimeManager(root:store.directory(.runtimes)).selection(id).previous) != nil}
}

struct RuntimeReleaseView:View {
 @EnvironmentObject var store:LibraryStore
 @Environment(\.dismiss) var dismiss
 let browser:RuntimeReleaseBrowser
 @State private var releaseID=""
 @State private var assetID:Int?
 var release:RuntimeRelease {browser.releases.first{$0.id==releaseID} ?? browser.releases[0]}
 var assets:[ReleaseAsset] {(browser.engine.isEmpty ? release.assets:release.assets.filter{$0.isMacCandidate}).sorted{a,b in a.isMacCandidate != b.isMacCandidate ? a.isMacCandidate:a.name.localizedStandardCompare(b.name) == .orderedAscending}}
 var asset:ReleaseAsset? {assets.first{$0.id==assetID}}
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   Text("Update "+browser.name).font(.title2.bold())
   Picker("Release",selection:$releaseID){ForEach(browser.releases){r in Text(r.tag_name+(r.prerelease ? " (prerelease)":"")).tag(r.id)}}
    .onChange(of:releaseID){_,_ in assetID=nil}
   if let url=URL(string:release.html_url){Link("Release notes on GitHub",destination:url)}
   if assets.isEmpty{Text("This release has no downloadable files. Integrated cores can still use their source update button.").foregroundStyle(.secondary)}else{
    Picker("Release file",selection:$assetID){Text("Choose a macOS release file").tag(nil as Int?);ForEach(assets){a in Text(a.name+" ("+ByteCountFormatter.string(fromByteCount:a.size,countStyle:.file)+")").tag(Optional(a.id))}}
    Text(browser.engine.isEmpty ? "The file will be saved in your configured Downloads folder. An Akito Station adapter is needed before this emulator can play games inside Akito Station.":"Choose a macOS archive or disk image containing the emulator app. Akito Station checks its signature and architecture before switching versions. Gameplay remains untested.").font(.caption).foregroundStyle(.secondary)
   }
   if store.busy{HStack{ProgressView().controlSize(.small);Text(store.activity).font(.caption)}}
   Text("Automatic installation accepts supported ZIPs. For DMG/other archives, download the official build and choose its extracted application in the emulator manager.").font(.caption)
   HStack{Button("Close"){dismiss()}.disabled(store.busy);Spacer();Button("Download only"){if let a=asset{store.downloadRuntimeAsset(a,release:release,browser:browser,install:false)}}.disabled(asset==nil || store.busy);if !browser.engine.isEmpty{Button("Install ZIP update"){if let a=asset{store.downloadRuntimeAsset(a,release:release,browser:browser,install:true)}}.buttonStyle(.borderedProminent).disabled(asset==nil || !(asset?.name.lowercased().hasSuffix(".zip") ?? false) || store.busy)}}
  }.padding(24).frame(width:620).onAppear{releaseID=browser.releases[0].id}.interactiveDismissDisabled(store.busy)
 }
}
