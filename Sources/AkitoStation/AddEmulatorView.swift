import SwiftUI
import AppKit
import AkitoStationCore

struct AddEmulatorView:View {
 @EnvironmentObject var store:LibraryStore
 @Environment(\.dismiss) private var dismiss
 let initialPlatform:Platform
 var editing:RuntimeManifest?=nil
 @State private var mode="Install Supported Emulator"
 @State private var platform:Platform = .nes
  @State private var input:URL?
 @State private var initialInput:URL?
 @State private var name=""
 @State private var executableOverride=""
 @State private var initialExecutableOverride=""
 @State private var managed=false
 @State private var detectedIcon:NSImage?
 @State private var detection:EmulatorDetection?
 @State private var launchMethod:GameLaunchMethod = .arguments
 @State private var arguments=""
 @State private var gameArgument="{game}"
 @State private var additional=""
 @State private var testArguments=""
 @State private var workingDirectory=""
 @State private var environment=""
 @State private var saveLocation=""
 @State private var configLocation=""
 @State private var error:String?
 @State private var advanced=false
 private let methods=["Install Supported Emulator","Import Existing Emulator","Add Custom Emulator"]
 var definitions:[RuntimeDefinition]{RuntimeCatalog.choices(platform)}
 var configuration:CustomEmulatorConfiguration {
  get throws {
   var config=editing?.custom ?? CustomEmulatorConfiguration(name:name)
   config.gameLaunchMethod=launchMethod
   config.name=name;config.environment=[:]
   config.arguments=lines(arguments);config.gameArgument=gameArgument;config.additionalArguments=lines(additional);config.testArguments=lines(testArguments)
   config.workingDirectory=workingDirectory;config.saveLocation=saveLocation;config.configLocation=configLocation;config.recognizedEngine=detection?.recognizedEngine ?? editing?.custom?.recognizedEngine
   for line in lines(environment) {
    guard let index=line.firstIndex(of:"=") else{throw AkitoStationError.message("Enter each environment setting as NAME=value.")}
    let key=String(line[..<index]);guard config.environment[key]==nil else{throw AkitoStationError.message("Each environment name may appear only once.")}
    config.environment[key]=String(line[line.index(after:index)...])
   }
   return config
  }
 }
 func lines(_ value:String)->[String]{value.components(separatedBy:.newlines).filter{!$0.isEmpty}}
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   HStack{Text(editing==nil ? "Add Emulator":"Edit Emulator").font(.title2.bold());Spacer();Button("Cancel"){dismiss()}}
   if editing==nil {Picker("Choose how to add it",selection:$mode){ForEach(methods,id:\.self){Text($0).tag($0)}}.pickerStyle(.segmented)}
   Picker("Console / System",selection:$platform){ForEach(Platform.allCases.filter{$0 != .unknown}){Text($0.title).tag($0)}}
   ScrollView{
    VStack(alignment:.leading,spacing:12){
     if mode==methods[0] && editing==nil {
      Text("Known compatible emulators").font(.headline)
      ForEach(definitions){definition in
       HStack{Text(definition.name);Spacer();if definition.installation != .manual{Button(definition.installation == .sourceBuild ? "Install from Source":"Install"){dismiss();store.installOptionalRuntime(definition,platform:platform)}}else{Link("Official Download",destination:URL(string:definition.officialSource)!)};if definition.id != "dolphin"{Button("Import"){dismiss();store.addExistingRuntime(definition,platform:platform)}}}
      }
     }else{
      Text(mode==methods[1] ? "Choose an existing application or executable. Recognized emulators get automatic launch defaults.":"Choose an application or executable, then confirm its name and console. Advanced settings are optional.").font(.caption).foregroundStyle(.secondary)
      HStack{Button(input==nil ? "Choose Application or Executable…":"Relink / Choose Installation…"){choose()};if let input=input{Text(input.path).font(.caption).textSelection(.enabled).lineLimit(2)}}
      TextField("Emulator Name",text:$name)
      Toggle("Install a managed copy",isOn:$managed)
      Text(managed ? "Akito Station copies and manages the selected runtime. Your original installation is retained.":"External Runtime: removing its registration leaves the original application and files untouched.").font(.caption).foregroundStyle(.secondary)
      if let detection=detection {
       HStack{if let icon=detectedIcon{Image(nsImage:icon).resizable().scaledToFit().frame(width:32,height:32)};Text("Detected: "+detection.name+" · "+detection.architecture+" · Version "+detection.version)}.font(.caption)
       if let id=detection.recognizedEngine{Text("Recognized as "+(RuntimeCatalog.definition(id)?.name ?? id)).font(.caption)}
       if let identifier=detection.bundleIdentifier{Text(identifier).font(.caption).foregroundStyle(.secondary)}
      }
      DisclosureGroup("Advanced Launch Configuration",isExpanded:$advanced){
       VStack(alignment:.leading,spacing:10){
        TextField("Executable inside .app (relative to bundle)",text:$executableOverride)
        Text("Arguments are entered one per line. Each line is passed directly, including any spaces; no shell is used.").font(.caption).foregroundStyle(.secondary)
        Picker("Game launch method",selection:$launchMethod){Text("Command-line arguments").tag(GameLaunchMethod.arguments);Text("Open game as document").tag(GameLaunchMethod.openDocument)}
        argumentEditor("Launch arguments before game",text:$arguments)
        TextField("ROM / game argument (empty for none)",text:$gameArgument)
        argumentEditor("Additional arguments after game",text:$additional)
        Text("Placeholders: {game}, {gameDirectory}, {runtimeDirectory}").font(.caption)
        TextField("Working directory (empty uses runtime directory)",text:$workingDirectory)
        argumentEditor("Environment (one NAME=value per line)",text:$environment)
        argumentEditor("Test arguments (no game placeholders)",text:$testArguments)
        TextField("Known save location (informational; never removed)",text:$saveLocation)
        TextField("Known config location (informational; never removed)",text:$configLocation)
       }.padding(.top,8)
      }
     }
     if let error=error{Text(error).foregroundStyle(.orange).textSelection(.enabled)}
    }
   }
   HStack{Text("Test checks startup without a ROM. Custom launch compatibility depends on the emulator's command-line interface.").font(.caption).foregroundStyle(.secondary);Spacer();if mode != methods[0] || editing != nil{Button("Save Emulator"){save()}.buttonStyle(.borderedProminent).disabled(input==nil || name.isEmpty || store.busy)}}
  }.textFieldStyle(.roundedBorder).padding(24).frame(width:760,height:650).onAppear{load()}.task(id:detection?.executable.path){detectedIcon=nil;if let found=detection,let relative=found.iconRelativePath{detectedIcon=await CoverImageCache.shared.image(found.base.appendingPathComponent(relative).path,maxPixelSize:64)}}
 }
 func argumentEditor(_ label:String,text:Binding<String>)->some View {VStack(alignment:.leading){Text(label).font(.caption);TextEditor(text:text).font(.system(.caption,design:.monospaced)).frame(height:55).overlay(RoundedRectangle(cornerRadius:4).stroke(.gray.opacity(0.4)))}}
 func choose(){
  let panel=NSOpenPanel();panel.title="Choose emulator application or executable";panel.canChooseFiles=true;panel.canChooseDirectories=false
  guard panel.runModal() == .OK,let url=panel.url else{return}
  Task{do{
   let found=try await Task.detached{try EmulatorDetection.inspect(url)}.value;input=url;detection=found;executableOverride="";error=nil
   if editing==nil {
    name=found.name
    launchMethod=found.bundleIdentifier?.lowercased() == "v380-ori.astris" ? .openDocument:.arguments
    if !found.supportedPlatforms.isEmpty && !found.supportedPlatforms.contains(platform){platform=found.supportedPlatforms[0]}
    if let id=found.recognizedEngine {
     let sample=URL(fileURLWithPath:"/tmp/Akito sample game.iso")
     let argv=(try? RuntimeCatalog.desktopArguments(engine:id,platform:platform,game:sample)) ?? [sample.path]
     arguments=argv.filter{!$0.contains(sample.path)}.joined(separator:"\n")
     gameArgument=argv.first{$0.contains(sample.path)}?.replacingOccurrences(of:sample.path,with:"{game}") ?? "{game}"
    }
   }
  }catch{self.error=error.localizedDescription}}
 }
 func load(){
  platform=initialPlatform
  guard let runtime=editing,let config=runtime.custom else{return}
  launchMethod=config.effectiveGameLaunchMethod
  mode=methods[2];name=config.name;managed=runtime.externalLocation==nil;arguments=config.arguments.joined(separator:"\n");gameArgument=config.gameArgument;additional=config.additionalArguments.joined(separator:"\n");testArguments=config.testArguments.joined(separator:"\n");workingDirectory=config.workingDirectory;environment=config.environment.sorted{$0.key<$1.key}.map{$0.key+"="+$0.value}.joined(separator:"\n");saveLocation=config.saveLocation;configLocation=config.configLocation
  if let manager=try? RuntimeManager(root:store.directory(.runtimes)),let base=try? manager.runtimeDirectory(runtime){
   let binary=base.appendingPathComponent(runtime.library)
   if runtime.library.contains(".app/") {
    let prefix=runtime.library.components(separatedBy:".app/")[0]+".app"
    input=base.appendingPathComponent(prefix);executableOverride=String(runtime.library.dropFirst(prefix.count+1))
   }else if base.pathExtension=="app"{input=base;executableOverride=runtime.library}else{input=binary}
   initialInput=input;initialExecutableOverride=executableOverride
   if let chosen=input{let override=executableOverride;Task{let found=try? await Task.detached{try EmulatorDetection.inspect(chosen,executableOverride:override)}.value;guard input==chosen,executableOverride==override else{return};detection=found}}
  }
 }
 func save(){Task{do{
  guard let input=input else{return}
  let config=try configuration
  if let runtime=editing,input==initialInput,managed==(runtime.externalLocation==nil) {
   try await store.updateCustomEmulator(runtime,platform:platform,configuration:config,input:input,executableOverride:executableOverride)
  }else{try await store.saveCustomEmulator(input:input,executableOverride:executableOverride,platform:platform,configuration:config,managed:managed,id:editing?.id)}
  dismiss()
 }catch{self.error=error.localizedDescription}}}
}
