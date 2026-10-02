import SwiftUI
import AkitoStationCore

struct OptionalRuntimePanel:View {
 @EnvironmentObject var store:LibraryStore
 let platform:Platform
 @State private var removing:String?
 @State private var adding=false
 @State private var editing:RuntimeManifest?
 var definitions:[RuntimeDefinition]{RuntimeCatalog.choices(platform).filter{$0.id != "dolphin" || store.runtimes.contains{$0.id=="dolphin"}}}
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   Text("Available Emulators").font(.title3.bold())
   Text("Install only what you need. Managed runtimes live outside Akito Station. External installations stay in their original locations.").font(.caption).foregroundStyle(.secondary)
   Picker("Default Emulator",selection:Binding(get:{installed(store.engine(platform) ?? "") ? store.engine(platform) ?? "":""},set:{store.switchEngine($0,for:platform)})){
    if !installed(store.engine(platform) ?? ""){Text("No installed default").tag("")}
    ForEach(EmulatorEngines.choices(for:platform,installed:store.runtimes),id:\.self){id in Text(store.emulatorName(id)).tag(id).disabled(!installed(id))}
   }.disabled(store.busy)
   ForEach(store.damagedRuntimes){damage in
    VStack(alignment:.leading){Text("Damaged runtime: \(damage.engine) / \(damage.version)").foregroundStyle(.orange);Text(damage.reason).font(.caption)
     HStack{if let definition=RuntimeCatalog.definition(damage.engine){Button("Repair / Relink"){store.addExistingRuntime(definition,platform:platform)}};Button("Quarantine Damaged Version"){store.runtimeOperation("Quarantining damaged runtime"){try $0.quarantine(damage)}}}
    }
   }
   ForEach(definitions){definition in row(definition)}
   ForEach(store.customEmulators(platform)){runtime in customRow(runtime)}
   Button("+ Add Emulator"){adding=true}.buttonStyle(.borderedProminent).disabled(store.busy)
   if store.busy{HStack{ProgressView().controlSize(.small);Text(store.activity)}}
   if store.activity.hasPrefix("✓ Emulator") || store.activity=="Could not launch emulator"{Text(store.activity).font(.caption).foregroundStyle(store.activity.hasPrefix("✓") ? IceTheme.cyan:.orange)}
  }.alert("Remove emulator?",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}})){
   Button("Cancel",role:.cancel){removing=nil}
   Button("Remove",role:.destructive){if let id=removing{store.removeOptionalRuntime(id)};removing=nil}
  }message:{Text("Managed runtime files are removed. External installations are only unregistered. Games, saves, firmware, BIOS, keys and profiles remain.")}
  .sheet(isPresented:$adding){AddEmulatorView(initialPlatform:platform).environmentObject(store)}
  .sheet(item:$editing){runtime in AddEmulatorView(initialPlatform:platform,editing:runtime).environmentObject(store)}
  .sheet(item:$store.releaseBrowser){browser in RuntimeReleaseView(browser:browser).environmentObject(store)}
 }
 func customRow(_ runtime:RuntimeManifest)->some View {
  VStack(alignment:.leading,spacing:8){
   HStack{RuntimeRegistrationIcon(runtime:runtime).environmentObject(store);Text(runtime.custom?.name ?? runtime.id).font(.headline);Spacer();if store.engine(platform)==runtime.id{Text("Default").foregroundStyle(IceTheme.gold)}}
   Text((runtime.externalLocation==nil ? "Managed Runtime":"External Runtime")+" · Version "+runtime.revision).font(.caption)
   if !installed(runtime.id){Text("Executable missing or changed. Edit to relink and verify its current installation.").font(.caption).foregroundStyle(.orange)}
   HStack{Button("Set as Default"){store.switchEngine(runtime.id,for:platform)}.disabled(!installed(runtime.id));Button("Edit"){editing=runtime};Button("Test Emulator"){store.testEmulator(runtime)};Button(runtime.externalLocation==nil ? "Uninstall Managed Emulator":"Remove from Akito Station"){removing=runtime.id}}
  }.padding().background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10)).disabled(store.busy || store.hasRunningRuntime(runtime.id))
 }
 func installed(_ id:String)->Bool{store.runtimes.contains{runtime in runtime.id==id && runtime.validated && !store.damagedRuntimes.contains{$0.engine==id && $0.version==runtime.version}}}
 func row(_ definition:RuntimeDefinition)->some View {
  let versions=store.runtimes.filter{$0.id==definition.id}
  let current=store.currentRuntimeVersion(definition.id)
  return VStack(alignment:.leading,spacing:8){
   HStack{Text(definition.name).font(.headline);Spacer();if store.engine(platform)==definition.id && installed(definition.id){Text("Default").font(.caption).foregroundStyle(IceTheme.gold)}}
   if versions.isEmpty{Text("Not installed").font(.caption).foregroundStyle(.secondary)}
   ForEach(versions,id:\.version){runtime in
    Text((runtime.trustStatus?.rawValue ?? "Unverified")+" · "+(runtime.publisherTrust ?? "Publisher trust not recorded; relink to verify")).font(.caption).foregroundStyle(.secondary)
    HStack{Text((runtime.externalLocation == nil ? "Managed Runtime":"External Runtime")+" · Installed Version: "+runtime.revision).font(.caption);Spacer();if current != runtime.version{Button("Select version"){store.selectRuntime(runtime)}}else{Text("Selected").font(.caption)}}
   }
   HStack{
    if definition.installation != .manual{Button(versions.isEmpty ? (definition.installation == .sourceBuild ? "Build · Requires Developer Tools":"Install"):"Update"){store.installOptionalRuntime(definition,platform:platform)}}
    Link("Download from Official Website",destination:URL(string:definition.officialSource)!)
    Button("Choose Existing Installation"){store.addExistingRuntime(definition,platform:platform)}
   }
   HStack{
    Button("Install a managed copy…"){store.addExistingRuntime(definition,platform:platform,managed:true)}
    if installed(definition.id){Button("Set Default"){store.switchEngine(definition.id,for:platform)}}
    if !versions.isEmpty {
     Button(versions.allSatisfy{$0.externalLocation != nil} ? "Unregister":"Uninstall"){removing=definition.id}
     Button("Relink Installation"){store.addExistingRuntime(definition,platform:platform)}
     if definition.desktop || definition.id=="dolphin"{Button("Relink Executable…"){store.addExistingRuntime(definition,platform:platform,chooseExecutable:true)}}
     Button("Test Emulator"){if let runtime=versions.first(where:{$0.version==current}) ?? versions.first{store.testEmulator(runtime)}}
     Button("Open Runtime Folder"){store.showRuntimeFolder(definition.id)}
    }
   }
   HStack{
    if definition.releaseRepository != nil || definition.installation == .sourceBuild{Button("Check for Updates"){store.checkOptionalUpdate(definition)}}
    Link("View Source / License",destination:URL(string:definition.releaseRepository ?? definition.officialSource)!)
    Text(definition.license).font(.caption).foregroundStyle(.secondary)
   }
   if definition.installation == .sourceBuild{Text("Builds the official source locally; requires Xcode command-line tools and upstream build dependencies.").font(.caption).foregroundStyle(.secondary)}
   if definition.id=="xenia"{Text("An independently obtained compatible macOS port is required. The upstream project does not provide a supported macOS installer.").font(.caption).foregroundStyle(.secondary)}
   if definition.id=="dolphin"{Text("Requires an existing Akito-compatible Dolphin adapter. Standard Dolphin apps use the Dolphin choice above.").font(.caption).foregroundStyle(.secondary)}
   if definition.id=="ryujinx" || definition.id=="lime3ds"{Text("Existing installation only; no mirror downloads.").font(.caption).foregroundStyle(.secondary)}
   if let status=store.runtimeUpdateStatus[definition.id]{Text(status).font(.caption).textSelection(.enabled)}
  }.padding().background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10)).disabled(store.busy || store.hasRunningRuntime(definition.id))
 }
}
struct OptionalRuntimeSheet:View {
 @EnvironmentObject var store:LibraryStore
 @Environment(\.dismiss) var dismiss
 let platform:Platform
 var body:some View{VStack(alignment:.leading){HStack{Text(platform.title+" · Emulators").font(.title2.bold());Spacer();Button("Done"){dismiss()}};ScrollView{OptionalRuntimePanel(platform:platform)}}.padding(24).frame(width:900,height:650)}
}
struct GameEmulatorPicker:View {
 @EnvironmentObject var store:LibraryStore
 let platform:Platform
 @Binding var profile:GameProfile
 var body:some View {
  Picker("Emulator",selection:Binding(get:{profile.options["arm.runtime.override"] ?? ""},set:{choice in profile.options["arm.runtime.override"]=choice.isEmpty ? nil:choice;profile.options["arm.runtime.engine"]=choice.isEmpty ? store.engine(platform):choice;profile.knownGoodRuntime=nil;profile.verifiedAt=nil})){
   Text("Use Console Default").tag("")
   ForEach(EmulatorEngines.choices(for:platform,installed:store.runtimes),id:\.self){id in Text(store.emulatorName(id)).tag(id)}
  }
  Button("Manage Emulators"){store.selected=nil;store.runtimeConsole=platform}
 }
}

private struct RuntimeRegistrationIcon:View {
 @EnvironmentObject var store:LibraryStore
 let runtime:RuntimeManifest
 @State private var image:NSImage?
 var body:some View {
  Group{if let image{Image(nsImage:image).resizable().scaledToFit().frame(width:28,height:28)}}.task(id:runtime.version){
   guard let relative=runtime.custom?.iconRelativePath,let configuration=store.storage else{return}
   let path=try? await Task.detached{let base=try RuntimeManager(root:configuration.directory(.runtimes)).runtimeDirectory(runtime);let icon=base.appendingPathComponent(relative).resolvingSymlinksInPath();guard icon.path.hasPrefix(base.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Icon escapes runtime")};return icon.path}.value
   if let path{image=await CoverImageCache.shared.image(path,maxPixelSize:64,cacheRevision:runtime.version)}
  }
 }
}
