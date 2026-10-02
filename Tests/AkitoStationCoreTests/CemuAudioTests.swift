import XCTest
@testable import AkitoStationCore
final class CemuAudioTests:XCTestCase {
 func testNativeGraphicsStillReceivesAudioAndPreservesSettings()throws {
  let data=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:data)}
  let file=data.appendingPathComponent("home/Library/Application Support/Cemu/settings.xml")
  try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
  let original="<content><Graphic><api>1</api></Graphic><Audio><api>0</api><PadDevice/><PadVolume>0</PadVolume><InputDevice>microphone</InputDevice></Audio><Account><id>keep</id></Account></content>"
  try Data(original.utf8).write(to:file)
  var p=GameProfile();p.volume=0.65;p.options["arm.settings.native"]="true"
  _ = try ManagedLaunch(engine:"cemu",binary:data.appendingPathComponent("cemu"),game:data.appendingPathComponent("game.wua"),profile:p,data:data,caches:data.appendingPathComponent("cache"))
  let doc=try XMLDocument(contentsOf:file)
  for key in ["TVDevice","PadDevice"]{XCTAssertEqual(try doc.nodes(forXPath:"/content/Audio/"+key).first?.stringValue,"default")}
  XCTAssertEqual(try doc.nodes(forXPath:"/content/Audio/PadVolume").first?.stringValue,"65")
  XCTAssertEqual(try doc.nodes(forXPath:"/content/Audio/api").first?.stringValue,"3")
  XCTAssertEqual(try doc.nodes(forXPath:"/content/Audio/InputDevice").first?.stringValue,"microphone")
  XCTAssertEqual(try doc.nodes(forXPath:"/content/Account/id").first?.stringValue,"keep")
  XCTAssertEqual(try String(contentsOf:file.appendingPathExtension("before-akito-audio")),original)
  p.options["arm.cemu.audio.native"]="true"
  try Data(original.utf8).write(to:file);try CemuAudioConfiguration.prepare(data:data,profile:p)
  XCTAssertEqual(try String(contentsOf:file),original)
 }
}
