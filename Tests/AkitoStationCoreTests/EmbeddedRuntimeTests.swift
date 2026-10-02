import XCTest
@testable import AkitoStationCore

final class EmbeddedRuntimeTests:XCTestCase {
 func testDesktopLaunchRejectedBeforeCreatingStorage()throws {
  for platform in [Platform.psvita,.switchConsole] {
   let engine=try XCTUnwrap(platform.core)
   let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
   XCTAssertThrowsError(try ManagedLaunch(engine:engine,binary:folder.appendingPathComponent("Emulator.app/Contents/MacOS/Emulator"),game:folder.appendingPathComponent("game"),profile:GameProfile(),data:folder,caches:folder.appendingPathComponent("cache"))) { error in
    XCTAssertTrue(error.localizedDescription.contains("Standalone launch is disabled"))
   }
   XCTAssertFalse(FileManager.default.fileExists(atPath:folder.path))
  }
 }
 func testOtherEnginesAndSourceURLs()throws {
  for engine in ManagedLaunch.engines.subtracting(EmbeddedRuntime.requiredEngines){XCTAssertNoThrow(try EmbeddedRuntime.requirePlayable(engine:engine))}
  for url in EmbeddedRuntime.sourceRepositories.values{_ = try GitHubRepository(url)}
 }
}
