import SwiftUI
import AkitoStationCore

struct EmulatorSettingsPanel:View {
 @EnvironmentObject var store:LibraryStore
 let system:Platform
 @State private var files:[URL]=[]
 @State private var selected:URL?
 @State private var document:NativeSettingsDocument?
 @State private var edits:[String:String]=[:]
 @State private var query=""
 @State private var section="All"
 @State private var focus="All"
 @State private var status=""
 @State private var options:[CoreOption]=[]
 @State private var documentRevision=0
 @State private var loading=false
 @State private var confirmingReset=false
 var engine:String{store.engine(system) ?? ""}
 var native:Bool{EmulatorSettings.files[engine] != nil}
 var dirty:Bool{document?.fields.contains{edits[$0.id] != nil && edits[$0.id] != $0.value} ?? false}
 var profile:GameProfile{store.systemProfiles[system.rawValue] ?? GameProfile()}
 var body:some View {
  VStack(alignment:.leading,spacing:12){
   Text("\(system.title) · \(engine)").font(.headline)
   Button("Reset emulator settings…"){confirmingReset=true}.disabled(loading || !store.canResetSettings || ExternalEmulator.name(system) != nil)
   EmulatorEnginePicker(system:system).disabled(dirty || loading)
   if let name=ExternalEmulator.name(system){Text("This system uses the installed "+name+" app and its own settings and saves.");Button("Open "+name+" settings"){store.openExternal(system)}}else if native {
    if engine=="cemu"{CemuGraphicsPacksView(onSaved:{loadDocument()}).disabled(dirty || store.hasRunningRuntime(engine))}
    Toggle("Use emulator graphics and controller settings",isOn:Binding(get:{EmulatorSettings.native(profile)},set:{value in var p=profile;p.options["arm.settings.native"]=String(value);store.saveSystem(p,system)}))
    Text("These are the emulator’s own settings in Akito Station’s managed storage. They apply on the next launch. Settings are shared by games using this engine; native mode takes priority over the simplified graphics presets.").font(.caption).foregroundStyle(.secondary)
    Button("Import installed emulator graphics and controls…"){Task{await importSettings()}}.disabled(loading || dirty)
    if files.isEmpty{Text("No managed settings found. Import your installed emulator’s configuration above.")}
    else{
     Picker("Settings file",selection:$selected){ForEach(files,id:\.self){file in Text(displayName(file)).tag(Optional(file))}}.disabled(dirty)
     if let document=document {
      Picker("Section",selection:$section){Text("All sections").tag("All");ForEach(Array(Set(document.fields.map{$0.section})).sorted(),id:\.self){Text($0.isEmpty ? "General":$0).tag($0)}}
      Picker("Show",selection:$focus){Text("All options").tag("All");Text("Upscaling / resolution").tag("Resolution");Text("VSync / presentation").tag("VSync");Text("Filtering").tag("Filtering");Text("Controllers").tag("Controllers")}.pickerStyle(.menu)
      TextField("Search graphics, renderer, controller, binding…",text:$query)
      LazyVStack(alignment:.leading,spacing:10){ForEach(document.fields.filter{field in BuildEdition.visibleSetting(field.section+" "+field.key) && (section=="All" || field.section==section) && matchesFocus(field) && (query.isEmpty || (field.section+" "+field.key+" "+field.help).localizedCaseInsensitiveContains(query))}){field in
       VStack(alignment:.leading,spacing:3){
        HStack{
         VStack(alignment:.leading){Text(fieldTitle(field));Text(field.section).font(.caption2).foregroundStyle(.secondary)}.frame(width:240,alignment:.leading)
         if field.isBoolean{Toggle(field.key,isOn:Binding(get:{(edits[field.id] ?? field.value).lowercased()=="true"},set:{edits[field.id]=field.value=="True" || field.value=="False" ? ($0 ? "True":"False"):String($0)})).labelsHidden()}
         else{TextField(field.key,text:Binding(get:{edits[field.id] ?? field.value},set:{edits[field.id]=$0})).textFieldStyle(.roundedBorder)}
        }
        if !field.help.isEmpty{Text(field.help).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
       }
      }}
      HStack{Button("Save emulator settings"){save()}.disabled(!dirty).buttonStyle(.borderedProminent);Button("Discard edits"){edits=[:]}.disabled(!dirty);Text("\(document.fields.count) settings").font(.caption)}
     }
    }
   }else if !engine.isEmpty{
    Toggle("Metal presentation VSync",isOn:Binding(get:{profile.vsync},set:{value in var p=profile;p.vsync=value;store.saveSystem(p,system)}))
    Picker("Display scaling filter",selection:Binding(get:{profile.options["arm.display.filter"] ?? "Linear"},set:{value in var p=profile;p.options["arm.display.filter"]=value;store.saveSystem(p,system)})){Text("Linear").tag("Linear");Text("Nearest neighbor").tag("Nearest")}

    Text("Options reported by the installed core. Changes apply on the next launch; hardware renderer choices still require support from Akito Station’s embedded player.").font(.caption).foregroundStyle(.secondary)
    TextField("Search core options…",text:$query)
    LazyVStack(alignment:.leading,spacing:10){ForEach(options.filter{BuildEdition.visibleSetting($0.title+" "+$0.key) && (query.isEmpty || ($0.title+" "+$0.key).localizedCaseInsensitiveContains(query))}){option in
     Picker(option.title,selection:Binding(get:{profile.options[option.key] ?? option.values.first ?? ""},set:{value in var p=profile;p.options[option.key]=value;store.saveSystem(p,system)})){
      if let saved=profile.options[option.key],!option.values.contains(saved){Text("\(saved) (unavailable)").tag(saved)}
      ForEach(option.values,id:\.self){Text($0).tag($0)}
     }.help(option.key)
    }}
    Text("Keyboard, gamepad buttons and stick dead zones can be set per console in Controllers.").font(.caption)
   }else{Text("No runtime is currently integrated for this console.")}
   HStack{Button("Reload"){Task{await reload()}}.disabled(loading || dirty);if loading{ProgressView().controlSize(.small)};Text(status).font(.caption).textSelection(.enabled)}
  }.alert("Reset emulator settings?",isPresented:$confirmingReset){Button("Cancel",role:.cancel){};Button("Reset",role:.destructive){do{try SettingsReset.archive(files);store.saveSystem(GameProfile(),system);Task{await reload();status="Settings backed up. Defaults take effect on the next launch."}}catch{status=error.localizedDescription}}}message:{Text("Back up this engine’s configuration and restore its system profile. The emulator recreates defaults on its next launch. Games sharing this engine are affected; per-game overrides remain. Stop any independently launched emulator first.")}.task(id:engine){await reload()}.onChange(of:selected){_,_ in loadDocument()}
 }
 func matchesFocus(_ field:SettingsField)->Bool {
  let key=field.key.lowercased(),context=(field.section+" "+field.key+" "+(selected?.lastPathComponent ?? "")).lowercased()
  switch focus {
  case "Resolution":return ["resolution","res_scale","surface_scale","width","height","fsr","rcas"].contains{key.contains($0)} || (engine=="cemu" && context.contains("graphicpack"))
  case "VSync":return ["vsync","v-sync","presentmode","swapinterval","allow_tearing"].contains{key.contains($0)}
  case "Filtering":return ["filter","anisotrop","antialias","anti_alias","multisample","msaa","fxaa"].contains{key.contains($0)}
  case "Controllers":return ["input","controller","controlmapping","pad","keyboard","hotkey","button","binding","deadzone"].contains{context.contains($0)}
  default:return true
  }
 }
 func fieldTitle(_ field:SettingsField)->String {
  switch field.key {
  case "InternalResolution","ResolutionScale","resolution_factor","resolution-multiplier","upscale_multiplier","res_scale","surface_scale":return "Internal resolution scale (×) · \(field.key)"
  case "Resolution Scale":return "Internal resolution scale (%)"
  case "draw_resolution_scale_x":return "Horizontal resolution scale (×)"
  case "draw_resolution_scale_y":return "Vertical resolution scale (×)"
  case "presentMode":return "Presentation / VSync mode"
  case "metal_allow_tearing":return "Allow tearing (disable Metal VSync)"
  default:return field.key
  }
 }
 func displayName(_ file:URL)->String{let base=(try? store.directory(.saves).appendingPathComponent("Systems/"+engine).path) ?? "";return file.path.hasPrefix(base+"/") ? String(file.path.dropFirst(base.count+1)):file.lastPathComponent}
 func loadDocument(){
  documentRevision+=1;let revision=documentRevision;edits=[:];section="All"
  guard let file=selected else{document=nil;return}
  Task{do{let loaded=try await Task.detached{try NativeSettingsDocument(text:String(contentsOf:file),format:file.pathExtension)}.value;guard revision==documentRevision,selected==file else{return};document=loaded;status=""}catch{guard revision==documentRevision else{return};status=error.localizedDescription;document=nil}}
 }
 func save(){
  guard !loading,!store.hasRunningRuntime(engine),let file=selected,let original=document else{return}
  let changes=edits;loading=true
  Task{defer{loading=false};do{try await Task.detached{let text=try original.applying(changes);try EmulatorSettings.save(text,to:file,original:original.text)}.value;loadDocument();status="Saved. Previous settings backed up."}catch{status=error.localizedDescription}}
 }
 func importSettings()async {
  guard !loading else{return};guard !store.hasRunningRuntime(engine) else{status="Stop this emulator before importing settings.";return};loading=true
  do{
   guard let relative=EmulatorSettings.files[engine]?.first else{throw AkitoStationError.message("Use this emulator's own settings interface")}
   let panel=NSOpenPanel();panel.title="Import graphics/controller configuration";panel.canChooseDirectories=false
   guard panel.runModal() == .OK,let source=panel.url else{loading=false;return}
   let selectedEngine=engine
   let root=try store.directory(.saves),destination=root.appendingPathComponent("Systems/"+selectedEngine+"/"+relative)
   try await Task.detached(priority:.userInitiated){try NativeSettingsImport.importFile(source,to:destination,managedRoot:root,engine:selectedEngine)}.value
   loading=false;await reload()
   if !files.isEmpty{var p=profile;p.options["arm.settings.native"]="true";store.saveSystem(p,system);status="Imported into managed storage; prior settings backed up."}
  }catch{loading=false;status=error.localizedDescription}
 }
 func reload()async {
  guard !loading else{return};loading=true;defer{loading=false};status="";options=[];files=[];selected=nil;document=nil;edits=[:]
  do{
   if ExternalEmulator.name(system) != nil{return}
   guard let configuration=store.storage else{status="Choose storage in Settings";return}
   if native{let selectedEngine=engine;files=try await Task.detached{try EmulatorSettings.documents(engine:selectedEngine,data:configuration.directory(.saves).appendingPathComponent("Systems/"+selectedEngine))}.value;selected=files.first;loadDocument()}
   else if !engine.isEmpty{
    guard store.runtimes.contains(where:{$0.id == engine && $0.validated}) else{status="No emulator is installed for this console. Add a compatible runtime in Emulator Settings before playing.";return}
    let root=try store.directory(.runtimes),selectedEngine=engine
    let (manifest,binary)=try await Task.detached{try RuntimeManager(root:root).selected(selectedEngine)}.value
    let cache=try store.directory(.profiles).appendingPathComponent("core-options");try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
    let output=cache.appendingPathComponent(engine+"-"+manifest.sha256+".json")
    if !FileManager.default.fileExists(atPath:output.path) || (try? JSONStore.read([CoreOption].self,from:output).isEmpty)==true{
     let result=try await ProcessRunner.run(executable:Bundle.main.executableURL!,arguments:["--core-options","--core",binary.path,"--output",output.path],log:cache.appendingPathComponent(engine+".log"),timeout:20)
     guard result.exitCode==0 else{throw AkitoStationError.message("Core option discovery failed. See the core-options log.")}
    }
    options=try await Task.detached{try JSONStore.read([CoreOption].self,from:output)}.value
    if options.isEmpty,let bundled=Bundle.main.resourceURL?.appendingPathComponent("CoreOptions/"+engine+"-"+manifest.sha256+".json"),FileManager.default.fileExists(atPath:bundled.path){options=try await Task.detached{try JSONStore.read([CoreOption].self,from:bundled)}.value}
    status="\(options.count) options from \(manifest.version)"
   }
  }catch{status=error.localizedDescription}
 }
}

struct EmulatorEnginePicker:View {
 @EnvironmentObject var store:LibraryStore
 let system:Platform
 var body:some View{OptionalRuntimePanel(platform:system)}
}
