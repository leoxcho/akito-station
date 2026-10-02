import XCTest
@testable import AkitoStationCore

final class CustomEmulatorTests:XCTestCase {
 func fixture(_ root:URL,name:String="Unknown Emulator",identifier:String="test.custom")->URL {
  let app=root.appendingPathComponent(name+".app"),contents=app.appendingPathComponent("Contents")
  try! FileManager.default.createDirectory(at:contents.appendingPathComponent("MacOS"),withIntermediateDirectories:true)
  try! FileManager.default.copyItem(at:URL(fileURLWithPath:"/bin/echo"),to:contents.appendingPathComponent("MacOS/fixture"))
  let info:[String:Any]=["CFBundleName":name,"CFBundleExecutable":"fixture","CFBundleIdentifier":identifier,"CFBundleShortVersionString":"fixture-2"]
  try! PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
  return app
 }
 func temporary()throws->URL{let root=FileManager.default.temporaryDirectory.appendingPathComponent("custom-tests-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);return root}
 func testAutomaticDetectionAndKnownCompatibility()throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  let known=fixture(root,name:"PCSX2",identifier:"net.pcsx2.pcsx2"),found=try EmulatorDetection.inspect(known)
  XCTAssertEqual(found.name,"PCSX2");XCTAssertEqual(found.recognizedEngine,"pcsx2");XCTAssertEqual(found.supportedPlatforms,[.ps2]);XCTAssertEqual(found.version,"fixture-2")
  XCTAssertTrue(["arm64","universal","x86_64"].contains(found.architecture));XCTAssertTrue(found.executable.path.hasSuffix("Contents/MacOS/fixture"))
  var config=CustomEmulatorConfiguration(name:"Known");config.recognizedEngine="pcsx2"
  XCTAssertThrowsError(try RuntimeManager(root:root.appendingPathComponent("runtimes")).registerCustom(input:known,platform:.ps3,configuration:config))
  XCTAssertThrowsError(try EmulatorDetection.inspect(known,executableOverride:"../../bin/echo"))
 }
 func testEveryRegistryConsoleSupportsCustomRegistrationAndRestart()throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  let app=fixture(root),manager=RuntimeManager(root:root.appendingPathComponent("runtimes"))
  for platform in Platform.allCases where platform != .unknown {
   let config=CustomEmulatorConfiguration(name:"Custom "+platform.title)
   let runtime=try manager.registerCustom(input:app,platform:platform,configuration:config)
   let restarted=RuntimeManager(root:manager.root)
   XCTAssertTrue(EmulatorEngines.choices(for:platform,installed:try restarted.manifests()).contains(runtime.id))
   XCTAssertEqual(try restarted.selected(runtime.id).0.custom,runtime.custom)
   XCTAssertEqual(try restarted.selected(runtime.id).0.custom?.bundleIdentifier,"test.custom")
   XCTAssertEqual(RuntimeCatalog.selected(platform:platform,system:runtime.id,game:nil,installed:try restarted.manifests()),runtime.id)
  }
 }
 func testMultipleDefaultsOverridesEditAndArgumentPersistence()throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  let app=fixture(root),manager=RuntimeManager(root:root.appendingPathComponent("runtimes")),game=URL(fileURLWithPath:"/tmp/User Games/Game with spaces.iso")
  var config=CustomEmulatorConfiguration(name:"Custom A");config.arguments=["--batch","--dir={gameDirectory}"];config.additionalArguments=["--data={runtimeDirectory}","literal $(do not execute)"]
  config.environment=["FIXTURE":"{gameDirectory}"];config.workingDirectory="{runtimeDirectory}";config.saveLocation="/tmp/My saves";config.configLocation="/tmp/My config"
  let a=try manager.registerCustom(input:app,platform:.switchConsole,configuration:config)
  let b=try manager.registerCustom(input:app,platform:.switchConsole,configuration:CustomEmulatorConfiguration(name:"Custom B"))
  XCTAssertNotEqual(a.id,b.id)
  let installed=try manager.manifests()
  XCTAssertEqual(RuntimeCatalog.selected(platform:.switchConsole,system:a.id,game:nil,installed:installed),a.id)
  XCTAssertEqual(RuntimeCatalog.selected(platform:.switchConsole,system:b.id,game:nil,installed:installed),b.id)
  XCTAssertEqual(RuntimeCatalog.selected(platform:.switchConsole,system:a.id,game:b.id,installed:installed),b.id)
  XCTAssertNil(RuntimeCatalog.selected(platform:.ps3,system:nil,game:b.id,installed:installed))
  let persisted=try RuntimeManager(root:manager.root).selected(a.id).0
  XCTAssertEqual(persisted.custom?.additionalArguments,config.additionalArguments)
  let launch=try ManagedLaunch(custom:persisted.custom!,runtimeDirectory:app,game:game)
  XCTAssertEqual(launch.arguments,["--batch","--dir=/tmp/User Games",game.path,"--data="+app.path,"literal $(do not execute)"])
  XCTAssertEqual(launch.environment["FIXTURE"],"/tmp/User Games")
  config.name="Edited A";config.arguments=["--new"]
  let edited=try manager.registerCustom(input:app,platform:.switchConsole,configuration:config,id:a.id)
  XCTAssertEqual(edited.id,a.id);XCTAssertNotEqual(edited.version,a.version)
  XCTAssertEqual(try manager.selected(a.id).0.custom?.name,"Edited A")
  XCTAssertNoThrow(try manager.selected(a.id,version:a.version))
  config.name="Edited in place";config.additionalArguments=["--changed"]
  let inPlace=try manager.editCustom(edited,platform:.switchConsole,configuration:config)
  XCTAssertEqual(inPlace.version,edited.version)
  XCTAssertEqual(try RuntimeManager(root:manager.root).selected(a.id).0.custom?.additionalArguments,["--changed"])
 }
 func testExternalRemovalManagedUninstallAndMissingMovedExecutable()throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  let app=fixture(root),manager=RuntimeManager(root:root.appendingPathComponent("runtimes"))
  let original=app.appendingPathComponent("Contents/MacOS/fixture"),hash=try digest(original)
  for path in ["games/game.iso","saves/save.bin","firmware/bios.bin","keys/keys.txt"]{let url=root.appendingPathComponent(path);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data("retain".utf8).write(to:url)}
  let external=try manager.registerCustom(input:app,platform:.ps3,configuration:CustomEmulatorConfiguration(name:"External"))
  try manager.unregister(external.id,version:external.version);XCTAssertEqual(try digest(original),hash)
  let managed=try manager.registerCustom(input:app,platform:.ps3,configuration:CustomEmulatorConfiguration(name:"Managed"),managed:true)
  XCTAssertNil(managed.externalLocation);XCTAssertEqual(try digest(manager.selected(managed.id).1),hash)
  try manager.uninstall(managed.id);XCTAssertEqual(try digest(original),hash)
  for path in ["games/game.iso","saves/save.bin","firmware/bios.bin","keys/keys.txt"]{XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(path)),Data("retain".utf8))}
  let movedRuntime=try manager.registerCustom(input:app,platform:.ps3,configuration:CustomEmulatorConfiguration(name:"Moved"))
  let moved=root.appendingPathComponent("Relocated.app");try FileManager.default.moveItem(at:app,to:moved)
  // Remove any resolvable bookmark to exercise a lost-volume/stale-path case deterministically.
  var lost=movedRuntime;lost.externalLocation?.bookmark=nil
  try JSONStore.write(lost,to:manager.root.appendingPathComponent(lost.id+"/"+lost.version+"/manifest.json"))
  XCTAssertThrowsError(try manager.selected(lost.id))
  let relinked=try manager.registerCustom(input:moved,platform:.ps3,configuration:CustomEmulatorConfiguration(name:"Moved"),id:lost.id)
  XCTAssertEqual(relinked.id,lost.id);XCTAssertNoThrow(try manager.selected(lost.id))
  try FileManager.default.removeItem(at:manager.selected(lost.id).1)
  XCTAssertThrowsError(try manager.selected(lost.id))
  XCTAssertThrowsError(try EmulatorDetection.inspect(root.appendingPathComponent("missing")))
 }
 func testArgumentValidationAndUnsupportedTypes()throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  var config=CustomEmulatorConfiguration(name:"Fixture")
  config.arguments=["{unknown}"];XCTAssertThrowsError(try config.validate())
  config.arguments=[];config.environment=["BAD=NAME":"value"];XCTAssertThrowsError(try config.validate())
  config.environment=[:];config.testArguments=["{game}"];XCTAssertThrowsError(try config.validate())
  config.testArguments=[];config.gameArgument="{game}\0";XCTAssertThrowsError(try config.validate())
  let invalid=root.appendingPathComponent("Windows.exe");try Data("not a mac executable".utf8).write(to:invalid);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:invalid.path)
  XCTAssertThrowsError(try EmulatorDetection.inspect(invalid))
 }
 func testNoROMStartupAndCleanFailure()async throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  let log=root.appendingPathComponent("test.log")
  try await ProcessRunner.testRuntime(executable:URL(fileURLWithPath:"/bin/echo"),arguments:["No ROM fixture"],workingDirectory:root,environment:["FIXTURE":"value"],log:log)
  XCTAssertTrue(try String(contentsOf:log).contains("No ROM fixture"))
  do{try await ProcessRunner.testRuntime(executable:URL(fileURLWithPath:"/usr/bin/false"),arguments:[],log:log);XCTFail("Startup failure accepted")}catch{XCTAssertTrue(error.localizedDescription.contains("exited during startup"))}
  // The observed GUI-style process remains alive until this test closes its own instance.
  let started=Date();try await ProcessRunner.testRuntime(executable:URL(fileURLWithPath:"/bin/sleep"),arguments:["30"],log:log)
  XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started),2)
  let script=root.appendingPathComponent("Launcher with spaces")
  let code="#!/bin/sh\nprintf '%s\\n' \"$AKITO_FIXTURE\" \"$@\"\n/bin/pwd\n"
  try Data(code.utf8).write(to:script);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:script.path)
  var configuration=CustomEmulatorConfiguration(name:"Script launcher");configuration.testArguments=["test {runtimeDirectory}"];configuration.environment=["AKITO_FIXTURE":"fixture value"];configuration.workingDirectory="{runtimeDirectory}"
  let manager=RuntimeManager(root:root.appendingPathComponent("runtimes")),registered=try manager.registerCustom(input:script,platform:.nes,configuration:configuration)
  XCTAssertEqual(registered.architecture,"script");let pair=try manager.selected(registered.id)
  let launch=try ManagedLaunch(custom:registered.custom!,runtimeDirectory:manager.runtimeDirectory(registered))
  try await ProcessRunner.testRuntime(executable:pair.1,arguments:launch.arguments,workingDirectory:launch.workingDirectory,environment:launch.environment,log:log)
  let evidence=try String(contentsOf:log);XCTAssertTrue(evidence.contains("fixture value"));XCTAssertTrue(evidence.contains(launch.arguments[0]));XCTAssertTrue(evidence.contains(root.path))
  do{try await ProcessRunner.testRuntime(executable:root.appendingPathComponent("missing"),arguments:[],log:log);XCTFail("Missing executable accepted")}catch{XCTAssertTrue(error.localizedDescription.contains("Executable not found"))}
 }
 func testSwitchDocumentAdapterLegacyRegistrationAndMissingGameArgument()throws {
  let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
  var config=CustomEmulatorConfiguration(name:"Astris");config.bundleIdentifier="V380-Ori.Astris"
  XCTAssertEqual(config.effectiveGameLaunchMethod,.openDocument)
  let game=URL(fileURLWithPath:"/tmp/External Games/Game & 日本語.nsp")
  XCTAssertEqual(try ManagedLaunch(custom:config,runtimeDirectory:root,game:game).arguments,[])
  config.gameLaunchMethod = .arguments
  XCTAssertEqual(try ManagedLaunch(custom:config,runtimeDirectory:root,game:game).arguments,[game.path])
  config.gameArgument="";XCTAssertThrowsError(try ManagedLaunch(custom:config,runtimeDirectory:root,game:game))
  config.bundleIdentifier=nil;config.gameArgument="{game}";config.recognizedEngine="eden"
  XCTAssertEqual(try ManagedLaunch(custom:config,runtimeDirectory:root,game:game).arguments,["-g",game.path])
  config.arguments=["--custom"]
  XCTAssertEqual(try ManagedLaunch(custom:config,runtimeDirectory:root,game:game).arguments,["--custom",game.path])
  config.arguments=[];config.recognizedEngine="ryujinx"
  XCTAssertEqual(try ManagedLaunch(custom:config,runtimeDirectory:root,game:game).arguments,[game.path])
 }

}
