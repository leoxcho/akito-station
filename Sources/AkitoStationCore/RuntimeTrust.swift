import Foundation
public enum RuntimeTrustStatus:String,Codable,Sendable {
 case verifiedPublisher="Verified Publisher",verifiedChecksum="Verified Checksum",officialUnsigned="Official Source / Unsigned",officialUnverified="Official Source / Publisher Unverified",userImported="User Imported",customExternal="Custom External",unverified="Unverified"
}
public struct RuntimeDownloadTrust:Sendable {
 public let engine:String;public let repository:String;public private(set) var asset:ReleaseAsset;public let release:String
 /// A Team ID must have independently reviewed upstream evidence before pinning.
 public let expectedTeam:String?
 public init(definition:RuntimeDefinition,asset:ReleaseAsset,release:RuntimeRelease,repository:String,expectedTeam:String?=nil)throws {
  guard definition.installation == .githubRelease,definition.releaseRepository==repository,release.assets.contains(asset),asset.isMacCandidate,asset.name.lowercased().hasSuffix(".zip") else{throw AkitoStationError.message("Release asset is outside the approved catalog integration")}
  let url=try GitHubUpdates.downloadURL(asset,repository:repository)
  let components=url.pathComponents
  guard components.count==7,components[5]==release.tag_name,release.html_url==repository+"/releases/tag/"+release.tag_name else{throw AkitoStationError.message("Release tag or asset identity mismatch")}
  let name=asset.name.lowercased()
  let tokens:[String:[String]]=["pcsx2":["pcsx2"],"rpcs3":["rpcs3"],"shadps4":["shadps4"],"vita3k":["macos"],"azahar":["azahar"],"cemu":["cemu"],"xemu":["xemu"],"flycast":["flycast"]]
  guard let allowed=tokens[definition.id],allowed.contains(where:name.contains) else{throw AkitoStationError.message("Unexpected catalog release filename")}
  if let digest=asset.digest {guard digest.hasPrefix("sha256:"),digest.dropFirst(7).range(of:"^[0-9a-fA-F]{64}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Malformed official asset checksum")}}
  self.engine=definition.id;self.repository=repository;self.asset=asset;self.release=release.tag_name;self.expectedTeam=expectedTeam
 }
 public func resolvingOfficialChecksum(release:RuntimeRelease,folder:URL)async throws->RuntimeDownloadTrust {
  guard asset.digest==nil else{return self}
  let names=[asset.name+".sha256",asset.name+".sha256sum","SHA256SUMS","SHA256SUMS.txt","checksums.txt"]
  let checks=release.assets.filter{names.contains($0.name)}
  guard !checks.isEmpty else{return self}
  guard checks.count==1,let checksum=checks.first,checksum.size>0,checksum.size<=1024*1024 else{throw AkitoStationError.message("Ambiguous or oversized upstream checksum manifest")}
  let file=try await GitHubUpdates.download(checksum,repository:repository,into:folder)
  defer{try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
  let text=try String(contentsOf:file)
  let value=try Self.checksum(text,filename:asset.name,singleFile:checksum.name.hasPrefix(asset.name+"."))
  var resolved=self;resolved.asset.digest="sha256:"+value;return resolved
 }
 public static func checksum(_ text:String,filename:String,singleFile:Bool)throws->String {
  var matches:[String]=[]
  for line in text.split(whereSeparator:{$0.isNewline}) {
   let words=line.split(whereSeparator:{$0.isWhitespace})
   if words.count==1,singleFile,words[0].count==64{matches.append(String(words[0]))}
   else if words.count==2,(words[1].hasPrefix("*") ? String(words[1].dropFirst()):String(words[1]))==filename{matches.append(String(words[0]))}
   else if line.hasPrefix("SHA256 ("+filename+") = "){matches.append(String(line.dropFirst(("SHA256 ("+filename+") = ").count)))}
  }
  guard matches.count==1,let value=matches.first,value.range(of:"^[0-9a-fA-F]{64}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Official checksum does not uniquely identify this release asset")}
  return value.lowercased()
 }
 public func status(signed:Bool,adhoc:Bool,team:String?)throws->RuntimeTrustStatus {
  if let expectedTeam {guard signed,!adhoc,team==expectedTeam else{throw AkitoStationError.message("Upstream publisher identity mismatch")};return .verifiedPublisher}
  if asset.digest != nil{return .verifiedChecksum}
  return !signed || adhoc ? .officialUnsigned:.officialUnverified
 }
}
