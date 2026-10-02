import XCTest
@testable import AkitoStationCore

final class SettingsResetTests:XCTestCase {
 func testResetArchivesOnlySettingsAndPreservesContent()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  let storage=try SettingsReset.defaultStorage(preferences:root.appendingPathComponent("preferences.json"))
  XCTAssertEqual(storage.root.path,root.appendingPathComponent("Data").path)
  XCTAssertTrue(storage.libraries.isEmpty);XCTAssertTrue(storage.overrides.isEmpty)
  let profiles=try storage.directory(.profiles)
  let profile=profiles.appendingPathComponent(String(repeating:"a",count:64)+".json")
  try JSONStore.write(GameProfile(),to:profile)
  let save=try storage.directory(.saves).appendingPathComponent("game.sav")
  try Data("save".utf8).write(to:save)
  let config=try storage.directory(.saves).appendingPathComponent("Systems/vita3k/config.yml")
  try FileManager.default.createDirectory(at:config.deletingLastPathComponent(),withIntermediateDirectories:true)
  try Data("test: true".utf8).write(to:config)
  let files=try SettingsReset.configurationFiles(storage:storage)
  try SettingsReset.archive(files+files)
  XCTAssertFalse(FileManager.default.fileExists(atPath:profile.path))
  XCTAssertFalse(FileManager.default.fileExists(atPath:config.path))
  XCTAssertEqual(try String(contentsOf:save),"save")
  XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:profiles.path).contains{$0.contains("before-reset-")})
 }
}
