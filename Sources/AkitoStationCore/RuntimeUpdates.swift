import Foundation

public struct GitHubRepository: Equatable, Codable, Sendable {
 public let owner:String
 public let name:String
 public var slug:String { owner+"/"+name }
 public var url:String { "https://github.com/"+slug }
 public init(_ input:String)throws {
  let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
  guard let u=URLComponents(string:text),u.scheme?.lowercased()=="https",u.host?.lowercased()=="github.com",u.user==nil,u.password==nil,u.port==nil,u.query==nil,u.fragment==nil else {throw AkitoStationError.message("Enter a GitHub repository URL, such as https://github.com/owner/emulator.")}
  let parts=u.path.split(separator:"/",omittingEmptySubsequences:true)
  guard parts.count==2 else{throw AkitoStationError.message("Use the repository link, without a release, branch or file path.")}
  let owner=String(parts[0]);var name=String(parts[1]);if name.hasSuffix(".git"){name=String(name.dropLast(4))}
  let valid: (String)->Bool = { !$0.isEmpty && $0 != "." && $0 != ".." && $0.range(of:"^[A-Za-z0-9_.-]+$",options:.regularExpression) != nil }
  guard valid(owner),valid(name) else{throw AkitoStationError.message("Invalid GitHub repository name.")}
  self.owner=owner;self.name=name
 }
}
public struct RuntimeSource:Codable,Identifiable,Equatable,Sendable {
 public var id:String
 public var name:String
 public var repository:String
 /// Empty means track and download releases until a compatible Akito Station adapter exists.
 public var engine:String
 public var channel:String
 public init(name:String,repository:String,engine:String="",channel:String="stable")throws {
  let repo=try GitHubRepository(repository)
  guard engine.isEmpty || ManagedLaunch.engines.contains(engine) else{throw AkitoStationError.message("Choose an available runtime adapter.")}
  if repo.url.lowercased()=="https://github.com/pcsx2/pcsx2",!engine.isEmpty,engine != "pcsx2"{throw AkitoStationError.message("PCSX2 belongs to PlayStation 2 and requires the PCSX2 adapter.")}
  guard ["stable","prerelease"].contains(channel) else{throw AkitoStationError.message("Invalid update channel.")}
  self.id=UUID().uuidString;self.name=name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? repo.name:name.trimmingCharacters(in:.whitespacesAndNewlines);self.repository=repo.url;self.engine=engine;self.channel=channel
 }
 public static func save(_ source:RuntimeSource,to file:URL)throws->[RuntimeSource] {
  var entries=FileManager.default.fileExists(atPath:file.path) ? try JSONStore.read([RuntimeSource].self,from:file):[]
  guard !entries.contains(where:{$0.repository.lowercased()==source.repository.lowercased()}) else{throw AkitoStationError.message("This GitHub repository is already in your custom emulators.")}
  entries.append(source);try JSONStore.write(entries,to:file);return entries
 }
}
public struct ReleaseAsset:Codable,Identifiable,Equatable,Sendable {
 public var id:Int;public var name:String;public var browser_download_url:String;public var size:Int64;public var digest:String?
 public var isMacCandidate:Bool {let n=name.lowercased();return ["mac","darwin","osx"].contains(where:n.contains) && !["x64","x86_64","intel","symbols","debug"].contains(where:n.contains)}
}
public struct RuntimeRelease:Codable,Identifiable,Sendable {
 public var tag_name:String;public var html_url:String;public var prerelease:Bool;public var body:String?;public var assets:[ReleaseAsset]
 public var id:String {tag_name}
}
public enum GitHubUpdates {
 public static func releaseRepository(engine:String,upstream:String)->String {
  engine=="rpcs3" ? "https://github.com/RPCS3/rpcs3-binaries-mac-arm64":upstream
 }
 static func data(repository:String,path:String)async throws->Data {
  let repo=try GitHubRepository(repository)
  let url=URL(string:"https://api.github.com/repos/"+repo.slug+"/"+path)!
  var request=URLRequest(url:url,timeoutInterval:45)
  request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
  request.setValue("AkitoStation",forHTTPHeaderField:"User-Agent")
  let session=URLSession(configuration:.ephemeral,delegate:NoGitHubAPIRedirects(),delegateQueue:nil)
  defer{session.invalidateAndCancel()}
  let(bytes,response)=try await session.bytes(for:request)
  var data=Data()
  for try await byte in bytes {guard data.count<8*1024*1024 else{throw AkitoStationError.message("GitHub metadata exceeds limits")};data.append(byte)}
  guard let http=response as? HTTPURLResponse else{throw AkitoStationError.message("GitHub returned an invalid response.")}
  guard http.statusCode==200 else{
   if http.statusCode==403 || http.statusCode==429{throw AkitoStationError.message("GitHub’s request limit was reached. Try again later.")}
   if http.statusCode==404{throw AkitoStationError.message("GitHub repository was not found or is private.")}
   throw AkitoStationError.message("GitHub request failed (HTTP \(http.statusCode)).")
  };return data
 }
 public static func releases(repository:String,channel:String="stable")async throws->[RuntimeRelease] {
  let data=try await data(repository:repository,path:"releases?per_page=100")
  return try JSONDecoder().decode([RuntimeRelease].self,from:data).filter{channel != "stable" || !$0.prerelease}
 }
 public static func sourceRevision(repository:String,channel:String="stable")async throws->String {
  if let release=try await releases(repository:repository,channel:channel).first{return release.tag_name}
  struct Commit:Decodable{var sha:String}
  let commits=try JSONDecoder().decode([Commit].self,from:await data(repository:repository,path:"commits?per_page=1"))
  guard let sha=commits.first?.sha,sha.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Repository has no buildable source revision.")};return sha
 }
 public static func downloadURL(_ asset:ReleaseAsset,repository:String)throws->URL {
  let repo=try GitHubRepository(repository)
  guard let u=URL(string:asset.browser_download_url),let c=URLComponents(url:u,resolvingAgainstBaseURL:false),c.scheme=="https",c.host=="github.com",c.user==nil,c.password==nil,c.port==nil,c.query==nil,c.fragment==nil,u.path.lowercased().hasPrefix("/"+repo.slug.lowercased()+"/releases/download/"),asset.size>0,asset.size<=RuntimeArchiveLimits().downloadBytes,u.lastPathComponent==asset.name,!asset.name.isEmpty,asset.name != ".",asset.name != "..",!asset.name.contains("/"),!asset.name.contains("\\") else{throw AkitoStationError.message("Invalid release download URL or filename.")}
  return u
 }
 public static func verifyDownload(_ file:URL,asset:ReleaseAsset)throws {
  let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
  guard asset.size>0,Int64(size)==asset.size else{throw AkitoStationError.message("Release download is incomplete; size verification failed.")}
  if let expected=asset.digest {
   guard expected.hasPrefix("sha256:"),expected.count==71,try "sha256:"+digest(file)==expected.lowercased() else{throw AkitoStationError.message("Release checksum verification failed.")}
  }
 }
 public static func download(_ asset:ReleaseAsset,repository:String,into folder:URL)async throws->URL {
  let url=try downloadURL(asset,repository:repository)
  let free=(try FileManager.default.attributesOfFileSystem(forPath:folder.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
  guard free>=asset.size+16*1024*1024 else{throw AkitoStationError.message("Insufficient disk space for runtime download")}
  guard FileManager.default.isWritableFile(atPath:folder.path) else{throw AkitoStationError.message("Download storage is unavailable.")}
  let delegate=RuntimeDownloadRedirectPolicy()
  let session=URLSession(configuration:.ephemeral,delegate:delegate,delegateQueue:nil)
  defer{session.invalidateAndCancel()}
  let file=folder.appendingPathComponent(".download-"+UUID().uuidString)
  guard FileManager.default.createFile(atPath:file.path,contents:nil) else{throw AkitoStationError.message("Cannot stage runtime download")}
  defer{try? FileManager.default.removeItem(at:file)}
  let output=try FileHandle(forWritingTo:file);defer{try? output.close()}
  let(bytes,response)=try await session.bytes(for:URLRequest(url:url,timeoutInterval:600))
  guard (response as? HTTPURLResponse)?.statusCode==200,let final=response.url,RuntimeDownloadRedirectPolicy.approved(final),response.expectedContentLength<=RuntimeArchiveLimits().downloadBytes else{throw AkitoStationError.message("Unapproved or oversized runtime download response")}
  var count:Int64=0,buffer=Data();buffer.reserveCapacity(65536)
  for try await byte in bytes {
   try Task.checkCancellation();count+=1
   guard count<=asset.size,count<=RuntimeArchiveLimits().downloadBytes else{throw AkitoStationError.message("Runtime download exceeds declared size")}
   buffer.append(byte)
   if buffer.count==65536{try output.write(contentsOf:buffer);buffer.removeAll(keepingCapacity:true)}
  }
  try output.write(contentsOf:buffer);try output.synchronize()
  try verifyDownload(file,asset:asset)
  let destination=folder.appendingPathComponent(UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
  let target=destination.appendingPathComponent(asset.name)
  do{try FileManager.default.moveItem(at:file,to:target);try JSONStore.write(asset,to:destination.appendingPathComponent("github-asset.json"))}
  catch{try? FileManager.default.removeItem(at:destination);throw error}
  return target
 }
}

public final class RuntimeDownloadRedirectPolicy:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
 public static func approved(_ url:URL)->Bool {
  guard let c=URLComponents(url:url,resolvingAgainstBaseURL:false),c.scheme=="https",c.user==nil,c.password==nil,c.port==nil else{return false}
  return ["github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"].contains(c.host?.lowercased() ?? "")
 }
 public func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(request.url.map{Self.approved($0)}==true ? request:nil)}
}

private final class NoGitHubAPIRedirects:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}

public enum PublicRuntimeUpdateValidation {
 /// Library/game state never selects a Developer probe.
 public static func coreArguments(gamePath:String?)->[String]{["--abi-only"]}
}
