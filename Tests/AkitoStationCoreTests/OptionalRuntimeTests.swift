import XCTest
@testable import AkitoStationCore

final class OptionalRuntimeTests:XCTestCase {
 func testAllConsolesHaveDefinitionsAndCompatibleAlternatives()throws {
  for platform in Platform.allCases where platform != .unknown {XCTAssertFalse(RuntimeCatalog.choices(platform).isEmpty,platform.title)}
  for platform in [Platform.ps1,.ps2,.psp,.switchConsole,.n3ds,.gb,.gbc] {XCTAssertGreaterThan(RuntimeCatalog.choices(platform).count,1)}
  XCTAssertEqual(Set(RuntimeCatalog.definitions.map(\.id)).count,RuntimeCatalog.definitions.count)
  for definition in RuntimeCatalog.definitions {XCTAssertEqual(URL(string:definition.officialSource)?.scheme,"https");if let repo=definition.releaseRepository {XCTAssertNoThrow(try GitHubRepository(repo));XCTAssertEqual(definition.installation,.githubRelease)}}
 }
 func testGameOverrideWinsAndIncompatibleOverrideFailsClosed(){
  XCTAssertEqual(RuntimeCatalog.selected(platform:.ps2,system:"armsx2",game:"pcsx2",installed:[]),"pcsx2")
  XCTAssertEqual(RuntimeCatalog.selected(platform:.ps2,system:"pcsx2",game:nil,installed:[]),"pcsx2")
  XCTAssertNil(RuntimeCatalog.selected(platform:.ps3,system:"rpcs3",game:"pcsx2",installed:[]))
  XCTAssertEqual(RuntimeCatalog.selected(platform:.psp,system:nil,game:"ppsspp_sdl",installed:[]),"ppsspp_sdl")
 }
 func testExternalVerificationUnregisterAndManagedUninstallPreserveUserData()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  let original=root.appendingPathComponent("External/Core.dylib"),folder=root.appendingPathComponent("runtimes/mgba/external")
  try FileManager.default.createDirectory(at:original.deletingLastPathComponent(),withIntermediateDirectories:true)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  try Data("original".utf8).write(to:original)
  var manifest=RuntimeManifest(id:"mgba",version:"external",upstream:"",revision:"1",library:original.lastPathComponent,sha256:try digest(original),license:"test",validated:true)
  manifest.externalLocation=Location(original.deletingLastPathComponent());manifest.platforms=[.gba]
  try JSONStore.write(manifest,to:folder.appendingPathComponent("manifest.json"))
  let manager=RuntimeManager(root:root.appendingPathComponent("runtimes"));try manager.activate("mgba",version:"external")
  XCTAssertEqual(try manager.selected("mgba").1.resolvingSymlinksInPath().path,original.resolvingSymlinksInPath().path)
  try Data("changed by external updater".utf8).write(to:original)
  XCTAssertThrowsError(try manager.selected("mgba"))
  // A missing or updated external binary must still be possible to unregister.
  try manager.unregister("mgba",version:"external")
  XCTAssertEqual(try String(contentsOf:original),"changed by external updater")
  for kind in ["games","saves","firmware","bios","keys","screenshots","profiles","controllers"] {let dir=root.appendingPathComponent(kind);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try Data("retain".utf8).write(to:dir.appendingPathComponent("keep"))}
  let managed=root.appendingPathComponent("runtimes/mgba/v2");try FileManager.default.createDirectory(at:managed,withIntermediateDirectories:true)
  try Data("runtime".utf8).write(to:managed.appendingPathComponent("core.dylib"))
  try manager.uninstall("mgba")
  XCTAssertFalse(FileManager.default.fileExists(atPath:managed.path))
  for kind in ["games","saves","firmware","bios","keys","screenshots","profiles","controllers"] {XCTAssertEqual(try String(contentsOf:root.appendingPathComponent(kind+"/keep")),"retain")}
  XCTAssertThrowsError(try manager.uninstall("../saves"))
  let nested=root.appendingPathComponent("runtimes/mgba/v3/saves");try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:true)
  try Data("retain".utf8).write(to:nested.appendingPathComponent("keep"))
  XCTAssertThrowsError(try manager.uninstall("mgba"));XCTAssertTrue(FileManager.default.fileExists(atPath:nested.appendingPathComponent("keep").path))
 }
 func testDownloadedRuntimeSizeAndChecksumVerification()throws {
  let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:file)}
  try Data("official release fixture".utf8).write(to:file)
  var asset=ReleaseAsset(id:1,name:"macos.zip",browser_download_url:"https://github.com/RPCS3/rpcs3-binaries-mac-arm64/releases/download/test/macos.zip",size:24,digest:"sha256:"+(try digest(file)))
  XCTAssertNoThrow(try GitHubUpdates.verifyDownload(file,asset:asset))
  asset.size=25;XCTAssertThrowsError(try GitHubUpdates.verifyDownload(file,asset:asset));asset.size=24
  try Data("tampered release fixture".utf8).write(to:file)
  XCTAssertThrowsError(try GitHubUpdates.verifyDownload(file,asset:asset))
  asset.digest="sha256:invalid";XCTAssertThrowsError(try GitHubUpdates.verifyDownload(file,asset:asset))
 }
 func testSaturnRoutesOnlyUserSuppliedFirmwareAndPreservesOriginalName()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  let source=root.appendingPathComponent("firmware"),cache=root.appendingPathComponent("cache")
  try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
  try Data("self-authored test fixture".utf8).write(to:source.appendingPathComponent("mpr-17933.bin"))
  try Data("other console".utf8).write(to:source.appendingPathComponent("scph5501.bin"))
  let destination=try SystemResourceRouter.prepare(core:"beetle_saturn",source:source,cache:cache)
  XCTAssertEqual(try Data(contentsOf:destination.appendingPathComponent("mpr-17933.bin")),Data("self-authored test fixture".utf8))
  XCTAssertFalse(FileManager.default.fileExists(atPath:destination.appendingPathComponent("scph5501.bin").path))
  XCTAssertTrue(FileManager.default.fileExists(atPath:source.appendingPathComponent("mpr-17933.bin").path))
 }
 func testDesktopLaunchConfigurationUsesSelectedAdapterAndPathsWithSpaces()throws {
  let game=URL(fileURLWithPath:"/tmp/User games/Game.iso")
  XCTAssertEqual(try RuntimeCatalog.desktopArguments(engine:"rpcs3",platform:.ps3,game:game),["--no-gui",game.path])
  XCTAssertEqual(try RuntimeCatalog.desktopArguments(engine:"dolphin_app",platform:.wii,game:game),["--exec",game.path])
  XCTAssertEqual(try RuntimeCatalog.desktopArguments(engine:"ppsspp_sdl",platform:.psp,game:game),[game.path])
  XCTAssertThrowsError(try RuntimeCatalog.desktopArguments(engine:"pcsx2",platform:.ps3,game:game))
 }
 func testSwitchSelectionHasNoImplicitDefaultAndAdaptersKeepExactPath()throws {
  var eden=RuntimeManifest(id:"eden",version:"1",upstream:"",revision:"",library:"eden",sha256:"",license:"",validated:true)
  eden.platforms=[.switchConsole]
  XCTAssertNil(RuntimeCatalog.selected(platform:.switchConsole,system:nil,game:nil,installed:[eden]))
  XCTAssertNil(EmulatorEngines.selected(for:.switchConsole,choice:nil,installed:[eden]))
  XCTAssertEqual(RuntimeCatalog.selected(platform:.switchConsole,system:"ryujinx",game:"eden",installed:[eden]),"eden")
  for ext in ["xci","nsp","nro","nso","nca","nsz","xcz","ncz"] {
   let game=URL(fileURLWithPath:"/tmp/External Games/日本語 & Game's [1] $."+ext)
   XCTAssertEqual(Platform.detect(game),.switchConsole)
   XCTAssertEqual(try RuntimeCatalog.desktopArguments(engine:"eden",platform:.switchConsole,game:game),["-g",game.path])
   XCTAssertEqual(try RuntimeCatalog.desktopArguments(engine:"ryujinx",platform:.switchConsole,game:game),[game.path])
  }
 }

}
