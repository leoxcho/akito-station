import XCTest
@testable import AkitoStationCore
import Darwin
final class ReleaseHardeningTests:XCTestCase {
 var root:URL!
 override func setUpWithError()throws{root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
 override func tearDownWithError()throws{try? FileManager.default.removeItem(at:root)}
 func manifest(_ id:String="nestopia",_ version:String="one")throws->RuntimeManifest {
  let folder=root.appendingPathComponent(id+"/"+version);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let binary=folder.appendingPathComponent("core.dylib");try Data("fixture".utf8).write(to:binary)
  let manifest=RuntimeManifest(id:id,version:version,upstream:"fixture",revision:"fixture",library:"core.dylib",sha256:try digest(binary),license:"fixture",validated:true)
  try JSONStore.write(manifest,to:folder.appendingPathComponent("manifest.json"));return manifest
 }
 func testCorruptOneOfManyAndRecovery()throws {
  _=try manifest();_=try manifest("snes9x");let manager=RuntimeManager(root:root)
  let file=root.appendingPathComponent("snes9x/one/manifest.json");try Data("{\"id\":".utf8).write(to:file)
  let inventory=try manager.inventory();XCTAssertEqual(inventory.manifests.map(\.id),["nestopia"]);XCTAssertEqual(inventory.damaged.count,1)
  _=try manifest("snes9x");XCTAssertEqual(try manager.inventory().damaged.count,0)
  try Data("[broken]".utf8).write(to:file);let damage=try XCTUnwrap(manager.inventory().damaged.first);try manager.quarantine(damage)
  XCTAssertEqual(try manager.inventory().damaged.count,0);XCTAssertEqual(try manager.manifests().count,1)
  XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("nestopia/one/core.dylib").path))
 }
 func testInvalidManifestPathHashAndMissingBinary()throws {
  var m=try manifest();let manager=RuntimeManager(root:root),file=root.appendingPathComponent("nestopia/one/manifest.json")
  m.library="../escape";try JSONStore.write(m,to:file);XCTAssertEqual(try manager.inventory().damaged.count,1)
  m.library="core.dylib";m.sha256="wrong";try JSONStore.write(m,to:file);XCTAssertEqual(try manager.inventory().damaged.count,1)
  m=try manifest();try manager.activate(m.id,version:m.version)
  try Data("altered".utf8).write(to:root.appendingPathComponent("nestopia/one/core.dylib"));XCTAssertThrowsError(try manager.selected(m.id))
  try FileManager.default.removeItem(at:root.appendingPathComponent("nestopia/one/core.dylib"));XCTAssertThrowsError(try manager.selected(m.id))
  _=try manifest();XCTAssertNoThrow(try manager.selected(m.id))
 }
 func testFailedValidationPreservesPrevious()throws {
  let manager=RuntimeManager(root:root);_=try manifest();try manager.activate("nestopia",version:"one");_=try manifest("nestopia","two");try manager.activate("nestopia",version:"two")
  XCTAssertEqual(try manager.selection("nestopia").previous,"one")
  try Data("altered".utf8).write(to:root.appendingPathComponent("nestopia/one/core.dylib"));XCTAssertThrowsError(try manager.rollback("nestopia"));XCTAssertEqual(try manager.selection("nestopia").current,"two")
  _=try manifest();try manager.rollback("nestopia");XCTAssertEqual(try manager.selection("nestopia").current,"one")
 }
 func testTimeoutAndCancellationCleanDescendants()async throws {
  for cancel in [false,true] {
   let child=root.appendingPathComponent(UUID().uuidString),log=root.appendingPathComponent("log")
   let task=Task{try await ProcessRunner.run(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","/bin/sleep 60 & echo $! > \"$1\"; wait","fixture",child.path],log:log,timeout:cancel ? 60:0.6)}
   for _ in 0..<40{if FileManager.default.fileExists(atPath:child.path){break};try await Task.sleep(nanoseconds:25_000_000)}
   let pid=try XCTUnwrap(Int32(String(contentsOf:child).trimmingCharacters(in:.whitespacesAndNewlines)))
   if cancel{task.cancel()}
   do{_=try await task.value;XCTFail("Operation should stop")}catch{}
   for _ in 0..<40{if kill(pid,0) != 0{break};try await Task.sleep(nanoseconds:25_000_000)}
   XCTAssertNotEqual(kill(pid,0),0,"Descendant survived cleanup")
  }
 }
 func testRedirectAndAssetPolicy()throws {
  XCTAssertFalse(RuntimeDownloadRedirectPolicy.approved(URL(string:"https://evil.example/asset")!));XCTAssertFalse(RuntimeDownloadRedirectPolicy.approved(URL(string:"http://github.com/asset")!));XCTAssertTrue(RuntimeDownloadRedirectPolicy.approved(URL(string:"https://release-assets.githubusercontent.com/asset")!))
  let asset=ReleaseAsset(id:1,name:"mac.zip",browser_download_url:"https://github.com/owner/repo/releases/download/v1/other.zip",size:10,digest:nil)
  XCTAssertThrowsError(try GitHubUpdates.downloadURL(asset,repository:"https://github.com/owner/repo"))
 }
 func testEditionCustomizationSeparation()throws {
  let publicRoot=EditionStorage.customizationRoot(support:root,developer:false),developerRoot=EditionStorage.customizationRoot(support:root,developer:true)
  XCTAssertNotEqual(publicRoot,developerRoot)
  XCTAssertFalse(EditionStorage.ownsWallpaper(developerRoot.appendingPathComponent("wallpaper.png").path,support:root,developer:false))
  XCTAssertTrue(EditionStorage.ownsWallpaper(publicRoot.appendingPathComponent("wallpaper.png").path,support:root,developer:false))
 }
 func testPublisherPolicy()throws {
  XCTAssertThrowsError(try RuntimeBundleIntegrity.classify(signed:true,adhoc:false,team:"WRONG",expectedTeam:"EXPECTED"))
  XCTAssertThrowsError(try RuntimeBundleIntegrity.classify(signed:true,adhoc:true,team:"EXPECTED",expectedTeam:"EXPECTED"))
  XCTAssertTrue(try RuntimeBundleIntegrity.classify(signed:false,adhoc:false,team:nil,expectedTeam:nil).contains("Unsigned"))
  XCTAssertTrue(try RuntimeBundleIntegrity.classify(signed:true,adhoc:false,team:"EXPECTED",expectedTeam:"EXPECTED").contains("Trusted publisher"))
 }
 func testUnsignedBundleNestedTampering()throws {
  let app=root.appendingPathComponent("Unsigned.app"),contents=app.appendingPathComponent("Contents/Frameworks")
  try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
  let dylib=contents.appendingPathComponent("fixture.dylib");try Data("original".utf8).write(to:dylib)
  let recorded=try RuntimeBundleIntegrity.fingerprint(app)
  try Data("altered".utf8).write(to:dylib);XCTAssertNotEqual(try RuntimeBundleIntegrity.fingerprint(app),recorded)
 }
 func testNativeSettingsSelectiveMergeAndOriginalPreservation()throws {
  let incoming="[GPU]\nRenderer=Metal\n[BIOS]\nPath=/original\n",existing="[GPU]\nRenderer=Old\n[BIOS]\nPath=/managed\n"
  let result=try NativeSettingsImport.merge(incoming:incoming,existing:existing,engine:"duckstation",format:"ini")
  XCTAssertTrue(result.contains("Renderer=Metal"));XCTAssertTrue(result.contains("Path=/managed"));XCTAssertFalse(result.contains("/original"))
  let source=root.appendingPathComponent("original.ini"),managed=root.appendingPathComponent("managed"),target=managed.appendingPathComponent("settings.ini")
  try Data(incoming.utf8).write(to:source);try FileManager.default.createDirectory(at:managed,withIntermediateDirectories:true)
  try Data(existing.utf8).write(to:target);try NativeSettingsImport.importFile(source,to:target,managedRoot:managed,engine:"duckstation")
  XCTAssertEqual(try String(contentsOf:source),incoming);XCTAssertEqual(try String(contentsOf:target),result)
  XCTAssertThrowsError(try NativeSettingsImport.importFile(source,to:root.appendingPathComponent("escape.ini"),managedRoot:managed,engine:"duckstation"))
 }
 func testLargeLibraryPresentationPerformance()throws {
  let games=(0..<20000).map{i -> Game in var game=Game(url:root.appendingPathComponent("Game \(20000-i).nes"),root:root,bytes:1);game.favorite=i%2==0;return game}
  let favorites=LibraryPresentation.visible(games,query:"Game",category:"favorites",order:"Title")
  XCTAssertEqual(favorites.count,10000)
  measure{_=LibraryPresentation.visible(games,query:"Game",category:"all",order:"Title")}
 }
 func testFailureCleanupPreservesUnrelatedProcess()async throws {
  let unrelated=Process();unrelated.executableURL=URL(fileURLWithPath:"/bin/sleep");unrelated.arguments=["60"];try unrelated.run();defer{unrelated.terminate();unrelated.waitUntilExit()}
  let child=root.appendingPathComponent("failure-child")
  let result=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","/bin/sleep 60 & echo $! > \"$1\"; exit 7","fixture",child.path],log:root.appendingPathComponent("failure.log"))
  XCTAssertEqual(result.exitCode,7);XCTAssertTrue(unrelated.isRunning)
  let pid=try XCTUnwrap(Int32(String(contentsOf:child).trimmingCharacters(in:.whitespacesAndNewlines)))
  for _ in 0..<40{if kill(pid,0) != 0{break};try await Task.sleep(nanoseconds:25_000_000)}
  XCTAssertNotEqual(kill(pid,0),0)
 }
 func testMalformedExtractionCleansStaging()async throws {
  let archive=root.appendingPathComponent("broken.zip"),stage=root.appendingPathComponent("stage")
  try Data("bad zip".utf8).write(to:archive)
  do{try await RuntimeArchive.extractZIP(archive,to:stage,log:root.appendingPathComponent("archive.log"));XCTFail("Malformed archive accepted")}catch{}
  XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path))
 }
 func testNativeCatalogImportRelinkAndNestedTampering()async throws {
  let app=root.appendingPathComponent("RPCS3.app"),macOS=app.appendingPathComponent("Contents/MacOS")
  try FileManager.default.createDirectory(at:macOS,withIntermediateDirectories:true)
  let source=root.appendingPathComponent("fixture.c");try Data("int main(void){return 0;}".utf8).write(to:source)
  let binary=macOS.appendingPathComponent("fixture"),log=root.appendingPathComponent("native-import.log")
  let compiled=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["clang","-arch","arm64",source.path,"-o",binary.path],log:log)
  XCTAssertEqual(compiled.exitCode,0)
  let unsigned=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/codesign"),arguments:["--remove-signature",binary.path],log:log)
  XCTAssertEqual(unsigned.exitCode,0)
  let info:[String:Any]=["CFBundleExecutable":"fixture","CFBundleIdentifier":"fixture.rpcs3","CFBundleName":"RPCS3","CFBundleShortVersionString":"fixture"]
  try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:app.appendingPathComponent("Contents/Info.plist"))
  let nested=app.appendingPathComponent("Contents/fixture.dylib");try Data("original nested".utf8).write(to:nested)
  let manager=RuntimeManager(root:root.appendingPathComponent("runtimes")),definition=try XCTUnwrap(RuntimeCatalog.definition("rpcs3"))
  let registered=try await manager.importCatalog(input:app,definition:definition,platform:.ps3,managed:false,host:URL(fileURLWithPath:"/usr/bin/true"),log:log)
  XCTAssertEqual(registered.id,"rpcs3");XCTAssertNotNil(registered.externalLocation);XCTAssertNotNil(registered.publisherTrust)
  XCTAssertNoThrow(try manager.selected("rpcs3"))
  try Data("altered nested".utf8).write(to:nested);XCTAssertThrowsError(try manager.selected("rpcs3"))
  let updated=try await manager.importCatalog(input:app,definition:definition,platform:.ps3,managed:true,host:URL(fileURLWithPath:"/usr/bin/true"),log:log)
  XCTAssertNil(updated.externalLocation);XCTAssertEqual(try manager.selection("rpcs3").previous,registered.version)
  XCTAssertNoThrow(try manager.selected("rpcs3"));XCTAssertTrue(FileManager.default.fileExists(atPath:app.path))
 }
 func testPublicUpdateIndependentOfLibraryAndDamagedSelectionRecovery()throws {
  XCTAssertEqual(PublicRuntimeUpdateValidation.coreArguments(gamePath:nil),["--abi-only"])
  XCTAssertEqual(PublicRuntimeUpdateValidation.coreArguments(gamePath:"/User Games/Matching Game.nes"),["--abi-only"])
  let manager=RuntimeManager(root:root);_=try manifest();_=try manifest("nestopia","two")
  try manager.activate("nestopia",version:"one");try manager.activate("nestopia",version:"two")
  try Data("truncated".utf8).write(to:root.appendingPathComponent("nestopia/two/manifest.json"))
  try manager.quarantine(XCTUnwrap(manager.inventory().damaged.first))
  XCTAssertEqual(try manager.selection("nestopia").current,"one");XCTAssertNoThrow(try manager.selected("nestopia"))
 }
 func zip(name:String,expanded:UInt32=1,mode:UInt32=0)->Data {
  func bytes(_ value:UInt64,_ count:Int)->Data{Data((0..<count).map{UInt8((value >> ($0*8)) & 255)})}
  let filename=Data(name.utf8);var d=Data()
  for (value,count) in [(UInt64(0x04034b50),4),(20,2),(0,2),(0,2),(0,4),(0,4),(1,4),(UInt64(expanded),4),(UInt64(filename.count),2),(0,2)]{d.append(bytes(value,count))};d.append(filename);d.append(0)
  let central=d.count
  for (value,count) in [(UInt64(0x02014b50),4),(20,2),(20,2),(0,2),(0,2),(0,4),(0,4),(1,4),(UInt64(expanded),4),(UInt64(filename.count),2),(0,2),(0,2),(0,2),(0,2),(UInt64(mode)<<16,4),(0,4)]{d.append(bytes(value,count))};d.append(filename)
  let centralSize=d.count-central
  for (value,count) in [(UInt64(0x06054b50),4),(0,2),(0,2),(1,2),(1,2),(UInt64(centralSize),4),(UInt64(central),4),(0,2)]{d.append(bytes(value,count))};return d
 }
 func testArchiveTraversalSymlinkBombAndMalformed()throws {
  let file=root.appendingPathComponent("test.zip")
  try zip(name:"safe/file").write(to:file);XCTAssertNoThrow(try RuntimeArchive.inspectZIP(file))
  for name in ["../escape","/absolute","foo/../../escape","a\\b","C:drive"]{try zip(name:name).write(to:file);XCTAssertThrowsError(try RuntimeArchive.inspectZIP(file))}
  try zip(name:"link",mode:0xa000).write(to:file);XCTAssertThrowsError(try RuntimeArchive.inspectZIP(file))
  try zip(name:"bomb",expanded:3_000_000).write(to:file);XCTAssertThrowsError(try RuntimeArchive.inspectZIP(file))
  try Data("truncated".utf8).write(to:file);XCTAssertThrowsError(try RuntimeArchive.inspectZIP(file))
 }
}
