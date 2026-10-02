import Foundation
import CryptoKit
public struct RuntimeManifest:Codable,Identifiable,Equatable {
 public var bundleFiles:[String:String]?
 public var publisherTrust:String?
 public var trustStatus:RuntimeTrustStatus?
 public var custom:CustomEmulatorConfiguration?
 public var externalLocation:Location?
 public var platforms:[Platform]?
 public var id:String;public var version:String;public var upstream:String;public var revision:String;public var integrationRevision:String;public var architecture:String;public var library:String;public var sha256:String;public var capabilities:[String];public var channel:String;public var validated:Bool;public var license:String
 public init(id:String,version:String,upstream:String,revision:String,library:String,sha256:String,license:String,validated:Bool=false){self.id=id;self.version=version;self.upstream=upstream;self.revision=revision;self.integrationRevision="1";self.architecture="arm64";self.library=library;self.sha256=sha256;self.capabilities=["softwareVideo","audio","joypad","saveStates","sram"];self.channel="stable";self.validated=validated;self.license=license}
}
public struct RuntimeSelection:Codable {public var current:String;public var previous:String?;public init(current:String,previous:String?=nil){self.current=current;self.previous=previous}}
public struct RuntimeManager {
 public var root:URL; public init(root:URL){self.root=root}
 public struct Damage:Identifiable,Equatable {
  public var id:String { engine+"/"+version }
  public let engine:String;public let version:String;public let reason:String
 }
 public struct Inventory {public var manifests:[RuntimeManifest];public var damaged:[Damage]}
 /// Discovery never hashes executables. Launch/activation perform integrity validation.
 /// Bad registrations remain on disk for repair; unrelated entries load independently.
 public func inventory(validateIntegrity:Bool=false) throws -> Inventory {
  let fm=FileManager.default
  guard fm.fileExists(atPath:root.path) else{return Inventory(manifests:[],damaged:[])}
  var result=Inventory(manifests:[],damaged:[])
  for engine in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles) {
   guard (try? engine.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true else{continue}
   do {
    for version in try fm.contentsOfDirectory(at:engine,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles) {
     guard (try? version.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true else{continue}
     do {
      let manifest=try JSONStore.read(RuntimeManifest.self,from:version.appendingPathComponent("manifest.json"))
      guard safe(manifest.id),safe(manifest.version),manifest.id==engine.lastPathComponent,manifest.version==version.lastPathComponent,safeRelative(manifest.library),manifest.sha256.range(of:"^[a-fA-F0-9]{64}$",options:.regularExpression) != nil else{throw AkitoStationError.message("Invalid runtime manifest identity, executable path or digest")}
      result.manifests.append(manifest)
      if validateIntegrity {do{_=try selected(manifest.id,version:manifest.version)}catch{result.damaged.append(Damage(engine:manifest.id,version:manifest.version,reason:error.localizedDescription))}}
     }catch{result.damaged.append(Damage(engine:engine.lastPathComponent,version:version.lastPathComponent,reason:error.localizedDescription))}
    }
   }catch{result.damaged.append(Damage(engine:engine.lastPathComponent,version:"",reason:error.localizedDescription))}
  }
  return result
 }
 public func manifests() throws -> [RuntimeManifest] {try inventory().manifests}
 /// Quarantine just the damaged version, preserving all files and valid versions.
 public func quarantine(_ damage:Damage)throws {
  guard safe(damage.engine),safe(damage.version) else{throw AkitoStationError.message("Choose a damaged runtime version")}
  let parent=root.appendingPathComponent(damage.engine),folder=parent.appendingPathComponent(damage.version)
  guard folder.resolvingSymlinksInPath().deletingLastPathComponent()==parent.resolvingSymlinksInPath(),parent.resolvingSymlinksInPath().deletingLastPathComponent()==root.resolvingSymlinksInPath() else{throw AkitoStationError.message("Damaged registration escapes storage")}
  try FileManager.default.moveItem(at:folder,to:parent.appendingPathComponent(".quarantined-"+damage.version+"-"+UUID().uuidString))
  if let previous=try? selection(damage.engine),previous.current==damage.version {
   let remaining=try manifests().filter{$0.id==damage.engine && $0.validated}.sorted{$0.version<$1.version}
   let candidate=remaining.first{$0.version==previous.previous && (try? selected($0.id,version:$0.version)) != nil} ?? remaining.first{(try? selected($0.id,version:$0.version)) != nil}
   let selectionFile=parent.appendingPathComponent("selection.json")
   if let candidate=candidate{try JSONStore.write(RuntimeSelection(current:candidate.version),to:selectionFile)}
   else if FileManager.default.fileExists(atPath:selectionFile.path){try FileManager.default.moveItem(at:selectionFile,to:parent.appendingPathComponent(".selection-before-quarantine-"+UUID().uuidString))}
  }
 }
 public func uninstall(_ id:String)throws {
  guard safe(id) else{throw AkitoStationError.message("Invalid runtime identifier")}
  let folder=root.appendingPathComponent(id)
  guard folder.resolvingSymlinksInPath().deletingLastPathComponent()==root.resolvingSymlinksInPath() else{throw AkitoStationError.message("Runtime path escapes its storage directory")}
  if FileManager.default.fileExists(atPath:folder.path){
   let protected:Set<String>=["saves","savestates","roms","games","firmware","bios","keys","memorycards","screenshots","controllerprofiles"]
   if let files=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:nil) {
    for case let file as URL in files where protected.contains(file.lastPathComponent.lowercased()) {throw AkitoStationError.message("User data exists inside this runtime. Move it to user storage before uninstalling; nothing was deleted.")}
   }
   try FileManager.default.removeItem(at:folder)
  }
 }
 public func unregister(_ id:String,version:String)throws {
  guard safe(id),safe(version) else{throw AkitoStationError.message("Invalid runtime identifier")}
  let manifest=try JSONStore.read(RuntimeManifest.self,from:root.appendingPathComponent(id+"/"+version+"/manifest.json"))
  guard manifest.externalLocation != nil,manifest.id==id,manifest.version==version else{throw AkitoStationError.message("Only an External Runtime can be unregistered")}
  let folder=root.appendingPathComponent(id).appendingPathComponent(version)
  guard folder.resolvingSymlinksInPath().deletingLastPathComponent()==root.appendingPathComponent(id).resolvingSymlinksInPath() else{throw AkitoStationError.message("Registration path escapes runtime storage")}
  try FileManager.default.removeItem(at:folder)
  if let current=try? selection(id),current.current==version {
   let remaining=try manifests().filter{$0.id==id && $0.validated}
   if let next=remaining.first {try JSONStore.write(RuntimeSelection(current:next.version),to:root.appendingPathComponent(id+"/selection.json"))}
   else{try? FileManager.default.removeItem(at:root.appendingPathComponent(id+"/selection.json"))}
  }
 }
 public func selection(_ id:String)throws->RuntimeSelection{try JSONStore.read(RuntimeSelection.self,from:root.appendingPathComponent(id).appendingPathComponent("selection.json"))}
 public func selected(_ id:String,version:String?=nil)throws->(RuntimeManifest,URL){let v=try version ?? selection(id).current;guard safe(id),safe(v) else{throw AkitoStationError.message("Invalid runtime identifier")};let folder=root.appendingPathComponent(id).appendingPathComponent(v);let m=try JSONStore.read(RuntimeManifest.self,from:folder.appendingPathComponent("manifest.json"));guard m.validated,(["arm64","universal","x86_64"].contains(m.architecture) || (m.custom != nil && m.architecture=="script")),m.id==id,m.version==v,safeRelative(m.library) else{throw AkitoStationError.message("Runtime has not passed native integration validation")};let base=try m.externalLocation?.resolve() ?? folder;let binary=base.appendingPathComponent(m.library);if m.custom != nil && !FileManager.default.isExecutableFile(atPath:binary.path){throw AkitoStationError.message("Executable not found. Edit this emulator and choose its current location to relink it.")};guard binary.resolvingSymlinksInPath().path.hasPrefix(base.resolvingSymlinksInPath().path+"/") else{throw AkitoStationError.message("Runtime path escapes its version directory")};if let files=m.bundleFiles {let app=m.externalLocation != nil ? base:base.appendingPathComponent(m.library.components(separatedBy:".app/")[0]+".app");guard try RuntimeBundleIntegrity.fingerprint(app)==files else{throw AkitoStationError.message("Runtime nested file integrity check failed: \(id)")}};guard try RuntimeFileHashes.hash(binary)==m.sha256 else{throw AkitoStationError.message("Runtime integrity check failed: \(id)")};return(m,binary)}
 public func activate(_ id:String,version:String)throws { _=try selected(id,version:version);let old=try? selection(id);guard old?.current != version else{return};try JSONStore.write(RuntimeSelection(current:version,previous:old?.current),to:root.appendingPathComponent(id).appendingPathComponent("selection.json")) }
 public func rollback(_ id:String)throws {let s=try selection(id);guard let p=s.previous else{throw AkitoStationError.message("No previous validated runtime")};_=try selected(id,version:p);try JSONStore.write(RuntimeSelection(current:p,previous:s.current),to:root.appendingPathComponent(id).appendingPathComponent("selection.json"))}
 private func safeRelative(_ s:String)->Bool{!s.hasPrefix("/") && s.split(separator:"/",omittingEmptySubsequences:false).allSatisfy{safe(String($0))}}
 private func safe(_ s:String)->Bool{!s.isEmpty && s != "." && s != ".." && !s.contains("/") && !s.contains("\\")}
}
public func digest(_ url:URL)throws->String{let f=try FileHandle(forReadingFrom:url);defer{try? f.close()};var hash=SHA256();while let data=try f.read(upToCount:1024*1024),!data.isEmpty{hash.update(data:data)};return hash.finalize().map{String(format:"%02x",$0)}.joined()}
public enum StorageMover {
 // Copy and verify first. Source is retained deliberately; caller switches configuration only after success.
 public static func copyVerified(from source:URL,to destination:URL)throws {
 let source=source.resolvingSymlinksInPath();let destination=destination.resolvingSymlinksInPath()
 let src=source.resolvingSymlinksInPath().standardizedFileURL.path,dst=destination.resolvingSymlinksInPath().standardizedFileURL.path
 guard dst != src,!dst.hasPrefix(src+"/"),!src.hasPrefix(dst+"/") else{throw AkitoStationError.message("Storage locations must not overlap")}
 guard !FileManager.default.fileExists(atPath:destination.path) else{throw AkitoStationError.message("Migration destination must be a new folder")}
 try FileManager.default.copyItem(at:source,to:destination)
 guard let e=FileManager.default.enumerator(atPath:source.path)else{throw AkitoStationError.message("Cannot verify source")}
 for case let relative as String in e {let file=source.appendingPathComponent(relative);let v=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]);guard v.isSymbolicLink != true else{throw AkitoStationError.message("Migration refuses symbolic links")};if v.isRegularFile==true{guard try digest(file)==digest(destination.appendingPathComponent(relative)) else{throw AkitoStationError.message("Migration verification failed: \(relative)")}}}
 }
}
public struct UpstreamRelease:Codable {public var tag_name:String;public var html_url:String;public var prerelease:Bool;public var body:String?}
public enum UpdateResearch {
 public static func check(repository:String,channel:String="stable") async throws -> UpstreamRelease {
 guard let release=try await GitHubUpdates.releases(repository:repository,channel:channel).first else{throw AkitoStationError.message("No published releases; source revision builds are available.")}
 return UpstreamRelease(tag_name:release.tag_name,html_url:release.html_url,prerelease:release.prerelease,body:release.body)
 }

}
public enum AssistantTool:String,CaseIterable {case scanLibraries,identifyGame,identifyPlatform,inspectRuntime,inspectRuntimeVersion,inspectCompatibilityInformation,validateUserSystemResources,configureGameProfile,configureRenderer,configureController,testBoot,readLogs,compareResults,rollbackConfiguration,saveKnownGoodProfile,researchRuntime,checkRuntimeUpdates}
public struct ResourceRecord:Codable {public var path:String;public var size:Int;public var sha256:String;public var status:String}
public enum ResourceScanner {
 public static func inspect(_ root:URL)throws->[ResourceRecord]{guard let e=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey],options:[.skipsHiddenFiles])else{return []};var results:[ResourceRecord]=[];for case let file as URL in e{let v=try file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey]);guard v.isRegularFile==true else{continue};let size=v.fileSize ?? 0;results.append(ResourceRecord(path:file.path,size:size,sha256:size<32*1024*1024 ? try digest(file):"not hashed (large resource)",status:"User supplied; engine validation required"))};return results}
}
public enum SystemResourceRouter {
 /// Engines receive Akito Station-owned copies, never writable access to the original resource collection.
 public static func prepare(core:String,source:URL,cache:URL,runtime:URL?=nil,imported:[URL]=[])throws->URL {
 let target=cache.appendingPathComponent("SystemResources/"+core,isDirectory:true)
 try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
 if core=="ppsspp",let runtime=runtime{let assets=runtime.deletingLastPathComponent().appendingPathComponent("PPSSPP"),destination=target.appendingPathComponent("PPSSPP");guard FileManager.default.fileExists(atPath:assets.appendingPathComponent("compat.ini").path) else{throw AkitoStationError.message("The PSP runtime is missing its upstream assets")};if !FileManager.default.fileExists(atPath:destination.path){try FileManager.default.copyItem(at:assets,to:destination)}}
 let allowed:Set<String> = core=="pcsx_rearmed" ? ["scph1001.bin","scph5500.bin","scph5501.bin","scph5502.bin","scph7001.bin","scph101.bin"] : core=="melondsds" ? ["bios7.bin","bios9.bin","firmware.bin"] : core=="mgba" ? ["gba_bios.bin","gb_bios.bin","gbc_bios.bin"] : core=="nestopia" ? ["disksys.rom"] : core=="beetle_saturn" ? ["sega_101.bin","mpr-17933.bin","mpr-18811-mx.ic1","mpr-19367-mx.ic1"] : []
 var importedNames=Set<String>()
 for file in imported {
 let normalized=core=="beetle_saturn" ? file.lastPathComponent.lowercased():file.lastPathComponent.lowercased().replacingOccurrences(of:"-",with:"")
 guard allowed.contains(normalized),importedNames.insert(normalized).inserted else{continue}
 let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
 guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 0)<=16*1024*1024 else{throw AkitoStationError.message("Invalid imported BIOS resource")}
 let destination=target.appendingPathComponent(normalized)
 if try !FileManager.default.fileExists(atPath:destination.path) || digest(file) != digest(destination) {
 try Data(contentsOf:file).write(to:destination,options:.atomic)
 }
 }
 if !allowed.isEmpty,let e=FileManager.default.enumerator(at:source,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles]){
 for case let file as URL in e{let normalized=core=="beetle_saturn" ? file.lastPathComponent.lowercased():file.lastPathComponent.lowercased().replacingOccurrences(of:"-",with:"");guard allowed.contains(normalized) else{continue};let v=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]);guard v.isRegularFile==true,v.isSymbolicLink != true else{continue};let dest=target.appendingPathComponent(normalized);if !FileManager.default.fileExists(atPath:dest.path){try FileManager.default.copyItem(at:file,to:dest);guard try digest(file)==digest(dest) else{throw AkitoStationError.message("System resource copy failed verification")}}}
 }
 return target
 }
}

/// Additional embedded cores must explicitly declare their supported consoles.
public enum EmulatorEngines {
 public static func choices(for platform:Platform, installed:[RuntimeManifest])->[String] {
  guard platform != .unknown else{return []}
  var ids=RuntimeCatalog.choices(platform).map(\.id)
  ids += installed.filter{$0.validated && $0.custom != nil && $0.platforms?.contains(platform)==true}.map(\.id)
  ids += installed.filter{$0.validated && ManagedLaunch.platforms(for:$0.id).contains(platform)}.map(\.id)
  ids += installed.filter{$0.validated && $0.platforms?.contains(platform)==true && $0.capabilities.contains("libretro") && $0.capabilities.contains("softwareVideo") && !ManagedLaunch.engines.contains($0.id)}.map(\.id)
  return Array(Set(ids)).sorted()
 }
 public static func selected(for platform:Platform, choice:String?, installed:[RuntimeManifest])->String? {
  let ids=choices(for:platform,installed:installed)
  if let choice=choice,ids.contains(choice){return choice}
  return RuntimeCatalog.selected(platform:platform,system:nil,game:nil,installed:installed)
 }
}
