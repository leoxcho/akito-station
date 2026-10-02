import XCTest
import Darwin
@testable import AkitoStationCore
final class ReleaseEngineeringTests:XCTestCase {
 var root:URL!
 override func setUpWithError()throws{root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
 override func tearDownWithError()throws{try? FileManager.default.removeItem(at:root)}
 func zip(payload:Data,expanded:UInt64,method:UInt64,crc:UInt64)->Data {
  let name=Data("Fixture.app/Contents/MacOS/Fixture".utf8)
  func bytes(_ n:UInt64,_ count:Int)->Data{Data((0..<count).map{UInt8((n >> ($0*8))&255)})}
  var d=Data()
  for (n,c) in [(UInt64(0x04034b50),4),(20,2),(0,2),(method,2),(0,4),(crc,4),(UInt64(payload.count),4),(expanded,4),(UInt64(name.count),2),(0,2)]{d.append(bytes(n,c))};d.append(name);d.append(payload)
  let central=d.count
  for (n,c) in [(UInt64(0x02014b50),4),(20,2),(20,2),(0,2),(method,2),(0,4),(crc,4),(UInt64(payload.count),4),(expanded,4),(UInt64(name.count),2),(0,2),(0,2),(0,2),(0,2),(UInt64(0o100755)<<16,4),(0,4)]{d.append(bytes(n,c))};d.append(name)
  for (n,c) in [(UInt64(0x06054b50),4),(0,2),(0,2),(1,2),(1,2),(UInt64(d.count-central),4),(UInt64(central),4),(0,2)]{d.append(bytes(n,c))};return d
 }
 func testNativeBoundedExtractionRejectsDishonestSizeAndChecksum()async throws {
  let archive=root.appendingPathComponent("test.zip"),stage=root.appendingPathComponent("stage"),log=root.appendingPathComponent("log")
  // Raw DEFLATE for 512 zero bytes, stripped from the supplied-RIF zlib encoding.
  let encoded=try XCTUnwrap(Data(base64Encoded:NativeConsoleInstaller.encodeSuppliedVitaLicense(Data(count:512))))
  let raw=encoded.subdata(in:2..<encoded.count-4)
  try zip(payload:raw,expanded:512,method:8,crc:0xb2aa7578).write(to:archive)
  try await RuntimeArchive.extractZIP(archive,to:stage,log:log)
  let output=stage.appendingPathComponent("Fixture.app/Contents/MacOS/Fixture")
  XCTAssertEqual(try Data(contentsOf:output),Data(count:512));XCTAssertTrue(FileManager.default.isExecutableFile(atPath:output.path))
  try FileManager.default.removeItem(at:stage)
  for (size,crc) in [(UInt64(1),UInt64(0xb2aa7578)),(512,0)] {
   try zip(payload:raw,expanded:size,method:8,crc:crc).write(to:archive)
   do{try await RuntimeArchive.extractZIP(archive,to:stage,log:log);XCTFail("Dishonest output accepted")}catch{}
   XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path))
  }
  try zip(payload:raw,expanded:512,method:8,crc:0xb2aa7578).write(to:archive)
  var space=RuntimeArchiveLimits();space.freeSpaceReserveBytes=UInt64.max
  do{try await RuntimeArchive.extractZIP(archive,to:stage,log:log,limits:space);XCTFail("Insufficient space accepted")}catch{}
  XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path))
  var paths=RuntimeArchiveLimits();paths.fileCount=2;XCTAssertThrowsError(try RuntimeArchive.inspectZIP(archive,limits:paths))
  var limits=RuntimeArchiveLimits();limits.extractedBytes=100
  XCTAssertThrowsError(try RuntimeArchive.inspectZIP(archive,limits:limits))
 }
 func testRuntimeHashCacheInvalidatesReplacementAndSameSizeChange()throws {
  let file=root.appendingPathComponent("binary");try Data(repeating:1,count:128*1024*1024).write(to:file)
  let first=Date();let a=try RuntimeFileHashes.hash(file);let cold=Date().timeIntervalSince(first)
  let warmStart=Date();XCTAssertEqual(try RuntimeFileHashes.hash(file),a);let warm=Date().timeIntervalSince(warmStart)
  let modified=try file.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate!
  try Data(repeating:2,count:128*1024*1024).write(to:file)
  try FileManager.default.setAttributes([.modificationDate:modified],ofItemAtPath:file.path)
  XCTAssertNotEqual(try RuntimeFileHashes.hash(file),a)
  print("RUNTIME HASH 128 MiB cold=\(cold)s warm=\(warm)s; same-size/mtime rewrite invalidated")
  try FileManager.default.removeItem(at:file);XCTAssertThrowsError(try RuntimeFileHashes.hash(file))
 }
 func testNativeCatalogImportWithoutDeveloperPATHAndAdapterRelink()async throws {
  let fm=FileManager.default,app=root.appendingPathComponent("Renamed.app"),binary=app.appendingPathComponent("Contents/MacOS/ChangedName")
  try fm.createDirectory(at:binary.deletingLastPathComponent(),withIntermediateDirectories:true)
  let source=root.appendingPathComponent("fixture.c"),log=root.appendingPathComponent("compile.log")
  try Data("#include <stdio.h>\nint main(void){puts(\"ARM_DOLPHIN_PROBE\");return 0;}".utf8).write(to:source)
  let compiled=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/xcrun"),arguments:["clang","-arch","arm64",source.path,"-o",binary.path],log:log)
  XCTAssertEqual(compiled.exitCode,0)
  _=try await ProcessRunner.run(executable:URL(fileURLWithPath:"/usr/bin/codesign"),arguments:["--remove-signature",binary.path],log:log)
  let info:[String:Any]=["CFBundleIdentifier":"net.pcsx2.pcsx2","CFBundleExecutable":"ChangedName","CFBundleShortVersionString":"fixture"]
  try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:app.appendingPathComponent("Contents/Info.plist"))
  let prior=getenv("PATH").map{String(cString:$0)};setenv("PATH","/nonexistent",1);defer{if let prior{setenv("PATH",prior,1)}else{unsetenv("PATH")}}
  let manager=RuntimeManager(root:root.appendingPathComponent("runtimes")),definition=RuntimeCatalog.definition("pcsx2")!
  let first=try await manager.importCatalog(input:app,definition:definition,platform:.ps2,managed:false,host:URL(fileURLWithPath:"/bin/echo"),log:root.appendingPathComponent("log"))
  let moved=root.appendingPathComponent("Moved.app");try fm.moveItem(at:app,to:moved)
  XCTAssertThrowsError(try manager.selected("pcsx2"))
  let second=try await manager.importCatalog(input:moved,definition:definition,platform:.ps2,managed:false,host:URL(fileURLWithPath:"/bin/echo"),log:root.appendingPathComponent("log"))
  XCTAssertEqual(try manager.selection("pcsx2").previous,first.version);XCTAssertEqual(second.id,first.id)
  try manager.unregister("pcsx2",version:second.version);XCTAssertTrue(fm.fileExists(atPath:moved.path))
  let alternate=moved.appendingPathComponent("Contents/Alternate/Replacement")
  try fm.createDirectory(at:alternate.deletingLastPathComponent(),withIntermediateDirectories:true)
  try fm.copyItem(at:moved.appendingPathComponent("Contents/MacOS/ChangedName"),to:alternate)
  let replaced=try await manager.importCatalog(input:moved,definition:definition,platform:.ps2,managed:false,host:URL(fileURLWithPath:"/bin/echo"),log:root.appendingPathComponent("log"),executableOverride:"Contents/Alternate/Replacement")
  XCTAssertEqual(replaced.id,"pcsx2");XCTAssertEqual(try manager.selected("pcsx2").1.resolvingSymlinksInPath(),alternate.resolvingSymlinksInPath())
  XCTAssertTrue(fm.fileExists(atPath:moved.appendingPathComponent("Contents/MacOS/ChangedName").path))
  // Adapter proof is protocol/asset/identity validation, not gameplay certification.
  var adapterInfo=info;adapterInfo["CFBundleIdentifier"]="app.akitostation.dolphin"
  try PropertyListSerialization.data(fromPropertyList:adapterInfo,format:.xml,options:0).write(to:moved.appendingPathComponent("Contents/Info.plist"))
  let adapterBinary=moved.appendingPathComponent("Contents/MacOS/ChangedName")
  try fm.createDirectory(at:adapterBinary.deletingLastPathComponent().appendingPathComponent("Sys"),withIntermediateDirectories:true)
  let adapter=try await manager.importCatalog(input:moved,definition:RuntimeCatalog.definition("dolphin")!,platform:.wii,managed:false,host:URL(fileURLWithPath:"/bin/echo"),log:root.appendingPathComponent("log"))
  XCTAssertEqual(adapter.id,"dolphin");XCTAssertTrue(adapter.capabilities.contains("nativeWindow"))
 }
 func testAutomaticTrustRequiresExactRepositoryReleaseAndAsset()throws {
  let definition=RuntimeCatalog.definition("xemu")!,repo=definition.releaseRepository!
  let asset=ReleaseAsset(id:1,name:"xemu-macos-universal.zip",browser_download_url:repo+"/releases/download/v1/xemu-macos-universal.zip",size:32,digest:nil)
  let release=RuntimeRelease(tag_name:"v1",html_url:repo+"/releases/tag/v1",prerelease:false,body:nil,assets:[asset])
  let policy=try RuntimeDownloadTrust(definition:definition,asset:asset,release:release,repository:repo)
  XCTAssertEqual(try policy.status(signed:false,adhoc:false,team:nil),.officialUnsigned)
  XCTAssertEqual(try policy.status(signed:true,adhoc:true,team:nil),.officialUnsigned)
  XCTAssertEqual(try policy.status(signed:true,adhoc:false,team:"UNKNOWN"),.officialUnverified)
  let pinned=try RuntimeDownloadTrust(definition:definition,asset:asset,release:release,repository:repo,expectedTeam:"KNOWN")
  XCTAssertThrowsError(try pinned.status(signed:true,adhoc:false,team:"WRONG"));XCTAssertThrowsError(try pinned.status(signed:true,adhoc:true,team:"KNOWN"))
  XCTAssertEqual(try pinned.status(signed:true,adhoc:false,team:"KNOWN"),.verifiedPublisher)
  var altered=asset;altered.id=2;XCTAssertThrowsError(try RuntimeDownloadTrust(definition:definition,asset:altered,release:release,repository:repo))
  XCTAssertThrowsError(try RuntimeDownloadTrust(definition:definition,asset:asset,release:release,repository:"https://github.com/attacker/xemu"))
 }
 @MainActor func testLargeLibrarySlowAndDisconnectedReaderPreservesSnapshot()async throws {
  try FileManager.default.createDirectory(at:root.appendingPathComponent("data"),withIntermediateDirectories:true)
  let configuration=StorageConfiguration(root:Location(root.appendingPathComponent("data")))
  let games=(0..<20000).map{Game(url:root.appendingPathComponent("Game \($0).nes"),root:root,bytes:1)}
  let file=try configuration.directory(.metadata).appendingPathComponent("library.json");try JSONStore.write(games,to:file)
  var responsive=false;var heartbeatAt:Date?
  let heartbeat=Task{@MainActor in try? await Task.sleep(nanoseconds:20_000_000);responsive=true;heartbeatAt=Date()}
  let start=Date()
  let loaded=try await LibrarySnapshotLoader.load(configuration,reader:{url in Thread.sleep(forTimeInterval:0.1);return try Data(contentsOf:url)})
  let completed=Date();await heartbeat.value;XCTAssertTrue(responsive);XCTAssertLessThan(try XCTUnwrap(heartbeatAt),completed);XCTAssertEqual(loaded.games.count,20000)
  print("LIBRARY 20k decode + 100ms simulated disk latency: \(Date().timeIntervalSince(start))s; main actor heartbeat delivered")
  do{_=try await LibrarySnapshotLoader.load(configuration,reader:{_ in throw AkitoStationError.message("Simulated volume disconnect")});XCTFail("Disconnected read accepted")}catch{}
  XCTAssertEqual(loaded.games.count,20000);XCTAssertEqual(try JSONStore.read([Game].self,from:file).count,20000)
 }
 func testOfficialChecksumIdentityAndDuplicates()throws {
  let hash=String(repeating:"a",count:64)
  XCTAssertEqual(try RuntimeDownloadTrust.checksum(hash+"  xemu.zip",filename:"xemu.zip",singleFile:false),hash)
  XCTAssertThrowsError(try RuntimeDownloadTrust.checksum(hash+"  other.zip",filename:"xemu.zip",singleFile:false))
  XCTAssertThrowsError(try RuntimeDownloadTrust.checksum(hash+"  xemu.zip\n"+hash+"  xemu.zip",filename:"xemu.zip",singleFile:false))
 }

 func testOrderedLibraryWritesAndFlushBarrier()async throws {
  let configuration=StorageConfiguration(root:Location(root))
  for count in [1,100,300] {
   let games=(0..<count).map{Game(url:root.appendingPathComponent("Game \($0).nes"),root:root,bytes:1)}
   LibraryPersistence.submit(games,configuration:configuration){error in XCTAssertNil(error)}
  }
  await LibraryPersistence.flush()
  XCTAssertEqual(try JSONStore.read([Game].self,from:configuration.directory(.metadata).appendingPathComponent("library.json")).count,300)
  let snapshot=try await LibrarySnapshotLoader.load(configuration);XCTAssertEqual(snapshot.games.count,300)
 }

 func testCachedLibraryIndexMatchesPresentationAndInvalidates()async throws {
  let index=LibraryPresentationIndex()
  var games=(0..<20000).map{Game(url:root.appendingPathComponent("Game \(20000-$0).nes"),root:root,bytes:1)}
  games[0].favorite=true
  for order in ["Title","Recently played","Play time"] {
   let result=try await index.visible(games,revision:1,query:"Game",category:"favorites",order:order)
   XCTAssertEqual(result,LibraryPresentation.visible(games,query:"Game",category:"favorites",order:order))
  }
  let start=Date();_=try await index.visible(games,revision:1,query:"Game 12",category:"all",order:"Title")
  print("INDEXED 20k query warm: \(Date().timeIntervalSince(start))s")
  games[1].favorite=true;let changed=try await index.visible(games,revision:2,query:"",category:"favorites",order:"Title");XCTAssertEqual(changed.count,2)
 }

}
