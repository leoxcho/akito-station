import XCTest
import AppKit
@testable import AkitoStationCore

final class ArtworkTests: XCTestCase {
 func testAliasesAndDetection() {
  let pairs: [(Platform,[String])] = [(.ps2,["PS2","PlayStation 2","Sony Playstation 2"]),(.psp,["PSP","PlayStation Portable"]),(.ps3,["PS3","PlayStation 3"]),(.ps4,["PS4","PlayStation 4"]),(.xbox360,["Xbox 360","X360"]),(.wiiu,["Wii U","WiiU","Nintendo Wii U"]),(.switchConsole,["Nintendo Switch","Switch"])]
  for (platform,aliases) in pairs { for alias in aliases {
   XCTAssertEqual(Platform.artworkPlatform(alias),platform)
   XCTAssertEqual(Platform.detect(URL(fileURLWithPath:"/Games/\(alias)/Game.iso")),platform)
  }}
  XCTAssertNil(Platform.artworkPlatform("PlayStation 5"))
 }
 func testFilenameNormalizationPreservesTitlesAndSequels() {
  let pairs = [("God_of_War_(USA)_[SLUS-208.47].iso","God of War"),("Persona_4 (Europe) (Rev 1) (Disc 2).chd","Persona 4"),("Final Fantasy X [SLUS-20312] (USA) [!].iso","Final Fantasy X"),("Uncharted_2_Among_Thieves [BCUS98123]-DUPLEX.pkg","Uncharted 2 Among Thieves"),("Super_Mario_Odyssey [0100000000010000] [v1.0.0].nsp","Super Mario Odyssey"),("God of War (Ghost of Sparta)","God of War Ghost of Sparta"),("NieR (Replicant)","NieR Replicant"),("Gears_of_War_2 [4541087D] [X360].xex","Gears of War 2"),("Mario Kart 8 [WUP-P-AMKE].wux","Mario Kart 8")]
  for (filename,title) in pairs { XCTAssertEqual(ArtworkCache.matchingTitle(filename),ArtworkCache.matchingTitle(title),filename) }
  XCTAssertFalse(ArtworkCache.titleMatches("Halo 30",query:"Halo 3"))
  XCTAssertFalse(ArtworkCache.titleMatches("Persona 4",query:"Persona 3"))
 }
 func testPlatformRankingAndFrontOnlyParsing() {
  let html = """
  <a href="./game.php?id=1"><img alt="Halo 3 cover" src="https://cdn.thegamesdb.net/images/thumb/boxart/front/1-1.jpg"><p class="text-muted">Microsoft Xbox 360</p></a>
  <a href="./game.php?id=2"><img alt="Halo 3 cover" src="https://cdn.thegamesdb.net/images/thumb/screenshots/2.jpg"><p class="text-muted">Microsoft Xbox 360</p></a>
  <a href="./game.php?id=3"><img alt="Halo 3 cover" src="https://cdn.thegamesdb.net/images/thumb/boxart/front/3.jpg"><p class="text-muted">PC</p></a>
  """
  let parsed=ArtworkCache.publicPageResults(html,platform:.xbox360)
  XCTAssertEqual(parsed.count,1)
  XCTAssertTrue(parsed[0].url.path.contains("/original/boxart/front/"))
  let wrong=ArtworkCache.Result(title:"Halo 3",url:URL(string:"https://example.com/wrong")!,platform:.ps3)
  XCTAssertGreaterThan(ArtworkCache.matchScore(parsed[0],query:"Halo 3",platform:.xbox360),ArtworkCache.matchScore(wrong,query:"Halo 3",platform:.xbox360))
 }
 func testProviderFailureFallsBackAndCaches() async throws {
  actor Counter { var count=0; func hit(){count += 1}; func value()->Int {count} }
  let counter=Counter()
  let cache=ArtworkCache(loader: { url in
   await counter.hit()
   if url.host != "thegamesdb.net" { throw URLError(.cannotConnectToHost) }
   return Data("""
   <select id="platformselect"></select><a href="./game.php?id=1"><img alt="Halo 3 cover" src="https://cdn.thegamesdb.net/images/thumb/boxart/front/1-1.jpg"><p class="text-muted">Microsoft Xbox 360</p></a>
   """.utf8)
  })
  let first=try await cache.search("Halo 3",platform:.xbox360)
  XCTAssertEqual(first.count,1)
  let before=await counter.value()
  let second=try await cache.search("Halo_3 (USA).iso",platform:.xbox360)
  XCTAssertEqual(second.count,1)
  let after=await counter.value(); XCTAssertEqual(before,after)
 }
 func testMirrorFailureUsesGitHubAndIgnoresScreenshots() async throws {
  let cache=ArtworkCache(loader: { url in
   if url.host == "thumbnails.libretro.com" { throw URLError(.badServerResponse) }
   return Data(#"{"tree":[{"path":"Named_Boxarts/Persona 4 (USA).png"},{"path":"Named_Snaps/Persona 4.png"}],"truncated":false}"#.utf8)
  })
  let results=try await cache.search("Persona 4.iso",platform:.ps2)
  XCTAssertEqual(results.count,1); XCTAssertEqual(results[0].platform,.ps2)
 }
 func testProgressivePhraseFallbackValidatesFullTitle() async throws {
  let cache=ArtworkCache(loader: { url in
   let phrase=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where: { $0.name == "name" })?.value
   let prefix="<select id=\"platformselect\"></select>"
   guard phrase == "breath of the wild" else { return Data(prefix.utf8) }
   return Data((prefix+"<a href=\"./game.php?id=1\"><img alt=\"Legend of Zelda, The: Breath of the Wild cover\" src=\"https://cdn.thegamesdb.net/images/thumb/boxart/front/1.jpg\"><p class=\"text-muted\">Nintendo Switch</p></a>").utf8)
  })
  let results=try await cache.search("The Legend of Zelda: Breath of the Wild",platform:.switchConsole)
  XCTAssertEqual(results.count,1)
  XCTAssertEqual(ArtworkCache.matchingTitle(results[0].title),ArtworkCache.matchingTitle("The Legend of Zelda: Breath of the Wild"))
 }
 func testRateLimitBlocksFurtherQueriesToProvider() async throws {
  actor Counter { var count=0; func hit(){count += 1}; func value()->Int {count} }
  let counter=Counter()
  let cache=ArtworkCache(loader: { _ in
   await counter.hit()
   throw ArtworkCache.ProviderFailure(status:429,retryAt:Date().addingTimeInterval(600))
  })
  for title in ["Super Mario Odyssey","Mario Kart 8 Deluxe"] {
   do { _ = try await cache.search(title,platform:.switchConsole); XCTFail("Expected provider restriction") } catch {}
  }
  let calls=await counter.value(); XCTAssertEqual(calls,1)
 }
 func testAutomaticJPEGConversionAndExistingArtworkPreservation() async throws {
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  bitmap.setColor(.red,atX:0,y:0)
  let jpeg=bitmap.representation(using:.jpeg,properties:[:])!
  let cache=ArtworkCache(loader: { url in
   if url.host == "cdn.thegamesdb.net" { return jpeg }
   return Data("<select id=\"platformselect\"></select><a href=\"./game.php?id=1\"><img alt=\"Super Mario Odyssey cover\" src=\"https://cdn.thegamesdb.net/images/thumb/boxart/front/1.jpg\"><p class=\"text-muted\">Nintendo Switch</p></a>".utf8)
  })
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  let game=Game(url:URL(fileURLWithPath:"/Games/Switch/Super_Mario_Odyssey [0100000000010000].nsp"),root:URL(fileURLWithPath:"/Games"),bytes:0)
  let fetched=try await cache.fetch(game,cache:root)
  let destination=try XCTUnwrap(fetched)
  XCTAssertTrue(try Data(contentsOf:destination).starts(with:[137,80,78,71,13,10,26,10]))
  XCTAssertTrue(FileManager.default.fileExists(atPath:destination.appendingPathExtension("source.json").path))
  let second=try await cache.fetch(game,cache:root)
  XCTAssertEqual(second,destination)
  var sequel=game; sequel.title="Super Mario"; sequel.id="another-game"
  let rejected=try await cache.scrape(sequel)
  XCTAssertNil(rejected)
 }
 func testLiveAffectedPlatforms() async throws {
  guard ProcessInfo.processInfo.environment["AKITO_ARTWORK_LIVE"] == "1" else { throw XCTSkip("Set AKITO_ARTWORK_LIVE=1 for public-provider integration tests") }
  let cache=ArtworkCache()
  let games: [(Platform,[String])] = [(.ps2,["God of War","Shadow of the Colossus","Persona 4","Final Fantasy X"]),(.psp,["God of War - Ghost of Sparta","Crisis Core - Final Fantasy VII","Patapon"]),(.ps3,["The Last of Us","Uncharted 2: Among Thieves","LittleBigPlanet"]),(.ps4,["Bloodborne","God of War","Horizon Zero Dawn"]),(.xbox360,["Halo 3","Gears of War 2","Forza Motorsport 4"]),(.wiiu,["Mario Kart 8","Super Mario 3D World","Splatoon"]),(.switchConsole,["Super Mario Odyssey","Mario Kart 8 Deluxe","The Legend of Zelda: Breath of the Wild"])]
  for (platform,titles) in games {
   for title in titles {
    let clean=try await cache.search(title,platform:platform)
    let product: [Platform:String] = [.ps2:"[SLUS-20312]",.psp:"[ULUS-10567]",.ps3:"[BCUS98123]",.ps4:"[CUSA-00900]",.switchConsole:"[0100000000010000]"]
    let filename=title.replacingOccurrences(of:" ",with:"_")+" (USA) (Rev 1) (Disc 1) [!] "+(product[platform] ?? "[Redump]")+"-DUPLEX"+(platform == .switchConsole ? ".nsp" : ".iso")
    let imported=try await cache.search(filename,platform:platform)
    guard let best=clean.first else { XCTFail("No cover: \(platform.title) \(title)"); continue }
    XCTAssertEqual(best.platform,platform)
    XCTAssertEqual(ArtworkCache.matchingTitle(best.title),ArtworkCache.matchingTitle(title),"\(platform.title): \(best.title)")
    XCTAssertEqual(best.id,imported.first?.id,filename)
    let data=try await cache.download(best)
    XCTAssertGreaterThan(data.count,1000)
    print("ARTWORK PASS \(platform.rawValue) | \(title) | \(best.provider) | \(data.count) bytes | clean + filename")
   }
  }
 }
}
