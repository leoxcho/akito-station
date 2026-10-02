import XCTest
@testable import AkitoStationCore

final class EmulatorSettingsTests:XCTestCase {
 var temp:URL!
 override func setUpWithError()throws{temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)}
 override func tearDownWithError()throws{try FileManager.default.removeItem(at:temp)}
 func testINIAndYAMLKeepSectionsCommentsAndBindings()throws {
  let text="[GPU]\nScale = 3 # chosen quality\n[Pad1]\nCross = SDL-0/Button1\n"
  let doc=try NativeSettingsDocument(text:text,format:"ini")
  XCTAssertEqual(doc.fields.count,2)
  let result=try doc.applying([doc.fields[0].id:"4"])
  XCTAssertTrue(result.contains("Scale = 4 # chosen quality"));XCTAssertTrue(result.contains("Cross = SDL-0/Button1"))
  let yaml="Video:\n  Renderer: Vulkan\nInput:\n  Device: \"SDL=a#b\"\n"
  let yd=try NativeSettingsDocument(text:yaml,format:"yml");XCTAssertEqual(yd.fields.count,2);XCTAssertEqual(yd.fields[1].value,"\"SDL=a#b\"")
  XCTAssertEqual(try yd.applying([yd.fields[0].id:"Metal"]),yaml.replacingOccurrences(of:"Vulkan",with:"Metal"))
  XCTAssertThrowsError(try yd.applying([yd.fields[0].id:"Metal\nInjected: true"]))
 }
 func testJSONPreservesTypesAndNestedControllerArrays()throws {
  let doc=try NativeSettingsDocument(text:"{\"res_scale\":2,\"vsync\":true,\"input_config\":[{\"id\":\"pad\",\"deadzone\":0.2}],\"other\":null}",format:"json")
  let scale=try XCTUnwrap(doc.fields.first{$0.key=="res_scale"});let dead=try XCTUnwrap(doc.fields.first{$0.key=="deadzone"})
  let text=try doc.applying([scale.id:"3",dead.id:"0.15"]);let json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any])
  XCTAssertEqual(json["res_scale"] as? Int,3);XCTAssertEqual(json["vsync"] as? Bool,true);XCTAssertTrue(json["other"] is NSNull)
  XCTAssertEqual((json["input_config"] as? [[String:Any]])?.first?["id"] as? String,"pad")
  XCTAssertThrowsError(try doc.applying([scale.id:"true"]))
 }
 func testXMLKeepsDuplicateSiblingsAndAttributes()throws {
  let doc=try NativeSettingsDocument(text:"<content><Graphic><VSync>1</VSync></Graphic><Input><pad id=\"a\"><button>x</button></pad><pad id=\"b\"><button>y</button></pad></Input></content>",format:"xml")
  let field=try XCTUnwrap(doc.fields.last);let result=try doc.applying([field.id:"z"])
  let xml=try XMLDocument(xmlString:result,options:[])
  XCTAssertEqual(try xml.nodes(forXPath:"/content/Input/pad[1]/button").first?.stringValue,"x")
  XCTAssertEqual(try xml.nodes(forXPath:"/content/Input/pad[2]/button").first?.stringValue,"z")
  XCTAssertEqual(try xml.nodes(forXPath:"/content/Input/pad[2]/@id").first?.stringValue,"b")
 }
 func testConcurrentSettingsChangeIsNotOverwritten()throws {
  let file=temp.appendingPathComponent("config.ini");try Data("changed".utf8).write(to:file)
  XCTAssertThrowsError(try EmulatorSettings.save("new",to:file,original:"old"));XCTAssertEqual(try String(contentsOf:file),"changed")
  try EmulatorSettings.save("new",to:file,original:"changed")
  XCTAssertEqual(try String(contentsOf:file.appendingPathExtension("before-arm-settings")),"changed")
 }
 func testNativeGraphicsAreNotReplacedWithGenericPresets()throws {
  var p=GameProfile();p.options["arm.settings.native"]="true";p.resolutionScale=1
  let file=temp.appendingPathComponent("Config.json");let original="{\"res_scale\":5,\"graphics_backend\":\"OpenGl\",\"input_config\":[1]}";try Data(original.utf8).write(to:file)
  try GraphicsConfiguration.prepare(engine:"ryujinx",data:temp,profile:p);XCTAssertEqual(try String(contentsOf:file),original)
 }
 func testNativeDolphinUsesImportedGraphicsAndControllers()throws {
  var p=GameProfile();p.options["arm.settings.native"]="true"
  let source=temp.appendingPathComponent("system");let config=source.appendingPathComponent("Dolphin/Config");try FileManager.default.createDirectory(at:config,withIntermediateDirectories:true)
  let gfx="[Settings]\nEFBScale = 4\n";let pad="[GCPad1]\nDevice = SDL/0/PS5\nButtons/A = `Button 1`\n"
  try Data(gfx.utf8).write(to:config.appendingPathComponent("GFX.ini"));try Data(pad.utf8).write(to:config.appendingPathComponent("GCPadNew.ini"))
  let wii="[Wiimote1]\nDevice = SDL/0/DualSense Wireless Controller\nExtension = Classic\n"
  try Data(wii.utf8).write(to:config.appendingPathComponent("WiimoteNew.ini"))
  let gameSettings=source.appendingPathComponent("Dolphin/GameSettings")
  try FileManager.default.createDirectory(at:gameSettings,withIntermediateDirectories:true)
  let override="[Controls]\nWiimoteProfile1 = Classic\n"
  try Data(override.utf8).write(to:gameSettings.appendingPathComponent("RTEST.ini"))
  let launch=try DolphinLaunch(binary:temp.appendingPathComponent("dolphin"),game:temp,profile:p,saves:temp,states:temp,caches:temp,screenshots:temp,useGamepad:true,nativeSettings:source)
  XCTAssertFalse(launch.arguments.contains("-C"));XCTAssertFalse(launch.arguments.contains("-v"));XCTAssertNil(launch.environment["ARM_DOLPHIN_AUTO_GAMEPAD"])
  XCTAssertEqual(try String(contentsOf:temp.appendingPathComponent("Dolphin/Config/GFX.ini")),gfx)
  XCTAssertEqual(try String(contentsOf:temp.appendingPathComponent("Dolphin/Config/WiimoteNew.ini")),wii)
  XCTAssertEqual(try String(contentsOf:temp.appendingPathComponent("Dolphin/GameSettings/RTEST.ini")),override)
  XCTAssertEqual(try String(contentsOf:temp.appendingPathComponent("Dolphin/Config/GCPadNew.ini")),pad)
 }
 func testDuckStationLaunchIsIsolatedAndKeepsGamePath()throws {
  let settings=temp.appendingPathComponent("home/Library/Application Support/DuckStation/settings.ini");try FileManager.default.createDirectory(at:settings.deletingLastPathComponent(),withIntermediateDirectories:true);try Data("[GPU]\nResolutionScale = 3\n".utf8).write(to:settings)
  let launch=try ManagedLaunch(engine:"duckstation",binary:temp,game:URL(fileURLWithPath:"/games/a game.cue"),profile:GameProfile(),data:temp,caches:temp)
  XCTAssertEqual(launch.arguments,["-batch","-nogui","--","/games/a game.cue"]);XCTAssertEqual(launch.environment["HOME"],temp.appendingPathComponent("home").path)
 }
 func testQtOverridesAndVitaControllerSequences()throws {
  let qt=try NativeSettingsDocument(text:"[Renderer]\nresolution_factor=1\nresolution_factor\\default=true\n",format:"ini")
  let result=try qt.applying([qt.fields[0].id:"3"]);let fields=try NativeSettingsDocument(text:result,format:"ini").fields;XCTAssertEqual(fields.first{$0.key=="resolution_factor"}?.value,"3");XCTAssertEqual(fields.first{$0.key=="resolution_factor\\default"}?.value,"false")
  let vita=try NativeSettingsDocument(text:"controller-binds:\n  - 0\n  - 1\n",format:"yml");XCTAssertEqual(vita.fields.count,2)
  XCTAssertEqual(try vita.applying([vita.fields[1].id:"4"]),"controller-binds:\n  - 0\n  - 4\n")
 }
 func testCemuPresetChangesKeepOtherPacks()throws {
  let pack=CemuGraphicsPack(id:"graphicPacks/Test/rules.txt",title:"Test",presets:["Resolution":["1080p","4K"]])
  let original="<content><GraphicPack><Entry filename=\"other\"/></GraphicPack><Graphic><VSync>0</VSync></Graphic></content>"
  let result=try pack.updating(original,enabled:true,category:"Resolution",preset:"4K")
  XCTAssertEqual(try pack.selection(in:result).1["Resolution"],"4K");XCTAssertTrue(result.contains("filename=\"other\""));XCTAssertTrue(result.contains("<VSync>0</VSync>"))
  XCTAssertThrowsError(try pack.updating(result,enabled:true,category:"Resolution",preset:"invented"))
 }
 func testNativePSPUsesInstalledVersionConfigLayout()throws {
  let dir=temp.appendingPathComponent("home/.config/ppsspp/PSP/SYSTEM");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  try Data("[Graphics]\nInternalResolution=4\nVSync=False\n".utf8).write(to:dir.appendingPathComponent("ppsspp.ini"));try Data("[ControlMapping]\nCross=1-54\n".utf8).write(to:dir.appendingPathComponent("controls.ini"))
  let launch=try ManagedLaunch(engine:"ppsspp_sdl",binary:temp,game:temp.appendingPathComponent("game.iso"),profile:GameProfile(),data:temp,caches:temp)
  XCTAssertTrue(launch.arguments.contains("--appendconfig="+dir.appendingPathComponent("ppsspp.ini").path));XCTAssertEqual(launch.environment["HOME"],temp.appendingPathComponent("home").path)
 }
 func testCoreOptionDefinitionsExposeEveryChoiceAndDefault()throws {
  let option=try XCTUnwrap(CoreOption(key:"ppsspp_internal_resolution",definition:"Internal resolution; 480x272|960x544|1440x816"))
  XCTAssertEqual(option.title,"Internal resolution");XCTAssertEqual(option.values,["480x272","960x544","1440x816"])
  XCTAssertNil(CoreOption(key:"bad",definition:"malformed"))
 }
}
