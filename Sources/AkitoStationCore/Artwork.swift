import Foundation
import AppKit

/// Shared by the two editions; only public artwork endpoints are used.
public actor ArtworkCache {
 public static let shared = ArtworkCache()
 public struct Result: Identifiable, Sendable {
  public var id: String { url.absoluteString }
  public let title: String
  public let url: URL
  public let platform: Platform
  public let provider: String
  public init(title: String, url: URL, platform: Platform = .unknown, provider: String = "Libretro Thumbnails") {
   self.title=title; self.url=url; self.platform=platform; self.provider=provider
  }
 }
 public typealias Loader = @Sendable (URL) async throws -> Data
 private let loader: Loader
 private var catalogs: [String: [String]] = [:]
 private var pages: [String: [Result]] = [:]
 private var failures: [String: Date] = [:]
 private var providerBlockedUntil: [String: Date] = [:]
 struct ProviderFailure: LocalizedError {
  let status: Int
  let retryAt: Date
  var errorDescription: String? { "Cover provider unavailable, access restricted, or rate limited. Try later or import an image." }
 }
 private var pending: [String: Task<Data, Error>] = [:]
 private var attempted: [String: Date] = [:]
 private var nextRequest = Date.distantPast
 public init(loader: @escaping Loader = { try await ArtworkCache.load($0) }) { self.loader=loader }
 public static func load(_ url: URL) async throws -> Data {
  var request=URLRequest(url:url); request.timeoutInterval=30
  request.setValue("AkitoStation/1.0 (cover artwork)",forHTTPHeaderField:"User-Agent")
  let (data,response)=try await URLSession.shared.data(for:request)
  guard let response=response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
  guard response.statusCode == 200 else {
   let header=response.value(forHTTPHeaderField:"Retry-After") ?? ""
   let formatter=DateFormatter(); formatter.locale=Locale(identifier:"en_US_POSIX"); formatter.timeZone=TimeZone(secondsFromGMT:0); formatter.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
   let retryAt=Double(header).map { Date().addingTimeInterval($0) } ?? formatter.date(from:header) ?? Date().addingTimeInterval(300)
   throw ProviderFailure(status:response.statusCode,retryAt:max(retryAt,Date().addingTimeInterval(300)))
  }
  guard data.count <= 24*1024*1024 else { throw AkitoStationError.message("Cover provider response is too large") }
  return data
 }
 private func request(_ url: URL) async throws -> Data {
  let key=url.absoluteString
  if let host=url.host,let until=providerBlockedUntil[host],until>Date() {
   throw AkitoStationError.message("Cover provider is restricted or rate limited. Try later or import an image.")
  }
  if let date=failures[key], Date().timeIntervalSince(date)<300 {
   throw AkitoStationError.message("Cover provider temporarily unavailable. Try later or import an image.")
  }
  if let task=pending[key] { return try await task.value }
  let delay=max(0,nextRequest.timeIntervalSinceNow)
  nextRequest=Date().addingTimeInterval(delay+0.4)
  let task=Task {
   if delay>0 { try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000)) }
   return try await loader(url)
  }; pending[key]=task
  defer { pending[key]=nil }
  do { return try await task.value } catch {
   failures[key]=Date()
   if let failure=error as? ProviderFailure, [401,403,429].contains(failure.status), let host=url.host {
    providerBlockedUntil[host]=failure.retryAt
   }
   throw error
  }
 }
 public func fetch(_ game: Game, cache: URL) async throws -> URL? {
  let destination=cache.appendingPathComponent(game.id+".png")
  if FileManager.default.fileExists(atPath:destination.path) { return destination }
  let key=game.id+game.title+game.platform.rawValue
  if let date=attempted[key], Date().timeIntervalSince(date)<300 { return nil }
  guard let result=try await scrape(game) else { attempted[key]=Date(); return nil }
  let data=try await download(result)
  guard let bitmap=NSBitmapImageRep(data:data), let png=bitmap.representation(using:.png,properties:[:]) else { return nil }
  try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
  try png.write(to:destination,options:.atomic)
  try JSONStore.write(["source":result.url.absoluteString,"retrieved":ISO8601DateFormatter().string(from:Date()),"game":game.title],to:destination.appendingPathExtension("source.json"))
  return destination
 }
 private static func repos(_ platform: Platform) -> [String] {
  var values=repositories[platform].map { [$0] } ?? []
  if platform == .ps3 { values.append("Sony_-_PlayStation_3_Downloadable") }
  if platform == .n3ds { values.append("Nintendo_-_Nintendo_3DS_Digital") }
  return values
 }
 private func catalog(_ repo: String) async throws -> [String] {
  if let saved=catalogs[repo] { return saved }
  // The official directory mirror avoids GitHub API quotas. GitHub remains a fallback.
  let system=repo.replacingOccurrences(of:"_",with:" ")
  let base=URL(string:"https://thumbnails.libretro.com/")!.appendingPathComponent(system).appendingPathComponent("Named_Boxarts",isDirectory:true)
  var paths: [String]
  do {
   let data=try await request(base)
   paths=Self.directoryPaths(String(decoding:data,as:UTF8.self))
   guard !paths.isEmpty else { throw AkitoStationError.message("Cover directory format changed or is empty") }
  } catch {
   try Task.checkCancellation()
   let data=try await request(URL(string:"https://api.github.com/repos/libretro-thumbnails/\(repo)/git/trees/master?recursive=1")!)
   struct Tree: Decodable { struct Entry: Decodable { let path: String }; let tree: [Entry]; let truncated: Bool }
   let tree=try JSONDecoder().decode(Tree.self,from:data)
   guard !tree.truncated else { throw AkitoStationError.message("Incomplete cover catalog") }
   paths=tree.tree.map(\.path).filter { $0.hasPrefix("Named_Boxarts/") && $0.hasSuffix(".png") }
  }
  catalogs[repo]=paths; return paths
 }
 static func captures(_ pattern: String, _ text: String) -> [[String]] {
  guard let regex=try? NSRegularExpression(pattern:pattern,options:[.dotMatchesLineSeparators,.caseInsensitive]) else { return [] }
  return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map { match in
   (1..<match.numberOfRanges).map { Range(match.range(at:$0),in:text).map { String(text[$0]) } ?? "" }
  }
 }
 static func directoryPaths(_ html: String) -> [String] {
  captures("href=\"([^\"]+)\"",html).compactMap { row in
   guard let path=row[0].removingPercentEncoding, path.hasSuffix(".png"), !path.contains("/"), !path.contains("..") else { return nil }
   return "Named_Boxarts/"+path
  }
 }
 public static func matchingTitle(_ title: String) -> String { normalizedTitle(title,removeArticles:true) }
 private static func normalizedTitle(_ title: String, removeArticles: Bool) -> String {
  var value=title.replacingOccurrences(of:#"(?i)\.(iso|cso|chd|bin|cue|pbp|pkg|nsp|xci|wud|wux|rpx|xex|zip|7z|rom|png)$"#,with:"",options:.regularExpression)
  // Remove only recognizable dump metadata. Parenthesized title words stay intact.
  let groups=captures(#"(\([^)]*\)|\[[^]]*\])"#,value)
  for group in groups {
   let inner=String(group[0].dropFirst().dropLast())
   if (group[0].hasPrefix("[") && Platform.artworkPlatform(inner) != nil) || inner.range(of:#"^((?:USA|Europe|Japan|World|Asia|Korea|Australia)(?:, *(?:USA|Europe|Japan|Asia))*|PAL|NTSC[ -]?[UJ]?|En(?:[, -][A-Za-z]{2})*|Rev[ .].*|v\d.*|Disc[ .]\d.*|Disk[ .]\d.*|CD[ .]\d.*|!|b\d*|h\d*|t\d*|dump|redump|no-intro|scene|DUPLEX|iMARS|COMPLEX|PROTOCOL|VENOM|RELOADED|proper|repack|update|DLC|[0-9A-F]{8,16})$"#,options:[.regularExpression,.caseInsensitive]) != nil {
    value=value.replacingOccurrences(of:group[0],with:" ")
   }
  }
  value=value.replacingOccurrences(of:#"(?i)\b(?:SLUS|SLES|SCUS|SCES|ULUS|ULES|UCUS|UCES|BLUS|BLES|BCUS|BCES|NPUB|NPEB|CUSA|PCSE)[ _.-]?(?:\d{4,5}|\d{3}\.\d{2})\b|\b0100[0-9a-f]{12}\b|\b(?:WUP|HAC)[ _-]P[ _-][A-Z0-9]{4,5}\b"#,with:" ",options:.regularExpression)
  value=value.replacingOccurrences(of:#"(?i)\b(?:rev(?:ision)?[ _.-]*\d+(?:\.\d+)*|v\d+\.\d+(?:\.\d+)*|(?:disc|disk|cd)[ _.-]*\d+)\b"#,with:" ",options:.regularExpression)
  value=value.replacingOccurrences(of:#"(?i)[ _.-]+(?:DUPLEX|iMARS|COMPLEX|PROTOCOL|VENOM|REPACK|PROPER|RELOADED)$"#,with:"",options:.regularExpression)
  return value.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX"))
   .replacingOccurrences(of:"&",with:" and ").replacingOccurrences(of:"’",with:"'").replacingOccurrences(of:"'",with:"")
   .split(whereSeparator:{ !$0.isLetter && !$0.isNumber }).filter { !removeArticles || !["the","a","an"].contains($0) }.joined(separator:" ")
 }
 public static func titleMatches(_ candidate: String, query: String) -> Bool {
  let words=Set(matchingTitle(query).split(separator:" "))
  let title=Set(matchingTitle(candidate).split(separator:" "))
  return !words.isEmpty && words.isSubset(of:title)
 }
 public static func matchScore(_ result: Result, query: String, platform: Platform) -> Int {
  let q=matchingTitle(query), c=matchingTitle(result.title)
  guard !q.isEmpty, titleMatches(result.title,query:query) else { return 0 }
  let same=result.platform == platform
  return (same ? 1000 : 0) + (q == c ? 100 : 30) - abs(c.split(separator:" ").count-q.split(separator:" ").count)
 }
 static let providerIDs: [Platform: String] = [.ps2:"11",.psp:"13",.ps3:"12",.ps4:"4919",.xbox360:"15",.wiiu:"38",.switchConsole:"4971"]
 static func fallbackQueries(_ query: String) -> [String] {
  let full=normalizedTitle(query,removeArticles:false), key=matchingTitle(query)
  let words=full.split(separator:" ")
  // Retain articles for provider phrase search; try a distinctive subtitle last.
  // Full-title validation still applies to every returned candidate.
  var variants=[full]
  if key != full { variants.append(key) }
  if words.count >= 6 { variants.append(words.suffix(4).joined(separator:" ")) }
  var seen=Set<String>()
  return variants.filter { seen.insert($0).inserted }
 }
 static func decodeHTML(_ text: String) -> String {
  var value=text
  for (entity,character) in ["&amp;":"&","&quot;":"\"","&#039;":"'","&#39;":"'","&apos;":"'","&lt;":"<","&gt;":">"] { value=value.replacingOccurrences(of:entity,with:character) }
  for row in captures(#"&#(x[0-9a-f]+|[0-9]+);"#,value) {
   let hex=row[0].lowercased().hasPrefix("x")
   if let n=UInt32(hex ? String(row[0].dropFirst()) : row[0],radix:hex ? 16 : 10),let scalar=UnicodeScalar(n) { value=value.replacingOccurrences(of:"&#"+row[0]+";",with:String(scalar)) }
  }
  return value
 }
 static func publicPageResults(_ html: String, platform: Platform) -> [Result] {
  captures(#"<a\s+href="\./game\.php\?id=[0-9]+"[^>]*>(.*?)</a>"#,html).compactMap { row in
   let card=row[0]
   guard let system=captures(#"<p\s+class="text-muted">([^<]+)</p>"#,card).first?.first,
    let detected=Platform.artworkPlatform(decodeHTML(system)), detected == platform,
    let image=captures(#"<img[^>]+alt="([^"]+) cover"[^>]+src="(https://cdn\.thegamesdb\.net/images/thumb/boxart/front/[^"?]+)""#,card).first,
    let url=URL(string:image[1].replacingOccurrences(of:"/images/thumb/",with:"/images/original/")) else { return nil }
   return Result(title:decodeHTML(image[0]),url:url,platform:detected,provider:"TheGamesDB")
  }
 }
 private func supplemental(_ query: String, platform: Platform) async throws -> [Result] {
  guard let id=Self.providerIDs[platform] else { return [] }
  let key=platform.rawValue+":"+query
  if let saved=pages[key] { return saved }
  var components=URLComponents(string:"https://thegamesdb.net/search.php")!
  components.queryItems=[URLQueryItem(name:"name",value:query),URLQueryItem(name:"platform_id[]",value:id)]
  let data=try await request(components.url!)
  let html=String(decoding:data,as:UTF8.self)
  guard html.contains("platformselect") else { throw AkitoStationError.message("Cover search page unavailable or its format changed") }
  let results=Self.publicPageResults(html,platform:platform)
  pages[key]=results; return results
 }
 public func search(_ query: String, platform: Platform, allSystems: Bool=false) async throws -> [Result] {
  guard !Self.matchingTitle(query).isEmpty else { return [] }
  var results: [Result]=[], errors: [Error]=[]
  let systems=allSystems ? [platform]+Platform.allCases.filter { $0 != platform } : [platform]
  for system in systems {
   for repo in Self.repos(system) {
    try Task.checkCancellation()
    do {
     let paths=try await catalog(repo)
     results += paths.compactMap { path in
      let title=URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent
      guard Self.titleMatches(title,query:query) else { return nil }
      return Result(title:title,url:URL(string:"https://raw.githubusercontent.com/libretro-thumbnails/")!.appendingPathComponent(repo).appendingPathComponent("master").appendingPathComponent(path),platform:system)
     }
    } catch { try Task.checkCancellation(); errors.append(error) }
   }
  }
  // Exact title, then normalized title. No extra network request per normalization variant.
  if !results.contains(where:{ $0.platform == platform && Self.matchingTitle($0.title) == Self.matchingTitle(query) }) {
   for variant in Self.fallbackQueries(query) {
    do {
     results += try await supplemental(variant,platform:platform)
     if results.contains(where:{ $0.platform == platform && Self.titleMatches($0.title,query:query) }) { break }
    } catch { try Task.checkCancellation(); errors.append(error); break }
   }
  }
  var seen=Set<String>()
  results=results.filter { Self.titleMatches($0.title,query:query) && seen.insert($0.id).inserted }
  if results.isEmpty,let error=errors.first { throw error }
  return results.sorted {
   let a=Self.matchScore($0,query:query,platform:platform), b=Self.matchScore($1,query:query,platform:platform)
   return a == b ? $0.title == $1.title ? $0.id<$1.id : $0.title<$1.title : a>b
  }
 }
 public func scrape(_ game: Game) async throws -> Result? {
  let results=try await search(game.title,platform:game.platform)
  // Partial matches are for explicit selection only; do not silently choose a sequel or bundle.
  return results.first { $0.platform == game.platform && Self.matchingTitle($0.title) == Self.matchingTitle(game.title) }
 }
 public func download(_ result: Result) async throws -> Data {
  let data=try await request(result.url)
  guard data.count <= 8*1024*1024, NSBitmapImageRep(data:data) != nil else { throw AkitoStationError.message("Could not download a valid cover smaller than 8 MB") }
  return data
 }
 private static let repositories:[Platform:String]=[.xbox:"Microsoft_-_Xbox",.xbox360:"Microsoft_-_Xbox_360",.wiiu:"Nintendo_-_Wii_U",.ps3:"Sony_-_PlayStation_3",.ps4:"Sony_-_PlayStation_4",.psvita:"Sony_-_PlayStation_Vita",.nes:"Nintendo_-_Nintendo_Entertainment_System",.snes:"Nintendo_-_Super_Nintendo_Entertainment_System",.gb:"Nintendo_-_Game_Boy",.gbc:"Nintendo_-_Game_Boy_Color",.gba:"Nintendo_-_Game_Boy_Advance",.nds:"Nintendo_-_Nintendo_DS",.n64:"Nintendo_-_Nintendo_64",.n3ds:"Nintendo_-_Nintendo_3DS",.gc:"Nintendo_-_GameCube",.wii:"Nintendo_-_Wii",.ps1:"Sony_-_PlayStation",.ps2:"Sony_-_PlayStation_2",.psp:"Sony_-_PlayStation_Portable",.genesis:"Sega_-_Mega_Drive_-_Genesis",.pce:"NEC_-_PC_Engine_-_TurboGrafx_16",.dreamcast:"Sega_-_Dreamcast",.saturn:"Sega_-_Saturn"]
}
