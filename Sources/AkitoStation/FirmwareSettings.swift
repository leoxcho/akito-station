import SwiftUI
import AkitoStationCore

struct FirmwareSettings:View {
 @EnvironmentObject var store:LibraryStore
 @State private var platform:Platform = .ps1
 @State private var entries:[ConsoleResources.Entry]=[]
 @State private var importing=false
 @State private var message=""
 var body:some View{VStack(alignment:.leading,spacing:16){
  Picker("Console",selection:$platform){ForEach(Platform.allCases.filter{$0 != .unknown}){Text($0.title).tag($0)}}.disabled(importing)
  Text(ConsoleResources.guidance(platform)).foregroundStyle(.secondary)
  HStack{Button("Import BIOS / firmware / keys…"){importFile()}.disabled(importing);if importing{ProgressView().controlSize(.small)}}
  Text("Files stay on this Mac in Akito Station’s managed storage. Import verifies the copy; it does not establish that the file is compatible or install a firmware package.").font(.caption).foregroundStyle(.secondary)
  if !message.isEmpty{Text(message).font(.caption)}
  ForEach(entries){entry in VStack(alignment:.leading,spacing:4){Text(entry.filename).font(.headline);Text(entry.installationRequired ? "Imported · runtime installation required":"Imported · runtime validation required").font(.caption).foregroundStyle(.orange);Text(ByteCountFormatter.string(fromByteCount:Int64(entry.bytes),countStyle:.file)).font(.caption)}}
  if entries.isEmpty{Text("No files imported for this console.").foregroundStyle(.secondary)}
 }.task(id:platform){reload()}}
 func root()throws->URL{try store.directory(.saves)}
 func reload(){do{entries=try ConsoleResources.entries(root:root(),platform:platform)}catch{message=error.localizedDescription}}
 func importFile(){
  let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=true;panel.prompt="Import into Akito Station"
  guard panel.runModal() == .OK else{return}
  let files=panel.urls,selected=platform
  do{let root=try root();importing=true;Task{defer{importing=false;reload()};do{let count=try await Task.detached(priority:.userInitiated){var count=0;for file in files{_=try ConsoleResources.importFile(file,root:root,platform:selected);count += 1};return count}.value;message="Imported \(count) file(s). Originals are unchanged."}catch{message=error.localizedDescription}}}catch{message=error.localizedDescription}
 }
}
