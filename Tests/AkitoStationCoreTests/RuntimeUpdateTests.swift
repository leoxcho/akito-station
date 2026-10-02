import XCTest
@testable import AkitoStationCore

final class RuntimeUpdateTests:XCTestCase {
 func testEngineCompatibilityAndPersistence()throws {
  for platform in Platform.allCases where platform.core != nil {
   XCTAssertFalse(EmulatorEngines.choices(for:platform,installed:[]).isEmpty)
  }
  XCTAssertEqual(EmulatorEngines.selected(for:.switchConsole,choice:"ryujinx",installed:[]),"ryujinx")
  XCTAssertEqual(EmulatorEngines.selected(for:.nes,choice:"pcsx_rearmed",installed:[]),"nestopia")
  XCTAssertEqual(EmulatorEngines.selected(for:.ps1,choice:"pcsx_rearmed",installed:[]),"pcsx_rearmed")
  var core=RuntimeManifest(id:"test_core",version:"1",upstream:"local",revision:"1",library:"core.dylib",sha256:"hash",license:"MIT",validated:true)
  core.platforms=[.nes,.saturn];core.capabilities += ["libretro"]
  let decoded=try JSONDecoder().decode(RuntimeManifest.self,from:JSONEncoder().encode(core))
  XCTAssertEqual(EmulatorEngines.selected(for:.saturn,choice:"test_core",installed:[decoded]),"test_core")
  XCTAssertTrue(EmulatorEngines.choices(for:.nes,installed:[decoded]).contains("test_core"))
  XCTAssertFalse(EmulatorEngines.choices(for:.snes,installed:[decoded]).contains("test_core"))
  core.validated=false
  XCTAssertFalse(EmulatorEngines.choices(for:.nes,installed:[core]).contains("test_core"))
  core.validated=true;core.capabilities.removeAll{$0=="libretro"}
  XCTAssertFalse(EmulatorEngines.choices(for:.nes,installed:[core]).contains("test_core"))
 }
 func testPCSX2OnlyBelongsToPS2()throws {
  var runtime=RuntimeManifest(id:"pcsx2",version:"2.9.66",upstream:"https://github.com/PCSX2/pcsx2",revision:"2.9.66",library:"PCSX2.app/Contents/MacOS/PCSX2",sha256:"hash",license:"GPL",validated:true)
  runtime.platforms=[.ps1] // A bad manifest cannot override the adapter's console mapping.
  for platform in Platform.allCases {
   XCTAssertEqual(EmulatorEngines.choices(for:platform,installed:[runtime]).contains("pcsx2"),platform == .ps2)
  }
  XCTAssertEqual(EmulatorEngines.selected(for:.ps2,choice:"pcsx2",installed:[runtime]),"pcsx2")
  XCTAssertThrowsError(try RuntimeSource(name:"PCSX2",repository:"https://github.com/PCSX2/pcsx2",engine:"duckstation"))
  XCTAssertNoThrow(try RuntimeSource(name:"PCSX2",repository:"https://github.com/PCSX2/pcsx2",engine:"pcsx2"))
 }
 func testPCSX2LaunchUsesIsolatedPS2Data()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  let ini=root.appendingPathComponent("inis/PCSX2.ini")
  try FileManager.default.createDirectory(at:ini.deletingLastPathComponent(),withIntermediateDirectories:true)
  try Data("[EmuCore/GS]\nRenderer = 17\n".utf8).write(to:ini)
  let game=URL(fileURLWithPath:"/games/PS2/My Game.iso")
  let launch=try ManagedLaunch(engine:"pcsx2",binary:root,game:game,profile:GameProfile(),data:root,caches:root.appendingPathComponent("cache"))
  XCTAssertEqual(Array(launch.arguments.prefix(4)),["-nogui","-batch","-datapath",root.path])
  XCTAssertEqual(launch.arguments.last,game.path)
  XCTAssertEqual(EmulatorSettings.files["pcsx2"],["inis/PCSX2.ini"])
 }
 func testRepositoryCanonicalizationAndRejection()throws {
  XCTAssertEqual(try GitHubRepository(" https://github.com/RPCS3/rpcs3.git/ ").url,"https://github.com/RPCS3/rpcs3")
  for url in ["http://github.com/a/b","https://github.com.evil.test/a/b","https://github.com/a/b/releases","https://user@github.com/a/b","https://github.com/a/b?token=secret","https://github.com/a/..","https://github.com/a/b#fragment","https://github.com:443/a/b"] {
   XCTAssertThrowsError(try GitHubRepository(url),url)
  }
 }
 func testCustomSourcePersistenceAndDuplicateDetection()throws {
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
  let file=folder.appendingPathComponent("sources.json")
  let source=try RuntimeSource(name:"",repository:"https://github.com/example/new-emulator.git",engine:"",channel:"prerelease")
  let entries=try RuntimeSource.save(source,to:file)
  XCTAssertEqual(entries[0].name,"new-emulator");XCTAssertEqual(entries[0].channel,"prerelease")
  XCTAssertEqual(try JSONStore.read([RuntimeSource].self,from:file),entries)
  XCTAssertThrowsError(try RuntimeSource.save(RuntimeSource(name:"Duplicate",repository:"https://github.com/EXAMPLE/NEW-EMULATOR"),to:file))
  XCTAssertThrowsError(try RuntimeSource(name:"Bad adapter",repository:source.repository,engine:"../../app"))
 }
 func testReleaseAssetValidationAndArchitectureHints()throws {
  let json="""
  {"tag_name":"v2","html_url":"https://github.com/example/emu/releases/tag/v2","prerelease":false,"assets":[{"id":12,"name":"emu-macos-arm64.zip","browser_download_url":"https://github.com/example/emu/releases/download/v2/emu-macos-arm64.zip","size":123}]}
  """
  let release=try JSONDecoder().decode(RuntimeRelease.self,from:Data(json.utf8))
  var asset=release.assets[0];XCTAssertNil(asset.digest);XCTAssertTrue(asset.isMacCandidate)
  XCTAssertEqual(try GitHubUpdates.downloadURL(asset,repository:"https://github.com/example/emu").host,"github.com")
  XCTAssertThrowsError(try GitHubUpdates.downloadURL(asset,repository:"https://github.com/another/repo"))
  asset.name="../escape.zip";XCTAssertThrowsError(try GitHubUpdates.downloadURL(asset,repository:"https://github.com/example/emu"))
  asset.name="emu-macos-x64.zip";XCTAssertFalse(asset.isMacCandidate)
  XCTAssertEqual(GitHubUpdates.releaseRepository(engine:"rpcs3",upstream:"https://github.com/RPCS3/rpcs3"),"https://github.com/RPCS3/rpcs3-binaries-mac-arm64")
 }
 func testLiveGitHubReleaseAndSourceLookup()async throws {
  guard ProcessInfo.processInfo.environment["ARM_LIVE_GITHUB"]=="1" else{throw XCTSkip("Set ARM_LIVE_GITHUB=1 for the optional public GitHub check")}
  let releases=try await GitHubUpdates.releases(repository:"https://github.com/RPCS3/rpcs3-binaries-mac-arm64",channel:"prerelease")
  XCTAssertFalse(releases.isEmpty)
  let asset=try XCTUnwrap(releases.first?.assets.first)
  _=try GitHubUpdates.downloadURL(asset,repository:"https://github.com/RPCS3/rpcs3-binaries-mac-arm64")
  let revision=try await GitHubUpdates.sourceRevision(repository:"https://github.com/libretro/nestopia")
  XCTAssertFalse(revision.isEmpty)
 }

}
