import XCTest
@testable import AkitoStationCore
final class NativeConsoleInstallerTests:XCTestCase {
 var root:URL!
 override func setUpWithError()throws{root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
 override func tearDownWithError()throws{try? FileManager.default.removeItem(at:root)}
 func folder(_ name:String)throws->URL{let file=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:file,withIntermediateDirectories:true);return file}
 func package(vita:Bool)throws->URL {
  var bytes=Data(count:256)
  func number(_ at:Int,_ count:Int,_ value:UInt64){for i in 0..<count{bytes[at+i]=UInt8((value>>((count-i-1)*8))&255)}}
  bytes.replaceSubrange(0..<4,with:[0x7f,0x50,0x4b,0x47]);number(6,2,vita ? 2:1);number(24,8,256);number(32,8,256)
  let id="UP0000-"+(vita ? "PCSA00001":"BLES00001")+"_00-FIXTURE"
  bytes.replaceSubrange(48..<48+id.utf8.count,with:id.utf8)
  if vita{number(8,4,192);number(12,4,1);number(192,4,2);number(196,4,4);number(200,4,0x15)}
  let file=root.appendingPathComponent(vita ? "vita.pkg":"ps3.pkg");try bytes.write(to:file);return file
 }
 func script(_ code:String)throws->URL{let file=root.appendingPathComponent("fixture-runtime");try Data(("#!/bin/sh\nset -eu\n"+code).utf8).write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path);return file}
 func testSuppliedLicenseZlibEncoding()throws {
  XCTAssertEqual(try NativeConsoleInstaller.encodeSuppliedVitaLicense(Data(count:512)),"eNpjYBgFIxkAAAIAAAE=")
  XCTAssertThrowsError(try NativeConsoleInstaller.encodeSuppliedVitaLicense(Data(count:511)))
 }
 func testPublishPreservesOriginalAndPriorVersion()throws {
  let source=try folder("source"),library=try folder("library"),target=library.appendingPathComponent("CUSA00001"),file=source.appendingPathComponent("eboot.bin")
  try Data("first".utf8).write(to:file);XCTAssertNil(try NativeConsoleInstaller.publish(source,to:target,platform:.ps4,title:"CUSA00001"))
  try Data("second".utf8).write(to:file);let backup=try XCTUnwrap(NativeConsoleInstaller.publish(source,to:target,platform:.ps4,title:"CUSA00001"))
  XCTAssertEqual(try String(contentsOf:backup.appendingPathComponent("eboot.bin")),"first");XCTAssertEqual(try String(contentsOf:file),"second")
  let owned=try folder("library/CUSA00002");try Data("user".utf8).write(to:owned.appendingPathComponent("user.bin"));XCTAssertThrowsError(try NativeConsoleInstaller.publish(source,to:owned,platform:.ps4,title:"CUSA00002"))
  try FileManager.default.createSymbolicLink(at:source.appendingPathComponent("escape"),withDestinationURL:root);XCTAssertThrowsError(try NativeConsoleInstaller.validateTree(source))
 }
 func testIsolatedPS3FixtureAndRollbackOnConflictingLink()async throws {
  let data=try folder("data"),library=try folder("library"),work=try folder("work"),firmware=try folder("data/dev_flash/sys/external")
  try Data("self-authored firmware fixture".utf8).write(to:firmware.appendingPathComponent("liblv2.sprx"))
  let runtime=try script("/bin/mkdir -p \"$HOME/Library/Application Support/rpcs3/dev_hdd0/game/BLES00001\"\nprintf fixture > \"$HOME/Library/Application Support/rpcs3/dev_hdd0/game/BLES00001/fixture.bin\"\nprintf 'Successfully installed %s (title_id=BLES00001,\\n' \"$3\"\n")
  let file=try package(vita:false),log=root.appendingPathComponent("pkg.log")
  let result=try await NativeConsoleInstaller.install(file:file,platform:.ps3,library:library,data:data,runtime:runtime,work:work,log:log)
  XCTAssertEqual(try String(contentsOf:result.destination.appendingPathComponent("fixture.bin")),"fixture")
  XCTAssertTrue(FileManager.default.fileExists(atPath:file.path));XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:work.path).isEmpty)
  let link=data.appendingPathComponent("home/Library/Application Support/rpcs3/dev_hdd0/game/BLES00001")
  XCTAssertEqual(link.resolvingSymlinksInPath().path,result.destination.resolvingSymlinksInPath().path)
  try FileManager.default.removeItem(at:link);try FileManager.default.createDirectory(at:link,withIntermediateDirectories:true);try Data("preserve".utf8).write(to:link.appendingPathComponent("save"))
  do{_=try await NativeConsoleInstaller.install(file:file,platform:.ps3,library:library,data:data,runtime:runtime,work:work,log:root.appendingPathComponent("retry.log"));XCTFail("Conflicting link accepted")}catch{}
  XCTAssertEqual(try String(contentsOf:link.appendingPathComponent("save")),"preserve");XCTAssertEqual(try String(contentsOf:result.destination.appendingPathComponent("fixture.bin")),"fixture")
 }
 func testVitaFixtureLicenseIdentityAndIsolatedOutput()async throws {
  let file=try package(vita:true),data=try folder("data"),work=try folder("work"),library=try folder("library"),license=root.appendingPathComponent("work.bin")
  var bytes=Data(count:512);let id="UP0000-PCSA00001_00-FIXTURE";bytes.replaceSubrange(16..<16+id.utf8.count,with:id.utf8);try bytes.write(to:license)
  let runtime=try script("if [ \"$1\" = --help ]; then /bin/mkdir -p \"$HOME/Library/Application Support/Vita3K/Vita3K\"; printf 'keyboard-button-select: x\\n' > \"$HOME/Library/Application Support/Vita3K/Vita3K/config.yml\"; exit 0; fi\n/bin/mkdir -p \"$PWD/fs/ux0/app/PCSA00001/sce_sys\"\nprintf fixture > \"$PWD/fs/ux0/app/PCSA00001/eboot.bin\"\nprintf fixture > \"$PWD/fs/ux0/app/PCSA00001/sce_sys/param.sfo\"\n")
  let result=try await NativeConsoleInstaller.install(file:file,platform:.psvita,library:library,data:data,runtime:runtime,work:work,license:license,log:root.appendingPathComponent("vita.log"))
  XCTAssertTrue(FileManager.default.fileExists(atPath:result.destination.appendingPathComponent("eboot.bin").path));XCTAssertEqual(try Data(contentsOf:license),bytes)
  XCTAssertEqual(try Data(contentsOf:data.appendingPathComponent("fs/ux0/license/PCSA00001/"+id+".rif")),bytes)
  bytes[16]=0;try bytes.write(to:license)
  do{_=try await NativeConsoleInstaller.install(file:file,platform:.psvita,library:library,data:data,runtime:runtime,work:work,license:license,log:root.appendingPathComponent("bad.log"));XCTFail("Wrong license accepted")}catch{}
 }
}
