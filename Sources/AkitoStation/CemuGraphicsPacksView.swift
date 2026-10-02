import SwiftUI
import AkitoStationCore
struct CemuGraphicsPacksView:View {
 @EnvironmentObject var store:LibraryStore
 var onSaved:()->Void
 @State private var packs:[CemuGraphicsPack]=[]
 @State private var selected=""
 @State private var search=""
 @State private var text=""
 @State private var message=""
 var pack:CemuGraphicsPack?{packs.first{$0.id==selected}}
 var body:some View {
  DisclosureGroup("Wii U internal resolution and graphics-pack presets"){
   VStack(alignment:.leading,spacing:10){
    Text("Choose a game’s graphics pack to set internal resolution, shadows, anti-aliasing and its other available presets. Cemu applies packs only to their matching title IDs.").font(.caption)
    TextField("Find a game or graphics pack…",text:$search)
    Picker("Graphics pack",selection:$selected){Text("Choose a pack").tag("");ForEach(packs.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.id==selected}){Text($0.title).tag($0.id)}}
    if let pack=pack,let selection=try? pack.selection(in:text){
     Toggle("Enable this pack",isOn:Binding(get:{selection.0},set:{update(pack,enabled:$0)}))
     ForEach(pack.presets.keys.sorted(),id:\.self){category in
      Picker(category.isEmpty ? "Preset":category,selection:Binding(get:{selection.1[category] ?? ""},set:{update(pack,enabled:true,category:category,preset:$0)})){
       Text("Emulator default").tag("")
       ForEach(pack.presets[category] ?? [],id:\.self){Text($0).tag($0)}
      }
     }
    }
    Text(message).font(.caption)
   }.padding(.top,8)
  }.task{do{let base=try store.directory(.saves).appendingPathComponent("Systems/cemu/home/Library/Application Support/Cemu");text=try String(contentsOf:base.appendingPathComponent("settings.xml"));packs=try await Task.detached{try CemuGraphicsPack.discover(base:base)}.value;message="\(packs.count) installed graphics packs"}catch{message=error.localizedDescription}}
 }
 func update(_ pack:CemuGraphicsPack,enabled:Bool,category:String?=nil,preset:String="") {
  do{let file=try store.directory(.saves).appendingPathComponent("Systems/cemu/home/Library/Application Support/Cemu/settings.xml");let fresh=try String(contentsOf:file);let result=try pack.updating(fresh,enabled:enabled,category:category,preset:preset);try EmulatorSettings.save(result,to:file,original:fresh);text=result;message="Saved for the next Wii U launch.";onSaved()}catch{message=error.localizedDescription}
 }
}
