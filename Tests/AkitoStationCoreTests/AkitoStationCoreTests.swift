import XCTest
@testable import AkitoStationCore
final class AkitoStationCoreTests:XCTestCase {
 func testArtworkSearchNormalizesFilenameTagsAndAccents() {
 XCTAssertTrue(ArtworkCache.titleMatches("Pokemon - Emerald (Europe)",query:"Pokémon Emerald (USA) [!]"))
 XCTAssertTrue(ArtworkCache.titleMatches("Legend of Zelda, The - Link's Awakening (USA)",query:"The Legend of Zelda: Link’s Awakening"))
 XCTAssertFalse(ArtworkCache.titleMatches("Super Mario World (USA)",query:"Super Mario World 2"))
 XCTAssertFalse(ArtworkCache.titleMatches("Super Mario World",query:"[!]"))
 }
 func testArtworkTitleMatchingPreservesSequels() {
 XCTAssertEqual(ArtworkCache.matchingTitle("Pokémon - Emerald (USA) [!]"),"pokemon emerald")
 XCTAssertEqual(ArtworkCache.matchingTitle("Super Mario World (Europe)"),ArtworkCache.matchingTitle("Super Mario World (USA)"))
 XCTAssertNotEqual(ArtworkCache.matchingTitle("Super Mario World"),ArtworkCache.matchingTitle("Super Mario World 2"))
 }
 var temp:URL!
 override func setUpWithError()throws{temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)}
 override func tearDownWithError()throws{try FileManager.default.removeItem(at:temp)}
 func testGraphicsPreservesUnrelatedSettingsAndBackup()throws {
 let dir=temp.appendingPathComponent("inis");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
 let file=dir.appendingPathComponent("PCSX2.ini")
 let original="[BIOS]\nFilename=original.bin\n[EmuCore/GS]\nRenderer=17\nupscale_multiplier=1\n[Pad1]\nCross=SDL-0/A\n"
 try Data(original.utf8).write(to:file)
 var profile=GameProfile();GraphicsConfiguration.applyPreset("Quality",to:&profile)
 try GraphicsConfiguration.prepare(engine:"armsx2",data:temp,profile:profile)
 let updated=try String(contentsOf:file)
 XCTAssertTrue(updated.contains("Filename=original.bin"));XCTAssertTrue(updated.contains("Cross=SDL-0/A"));XCTAssertTrue(updated.contains("upscale_multiplier=3"))
 XCTAssertEqual(try String(contentsOf:file.appendingPathExtension("before-arm-graphics")),original)
 GraphicsConfiguration.applyPreset("Performance",to:&profile);try GraphicsConfiguration.prepare(engine:"armsx2",data:temp,profile:profile)
 XCTAssertEqual(try String(contentsOf:file.appendingPathExtension("before-arm-graphics")),original)
 XCTAssertFalse(profile.coreOptions.contains("arm.graphics"))
 }
 func testVitaGraphicsRepairsDocumentEndAndDuplicateKeys()throws {
 let file=temp.appendingPathComponent("config.yml")
 try Data("---\nv-sync: false\ncontroller-binds:\n  - 7\n...\nbackend-renderer: OpenGL\nbackend-renderer: Vulkan\n".utf8).write(to:file)
 try GraphicsConfiguration.prepare(engine:"vita3k",data:temp,profile:GameProfile())
 let updated=try String(contentsOf:file)
 XCTAssertFalse(updated.contains("..."));XCTAssertTrue(updated.contains("controller-binds:\n  - 7"))
 XCTAssertEqual(updated.components(separatedBy:"backend-renderer:").count,2)
 XCTAssertTrue(updated.contains("v-sync: true"))
 }
 func testSwitchGraphicsPreservesControllerObjects()throws {
 let file=temp.appendingPathComponent("Config.json")
 try Data(#"{"input_config":[{"id":"dualsense","deadzone":0.1}],"version":71}"#.utf8).write(to:file)
 try GraphicsConfiguration.prepare(engine:"ryujinx",data:temp,profile:GameProfile())
 let json=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
 XCTAssertEqual((json["input_config"] as? [[String:Any]])?.first?["id"] as? String,"dualsense")
 XCTAssertEqual(json["graphics_backend"] as? String,"Vulkan")
 XCTAssertEqual(json["res_scale"] as? Int,1)
 }
 func testCemuGraphicsPreservesPacksAndAccounts()throws {
 let folder=temp.appendingPathComponent("home/Library/Application Support/Cemu");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 let file=folder.appendingPathComponent("settings.xml")
 let original="<content><Graphic><api>0</api><VSync>0</VSync></Graphic><GraphicPack><Entry filename=\"game/rules.txt\"/></GraphicPack><Account><id>original</id></Account></content>"
 try Data(original.utf8).write(to:file)
 try GraphicsConfiguration.prepare(engine:"cemu",data:temp,profile:GameProfile())
 let text=try String(contentsOf:file)
 XCTAssertTrue(text.contains("<api>1</api>"));XCTAssertTrue(text.contains("<VSync>1</VSync>"))
 XCTAssertTrue(text.contains("filename=\"game/rules.txt\""));XCTAssertTrue(text.contains("<id>original</id>"))
 XCTAssertEqual(try String(contentsOf:file.appendingPathExtension("before-arm-graphics")),original)
 }
 func testResourceImportKeepsOriginalAndRoutesBIOS()throws {
 let source=temp.appendingPathComponent("bios7.bin");let data=Data(repeating:7,count:16384);try data.write(to:source)
 let root=temp.appendingPathComponent("managed");let entry=try ConsoleResources.importFile(source,root:root,platform:.nds)
 XCTAssertFalse(entry.installationRequired);XCTAssertEqual(try Data(contentsOf:source),data)
 let folder=try ConsoleResources.directory(root:root,platform:.nds)
 let copied=folder.appendingPathComponent(entry.id).appendingPathComponent(entry.filename)
 XCTAssertEqual(try digest(copied),entry.sha256)
 let cache=temp.appendingPathComponent("cache")
 let routed=try SystemResourceRouter.prepare(core:"melondsds",source:temp.appendingPathComponent("absent-original-library"),cache:cache,imported:[copied])
 XCTAssertEqual(try Data(contentsOf:routed.appendingPathComponent("bios7.bin")),data)
 XCTAssertEqual(try ConsoleResources.entries(root:root,platform:.nds).count,1)
 }
 func testResourceImportRejectsSymlinksAndStagesFirmware()throws {
 let source=temp.appendingPathComponent("PS3UPDAT.PUP");try Data([1,2,3]).write(to:source)
 let root=temp.appendingPathComponent("managed")
 XCTAssertTrue(try ConsoleResources.importFile(source,root:root,platform:.ps3).installationRequired)
 let link=temp.appendingPathComponent("link.pup");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:source)
 XCTAssertThrowsError(try ConsoleResources.importFile(link,root:root,platform:.ps3))
 }
 func testDetection(){XCTAssertEqual(Platform.detect(URL(fileURLWithPath:"/games/ps2/test.iso")),.ps2);XCTAssertEqual(Platform.detect(URL(fileURLWithPath:"/games/test.iso")),.unknown);XCTAssertEqual(Platform.detect(URL(fileURLWithPath:"/game.bin"),header:Data([0x4e,0x45,0x53,0x1a])),.nes);XCTAssertEqual(Platform.detect(URL(fileURLWithPath:"/games/MARIO.GBA")),.gba)}
 func testIndexAndMerge()throws{let rom=temp.appendingPathComponent("Test.nes");try Data([0x4e,0x45,0x53,0x1a]).write(to:rom);try Data().write(to:temp.appendingPathComponent("._ghost.nes"));try Data().write(to:temp.appendingPathComponent("readme.txt"));let games=try LibraryScanner.scan([Location(temp),Location(temp)]);XCTAssertEqual(games.count,1);var old=games[0];old.favorite=true;old.playSeconds=40;let merged=LibraryScanner.merge(games,existing:[old]);XCTAssertTrue(merged[0].favorite);XCTAssertEqual(merged[0].playSeconds,40)}
 func testMissingVolumeFails()throws{let dir=temp.appendingPathComponent("volume");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);let loc=Location(dir);try FileManager.default.removeItem(at:dir);XCTAssertThrowsError(try loc.resolve());XCTAssertThrowsError(try StorageConfiguration(root:loc).directory(.saves));XCTAssertFalse(FileManager.default.fileExists(atPath:dir.path))}
 func testVolumeMismatch()throws{var loc=Location(temp);loc.volumeUUID="wrong-volume";XCTAssertThrowsError(try loc.resolve())}
 func testStorageOverrides()throws{let other=temp.appendingPathComponent("custom");try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true);var s=StorageConfiguration(root:Location(temp));s.overrides["saves"]=Location(other);XCTAssertEqual(try s.directory(.saves).standardizedFileURL,other.standardizedFileURL);XCTAssertEqual(try s.directory(.states).lastPathComponent,"states")}
 func testProfilePersistenceAndTranslation()throws{var p=GameProfile();p.options=["z":"enabled","a":"disabled"];p.volume=0.4;p.knownGoodRuntime="rev123";let url=temp.appendingPathComponent("profile.json");try JSONStore.write(p,to:url);XCTAssertEqual(try JSONStore.read(GameProfile.self,from:url),p);XCTAssertEqual(p.coreOptions,"a=disabled\nz=enabled")}
 func install(_ version:String,validated:Bool=true)throws->RuntimeManager{let folder=temp.appendingPathComponent("nestopia/\(version)");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let bin=folder.appendingPathComponent("core.dylib");try Data(version.utf8).write(to:bin);let m=RuntimeManifest(id:"nestopia",version:version,upstream:"https://github.com/libretro/nestopia",revision:version,library:"core.dylib",sha256:try digest(bin),license:"GPL-2.0",validated:validated);try JSONStore.write(m,to:folder.appendingPathComponent("manifest.json"));return RuntimeManager(root:temp)}
 func testActivationRollbackAndIntegrity()throws{let m=try install("one");_=try install("two");try m.activate("nestopia",version:"one");try m.activate("nestopia",version:"two");XCTAssertEqual(try m.selection("nestopia").previous,"one");try m.rollback("nestopia");XCTAssertEqual(try m.selected("nestopia").0.version,"one");try Data("tampered".utf8).write(to:temp.appendingPathComponent("nestopia/one/core.dylib"));XCTAssertThrowsError(try m.selected("nestopia"))}
 func testRuntimeDiscoveryIgnoresAssetManifests()throws {
 let manager=try install("assets")
 let asset=temp.appendingPathComponent("nestopia/assets/PPSSPP/debugger")
 try FileManager.default.createDirectory(at:asset,withIntermediateDirectories:true)
 try Data("{\"name\":\"debugger\"}".utf8).write(to:asset.appendingPathComponent("manifest.json"))
 XCTAssertEqual(try manager.manifests().map(\.version),["assets"])
 }
 func testKeyboardTapSurvivesUntilFrameSample(){
 var input=KeyboardInput();input.press(3);input.release(3)
 XCTAssertTrue(input.active.contains(3));input.didRunFrame();XCTAssertFalse(input.active.contains(3))
 input.press(7);input.didRunFrame();XCTAssertTrue(input.active.contains(7))
 input.clear();XCTAssertTrue(input.active.isEmpty)
 }
 func testDolphinGamepadProfiles(){
 let bindings=ControllerBindings()
 XCTAssertTrue(bindings.dolphinGamepadINI().contains("Buttons/A = `Button S`"))
 XCTAssertTrue(bindings.dolphinGamepadINI().contains("Main Stick/Up = `Left Y+`"))
 XCTAssertTrue(bindings.dolphinWiiINI(mode:"Classic").contains("Extension = Classic"))
 XCTAssertTrue(bindings.dolphinWiiINI(mode:"Sideways").contains("Options/Sideways Wiimote = True"))
 }
 func testPS3LaunchUsesManagedStorage()throws{
 let home=temp.appendingPathComponent("home"),cache=temp.appendingPathComponent("cache"),firmware=temp.appendingPathComponent("firmware")
 for folder in [home,cache,firmware.appendingPathComponent("sys/external")]{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
 try Data([0]).write(to:firmware.appendingPathComponent("sys/external/liblv2.sprx"))
 let game=temp.appendingPathComponent("EBOOT.BIN");try Data([0]).write(to:game)
 let launch=try RPCS3Launch(game:game,profile:GameProfile(),managedHome:home,caches:cache,firmware:firmware)
 XCTAssertEqual(launch.environment["HOME"],home.path);XCTAssertEqual(launch.arguments.first,"--no-gui");XCTAssertEqual(launch.arguments.last,game.path)
 XCTAssertEqual(home.appendingPathComponent("Library/Caches/rpcs3").resolvingSymlinksInPath().path,cache.path)
 }
 func testPS3RejectsMissingFirmware()throws{
 let game=temp.appendingPathComponent("EBOOT.BIN");try Data([0]).write(to:game)
 XCTAssertThrowsError(try RPCS3Launch(game:game,profile:GameProfile(),managedHome:temp,caches:temp,firmware:temp))
 }
 func testUnvalidatedRuntimeRefused()throws{let m=try install("candidate",validated:false);XCTAssertThrowsError(try m.activate("nestopia",version:"candidate"));XCTAssertThrowsError(try m.selected("nestopia",version:"../candidate"))}
 func testVerifiedMigrationRetainsSource()throws{let src=temp.appendingPathComponent("source"),dst=temp.appendingPathComponent("destination");try FileManager.default.createDirectory(at:src,withIntermediateDirectories:true);try Data("save bytes".utf8).write(to:src.appendingPathComponent("save"));try StorageMover.copyVerified(from:src,to:dst);XCTAssertEqual(try digest(src.appendingPathComponent("save")),try digest(dst.appendingPathComponent("save")));XCTAssertThrowsError(try StorageMover.copyVerified(from:src,to:src.appendingPathComponent("nested")))}
 func testUpdateMetadata()throws{let data=Data(#"{"tag_name":"v1.2","html_url":"https://github.com/example/core/releases/tag/v1.2","prerelease":false,"body":"Fixes"}"#.utf8);let release=try JSONDecoder().decode(UpstreamRelease.self,from:data);XCTAssertEqual(release.tag_name,"v1.2");XCTAssertFalse(release.prerelease)}
}
extension AkitoStationCoreTests {
 func testProcessLifecycle()async throws{let r=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/true"),arguments:[],log:temp.appendingPathComponent("run.log"));XCTAssertEqual(r.exitCode,0)}
 func testProcessTimeout()async throws{do{_=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/bin/sleep"),arguments:["20"],log:temp.appendingPathComponent("timeout.log"),timeout:0.1);XCTFail("Expected timeout")}catch{XCTAssertTrue(error.localizedDescription.contains("time limit"))}}
 func testResourceRoutingPreservesOriginal()throws{let src=temp.appendingPathComponent("supplied"),cache=temp.appendingPathComponent("cache");try FileManager.default.createDirectory(at:src,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true);let bios=src.appendingPathComponent("SCPH-5501.BIN");try Data("supplied test resource".utf8).write(to:bios);let before=try digest(bios);let routed=try SystemResourceRouter.prepare(core:"pcsx_rearmed",source:src,cache:cache);XCTAssertEqual(try digest(routed.appendingPathComponent("scph5501.bin")),before);XCTAssertEqual(try digest(bios),before)}
 func testLaunchRouting(){XCTAssertEqual(Platform.nes.core,"nestopia");XCTAssertEqual(Platform.gbc.core,"gambatte");XCTAssertEqual(Platform.ps1.core,"duckstation");XCTAssertEqual(Platform.ps4.core,"shadps4")}
}
extension AkitoStationCoreTests {
 func testNestedRuntimeAndEscapes()throws {
  let manager=try install("nested"),folder=temp.appendingPathComponent("nestopia/nested"),manifest=folder.appendingPathComponent("manifest.json")
  var m=try JSONStore.read(RuntimeManifest.self,from:manifest)
  let nested=folder.appendingPathComponent("Player.app/Contents/MacOS")
  try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:true)
  try FileManager.default.copyItem(at:folder.appendingPathComponent("core.dylib"),to:nested.appendingPathComponent("core"))
  m.library="Player.app/Contents/MacOS/core";try JSONStore.write(m,to:manifest)
  XCTAssertNoThrow(try manager.selected("nestopia",version:"nested"))
  for path in ["../nested/core.dylib","/core.dylib","Player.app//core","Player.app/../core.dylib"]{m.library=path;try JSONStore.write(m,to:manifest);XCTAssertThrowsError(try manager.selected("nestopia",version:"nested"))}
  try FileManager.default.createSymbolicLink(at:folder.appendingPathComponent("escape"),withDestinationURL:temp)
  m.library="escape/nestopia/nested/core.dylib";try JSONStore.write(m,to:manifest)
  // A link resolving within the version remains contained; an external file must fail.
  let outside=temp.appendingPathComponent("outside");try Data("nested".utf8).write(to:outside)
  m.library="escape/outside";try JSONStore.write(m,to:manifest);XCTAssertThrowsError(try manager.selected("nestopia",version:"nested"))
 }
 func testDolphinTranslationAndMissingStorage()throws {
  var p=GameProfile();p.resolutionScale=3;p.volume=0.5
  let binary=temp.appendingPathComponent("engine"),game=temp.appendingPathComponent("game.rvz")
  let launch=try DolphinLaunch(binary:binary,game:game,profile:p,saves:temp,states:temp,caches:temp,screenshots:temp)
  XCTAssertTrue(launch.arguments.contains("GFX.Settings.InternalResolution=3"));XCTAssertTrue(launch.arguments.contains("Dolphin.DSP.Volume=50"));XCTAssertEqual(launch.environment["ARM_DOLPHIN_STATES"],temp.path)
  XCTAssertEqual(Platform.gc.core,"dolphin");XCTAssertEqual(Platform.wii.core,"dolphin")
  XCTAssertThrowsError(try DolphinLaunch(binary:binary,game:game,profile:p,saves:temp,states:temp.appendingPathComponent("missing"),caches:temp,screenshots:temp))
 }
}
extension AkitoStationCoreTests {
 func testCustomControllerMappingsPersistAndTranslate()throws {
  var b=ControllerBindings();b.keyboard["A"]=49;b.gamepad["A"]="R1";b.deadZone=0.35;b.gameCube["Buttons/A"]="`Space`"
  try b.validate();let url=temp.appendingPathComponent("bindings.json");try JSONStore.write(b,to:url);XCTAssertEqual(try JSONStore.read(ControllerBindings.self,from:url),b);XCTAssertTrue(b.dolphinPadINI().contains("Buttons/A = `Space`"))
  b.gameCubeDevice="bad\n[Core]";XCTAssertThrowsError(try b.validate())
  b=ControllerBindings();b.gamepad["A"]="invalid";XCTAssertThrowsError(try b.validate())
 }
}
extension AkitoStationCoreTests {
 func sfo(_ values:[String:String])->Data {
 var keys=Data(),strings=Data(),entries=Data()
 func le(_ n:Int,_ bytes:Int)->Data{Data((0..<bytes).map{UInt8((n >> ($0*8)) & 255)})}
 for (key,value) in values.sorted(by:{$0.key<$1.key}){let text=Data(value.utf8)+Data([0]);entries+=le(keys.count,2)+le(0x0204,2)+le(text.count,4)+le(text.count,4)+le(strings.count,4);keys+=Data(key.utf8)+Data([0]);strings+=text}
 return Data([0,80,83,70])+le(0x101,4)+le(20+entries.count,4)+le(20+entries.count+keys.count,4)+le(values.count,4)+entries+keys+strings
 }
 func testPS3InstalledGamesExcludeUpdatesAndDLC()throws {
 for (id,category) in [("NPUA00001","HG"),("BCUS00002","GD"),("NPUA00003","AC")]{let folder=temp.appendingPathComponent(id);try FileManager.default.createDirectory(at:folder.appendingPathComponent("USRDIR"),withIntermediateDirectories:true);try Data([1]).write(to:folder.appendingPathComponent("USRDIR/EBOOT.BIN"));try sfo(["TITLE":"Digital Game","TITLE_ID":id,"CATEGORY":category]).write(to:folder.appendingPathComponent("PARAM.SFO"))}
 let games=try LibraryScanner.scan([Location(temp),Location(temp)]);XCTAssertEqual(games.count,1);XCTAssertEqual(games.first?.title,"Digital Game");XCTAssertEqual(games.first?.platform,.ps3)
 }
 func testPS4AndVitaFoldersWithSharedModuleDirectory()throws {
 for (path,id,expected) in [("psvita/PS4 Game","CUSA00001",Platform.ps4),("ps4/Vita Game","PCSE00001",.psvita),("ps4/No ID","",.ps4),("psvita/No ID","",.psvita)] {
 let folder=temp.appendingPathComponent(path)
 for child in ["sce_sys","sce_module"] {try FileManager.default.createDirectory(at:folder.appendingPathComponent(child),withIntermediateDirectories:true)}
 try Data([1]).write(to:folder.appendingPathComponent("eboot.bin"))
 try sfo(["TITLE":"Game","TITLE_ID":id]).write(to:folder.appendingPathComponent("sce_sys/param.sfo"))
 let game=try XCTUnwrap(ConsoleFolder.game(at:folder,root:temp))
 XCTAssertEqual(game.platform,expected,path)
 var old=game;old.platform = .psvita;old.favorite=true
 let merged=LibraryScanner.merge([game],existing:[old])
 XCTAssertEqual(merged.first?.platform,expected);XCTAssertEqual(merged.first?.favorite,true)
 }
 }
 func testMalformedSFOIsBounded()throws{let file=temp.appendingPathComponent("PARAM.SFO");try Data([0,80,83,70]+Array(repeating:255,count:40)).write(to:file);XCTAssertTrue(try ParamSFO.read(file).isEmpty)}
 func testManagedPS2LaunchKeepsPathAsSingleArgument()throws{let ini=temp.appendingPathComponent("inis/PCSX2.ini");try FileManager.default.createDirectory(at:ini.deletingLastPathComponent(),withIntermediateDirectories:true);try Data().write(to:ini);let rom=URL(fileURLWithPath:"/games/a game.iso");let launch=try ManagedLaunch(engine:"armsx2",binary:temp,game:rom,profile:GameProfile(),data:temp,caches:temp.appendingPathComponent("cache"));XCTAssertEqual(launch.arguments.last,rom.path);XCTAssertTrue(launch.arguments.contains("-nogui"));XCTAssertEqual(launch.environment["HOME"],temp.appendingPathComponent("home").path)}
}
