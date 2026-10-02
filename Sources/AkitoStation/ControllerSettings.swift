import SwiftUI
import AkitoStationCore

struct ControllerSettings:View {
 @EnvironmentObject var store:LibraryStore
 @State private var tab="Standard"
 @State private var scope="global"
 @State private var bindings=ControllerBindings()
 var body:some View{VStack(alignment:.leading,spacing:16){
  Picker("Console profile",selection:$scope){Text("Shared defaults").tag("global");ForEach(Platform.allCases.filter{$0.core != nil && !ManagedLaunch.engines.contains($0.core ?? "") && $0.core != "dolphin"}){Text($0.title).tag($0.rawValue)}}
  Label(store.controllerName,systemImage:"gamecontroller.fill").font(.title3)
  Picker("Mapping",selection:$tab){Text("Standard systems").tag("Standard");Text("GameCube / Wii gamepad").tag("Dolphin")}.pickerStyle(.segmented)
  if tab=="Standard" {
   Text("Choose the keyboard key and physical gamepad button for each console action. Changes apply when the next game starts.").foregroundStyle(.secondary)
   HStack{Text("Stick dead zone");Slider(value:$bindings.deadZone,in:0...0.9);Text("\(Int(bindings.deadZone*100))%").monospacedDigit()}
   Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:10){
    GridRow{Text("Console action").bold();Text("Keyboard").bold();Text("Gamepad button").bold()}
    ForEach(ControllerBindings.actions,id:\.self){action in GridRow{
     Text(action).frame(width:90,alignment:.leading)
     Picker(action,selection:Binding(get:{bindings.keyboard[action] ?? 65535},set:{bindings.keyboard[action]=$0})){ForEach(ControllerBindings.keys,id:\.1){key in Text(key.0).tag(key.1)}}.labelsHidden().frame(width:150)
     Picker(action,selection:Binding(get:{bindings.gamepad[action] ?? "None"},set:{bindings.gamepad[action]=$0})){ForEach(ControllerBindings.padInputs,id:\.self){Text($0).tag($0)}}.labelsHidden().frame(width:150)
    }}
   }
  }else{
   Text("Native Dolphin profiles are edited in Emulator Settings when native settings are enabled.").font(.caption)
   Text("Map the GameCube controller used by GameCube games and compatible Wii games. Dolphin device identifiers and input expressions can be entered here without opening an emulator settings window.").foregroundStyle(.secondary)
   Picker("Wii controller",selection:Binding(get:{bindings.wiiMode ?? "Nunchuk"},set:{bindings.wiiMode=$0})){Text("Wii Remote + Nunchuk").tag("Nunchuk");Text("Classic Controller").tag("Classic");Text("Sideways Wii Remote").tag("Sideways")}
   Text("With Automatic selected in the game profile, connected gamepads (including DualSense) use native stick, trigger and face-button mappings. Wii: right stick points; right-stick click shakes.").font(.caption)
   TextField("Device",text:$bindings.gameCubeDevice)
   Text("Keyboard device: Quartz/0/Keyboard & Mouse. Key expressions use backticks, for example `X` or `Return`. Hardware devices use their Dolphin SDL identifier.").font(.caption).foregroundStyle(.secondary)
   ForEach(bindings.gameCube.keys.sorted(),id:\.self){action in HStack{Text(action).frame(width:180,alignment:.leading);TextField("Input expression",text:Binding(get:{bindings.gameCube[action] ?? ""},set:{bindings.gameCube[action]=$0}))}}
  }
  HStack{Button("Save mappings"){saveBindings()}.buttonStyle(.borderedProminent);Button("Restore defaults"){bindings=ControllerBindings();saveBindings()}}
  if store.activity=="Controller mappings saved"{Text(store.activity).foregroundStyle(.green)}
  Text("Mappings are saved in your configured Controller Profiles location. Select Keyboard in a system profile to disable physical gamepad input for libretro games.").font(.caption).foregroundStyle(.secondary)
 }.onAppear{loadBindings()}.onChange(of:scope){_,_ in loadBindings()}}
 func loadBindings(){store.attempt{if scope=="global"{bindings=store.controllerBindings}else{let file=try store.directory(.controllers).appendingPathComponent(scope+".json");bindings=FileManager.default.fileExists(atPath:file.path) ? try JSONStore.read(ControllerBindings.self,from:file):store.controllerBindings}}}
 func saveBindings(){store.attempt{try bindings.validate();if scope=="global"{store.controllerBindings=bindings;store.saveControllers()}else{try JSONStore.write(bindings,to:store.directory(.controllers).appendingPathComponent(scope+".json"));store.activity="Controller mappings saved"}}}
}
