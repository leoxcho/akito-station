import XCTest
@testable import AkitoStationCore

final class ExternalEmulatorTests:XCTestCase {
 func testOptionalInstallUninstallIsolation()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  let saves=root.appendingPathComponent("saves/keep")
  try FileManager.default.createDirectory(at:saves,withIntermediateDirectories:true)
  let runtimes=root.appendingPathComponent("runtimes")
  let manager=RuntimeManager(root:runtimes)
  for platform in [Platform.psvita,.switchConsole,.ps4] {
   XCTAssertThrowsError(try ExternalEmulator.managedApplication(platform,root:runtimes))
   let id=platform == .switchConsole ? "eden":platform.core!
   XCTAssertTrue(ManagedLaunch.platforms(for:id).contains(platform))
   let version=runtimes.appendingPathComponent(id+"/v1")
   let app=version.appendingPathComponent("Fixture.app")
   let binary=app.appendingPathComponent("Contents/MacOS/Fixture")
   try FileManager.default.createDirectory(at:binary.deletingLastPathComponent(),withIntermediateDirectories:true)
   try Data("fixture".utf8).write(to:binary)
   try PropertyListSerialization.data(fromPropertyList:["CFBundleExecutable":"Fixture","CFBundleIdentifier":"test."+id,"CFBundlePackageType":"APPL"],format:.xml,options:0).write(to:app.appendingPathComponent("Contents/Info.plist"))
   let manifest=RuntimeManifest(id:id,version:"v1",upstream:"",revision:"test",library:"Fixture.app/Contents/MacOS/Fixture",sha256:try digest(binary),license:"test",validated:true)
   try JSONStore.write(manifest,to:version.appendingPathComponent("manifest.json"))
   try manager.activate(id,version:"v1")
   XCTAssertEqual(try ExternalEmulator.managedApplication(platform,root:runtimes).path,app.path)

   try manager.uninstall(id)
   XCTAssertFalse(FileManager.default.fileExists(atPath:runtimes.appendingPathComponent(id).path))
  }
  XCTAssertTrue(FileManager.default.fileExists(atPath:saves.path))
  XCTAssertThrowsError(try manager.uninstall("../saves"))
  try FileManager.default.createSymbolicLink(at:runtimes.appendingPathComponent("eden"),withDestinationURL:root.appendingPathComponent("saves"))
  XCTAssertThrowsError(try manager.uninstall("eden"))
 }
 func testExternalRoutesAndPathsWithSpaces()throws {
  XCTAssertEqual(ExternalEmulator.name(.psvita),"Vita3K")
  XCTAssertEqual(ExternalEmulator.name(.switchConsole),"Eden")
  XCTAssertEqual(ExternalEmulator.name(.ps4),"shadPS4")
  XCTAssertNil(ExternalEmulator.name(.ps3))
  let game=URL(fileURLWithPath:"/tmp/Games/My game.nsp")
  XCTAssertEqual(try ExternalEmulator.arguments(.switchConsole,game:game),[game.path])
  XCTAssertEqual(try ExternalEmulator.arguments(.psvita,game:game),[game.path])
 }
 func testPS4FolderWithoutDirectoryURLHint()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:root)}
  XCTAssertThrowsError(try ExternalEmulator.arguments(.ps4,game:root))
  let boot=root.appendingPathComponent("eboot.bin")
  try Data().write(to:boot)
  XCTAssertEqual(try ExternalEmulator.arguments(.ps4,game:URL(fileURLWithPath:root.path,isDirectory:false)),["-g",boot.path])
  XCTAssertEqual(try ExternalEmulator.arguments(.ps4,game:boot),["-g",boot.path])
 }
 func testDiscoverySelectsNewestVersion()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  for name in ["shadps4 (7.0)","shadps4 (12.0)"]{
   let contents=root.appendingPathComponent(name+".app/Contents")
   try FileManager.default.createDirectory(at:contents.appendingPathComponent("MacOS"),withIntermediateDirectories:true)
   let executable=contents.appendingPathComponent("MacOS/shadps4")
   try Data("#!/bin/sh\nexit 0\n".utf8).write(to:executable)
   try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
   let plist:[String:Any]=["CFBundleExecutable":"shadps4","CFBundleIdentifier":"test."+name,"CFBundlePackageType":"APPL"]
   try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
  }
  XCTAssertEqual(ExternalEmulator.application(.ps4,roots:[root])?.lastPathComponent,"shadps4 (12.0).app")
  XCTAssertNil(ExternalEmulator.application(.switchConsole,roots:[root]))
 }
}
