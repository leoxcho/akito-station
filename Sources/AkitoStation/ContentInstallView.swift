import SwiftUI
import AkitoStationCore

struct ContentInstallView:View {
 @EnvironmentObject var store:LibraryStore
 @State private var platform:Platform = .ps3
 @State private var libraryPath=""
 @State private var package:URL?
 @State private var packageInfo:ConsolePackage?
 @State private var license:URL?
 @State private var history:[ConsoleContent.Receipt]=[]
 @State private var error:String?
 var library:Location?{store.storage?.libraries.first{$0.path==libraryPath}}
 var destination:String {
  guard let library=library else{return "Choose a ROM library in Storage Locations first."}
  do{let root=try ConsoleContent.romDirectory(library:library.resolve(),platform:platform);return root.appendingPathComponent(packageInfo?.titleID.isEmpty==false ? packageInfo!.titleID:"<title ID>").path}catch{return error.localizedDescription}
 }
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   Picker("Console",selection:$platform){ForEach([Platform.ps3,.ps4,.psvita]){Text($0.title).tag($0)}}.disabled(store.busy)
   Picker("ROM library",selection:$libraryPath){Text("Choose destination library").tag("");ForEach(store.storage?.libraries ?? [],id:\.path){Text($0.path).tag($0.path)}}.disabled(store.busy)
   Text("Installed game location").font(.headline)
   Text(destination).font(.caption).textSelection(.enabled)
   Text("Games and game updates go into the selected library’s console folder. Licenses, saves and runtime settings remain in Akito Station’s managed system storage. Existing title data is retained in a backup when an update replaces it.").font(.caption).foregroundStyle(.secondary)
   Divider()
   HStack{Button("Choose PKG…"){choosePackage()};Text(package?.lastPathComponent ?? "No package selected").font(.caption).lineLimit(2)}.disabled(store.busy)
   if let info=packageInfo{
    Text("Detected: \(info.platform.title)"+(info.contentID.isEmpty ? "":" · "+info.contentID)).font(.caption).textSelection(.enabled)
    if info.platform != platform{Text("The selected console does not match this package.").foregroundStyle(.orange)}
   }
   if platform == .psvita {
    HStack{Button("Choose matching work.bin / RIF…"){chooseLicense()};Text(license?.lastPathComponent ?? "Use an already imported matching license").font(.caption)}.disabled(store.busy)
    Text("The Vita package and license content IDs must match. Akito Station accepts work.bin, .rif and .riff, and keeps the supplied license bytes unchanged.").font(.caption).foregroundStyle(.secondary)
   }
   if platform == .ps4 {
    Text("This shadPS4 runtime has no PKG installer. PS4 PKGs are identified but never sent to PS3 or Vita. You can install an already-extracted CUSA game folder below.").font(.caption).foregroundStyle(.orange)
    Button("Install extracted PS4 game folder…"){chooseFolder()}.disabled(store.busy || library==nil)
   }else{
    Button("Install package"){if let file=package,let library=library{store.installConsolePackage(file:file,platform:platform,library:library,license:platform == .psvita ? license:nil)}}.buttonStyle(.borderedProminent).disabled(store.busy || library==nil || packageInfo?.platform != platform)
   }
   Divider()
   Text("Package installation uses the installed emulator in isolated temporary storage. Firmware and matching licenses must be supplied by you; gameplay remains untested.").font(.caption).foregroundStyle(.orange)
   Text("Digital licenses").font(.headline)
   Text(platform == .ps3 ? "RAP and EDAT files are routed to PS3 user 00000001/exdata. RIF and activation data are retained separately when the runtime cannot use them.":platform == .psvita ? "work.bin and RIF files are routed to Vita ux0/license/<title ID>/<content ID>.rif.":"PS4 licenses are retained in its own ImportedLicenses folder. shadPS4 does not currently expose a license activation interface.").font(.caption).foregroundStyle(.secondary)
   Button("Import license files…"){let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.canChooseDirectories=false;panel.prompt="Import licenses";if panel.runModal() == .OK{store.importDigitalLicenses(panel.urls,platform:platform)}}.disabled(store.busy)
   if store.busy{HStack{ProgressView().controlSize(.small);Text(store.activity).font(.caption)}}else{Text(store.activity).font(.caption)}
   if let error=error{Text(error).foregroundStyle(.orange)}
   ForEach(history.filter{$0.platform==platform}){entry in VStack(alignment:.leading,spacing:4){Text(entry.filename).font(.headline);Text(entry.status).font(.caption);Text(entry.destination).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)}}
  }.task{libraryPath=store.storage?.libraries.first?.path ?? "";reload()}.onChange(of:store.busy){_,busy in if !busy{reload()}}
 }
 func reload(){do{history=try ConsoleContent.history(root:store.directory(.saves))}catch{self.error=error.localizedDescription}}
 func choosePackage(){let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.prompt="Inspect package";guard panel.runModal() == .OK,let url=panel.url else{return};do{let info=try ConsolePackage.inspect(url);package=url;packageInfo=info;platform=info.platform;error=nil;license=nil}catch{self.error=error.localizedDescription;package=nil;packageInfo=nil}}
 func chooseLicense(){let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.prompt="Use this license";if panel.runModal() == .OK{license=panel.url}}
 func chooseFolder(){let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.prompt="Install PS4 folder";if panel.runModal() == .OK,let url=panel.url,let library=library{store.installConsolePackage(file:url,platform:.ps4,library:library,folder:true)}}
}
