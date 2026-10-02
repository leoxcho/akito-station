import Foundation
import CryptoKit

public enum AkitoStationError: LocalizedError { case message(String); public var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
public enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
 case nes, snes, gb, gbc, gba, genesis, pce, n64, nds, n3ds, ps1, ps2, ps3, ps4, psp, psvita, gc, wii, wiiu, xbox, xbox360, dreamcast, saturn, switchConsole, unknown
 public var id: String { rawValue }
 public var title: String { switch self { case .nes: return "Nintendo Entertainment System"; case .snes: return "Super Nintendo"; case .gb: return "Game Boy"; case .gbc: return "Game Boy Color"; case .gba: return "Game Boy Advance"; case .genesis: return "Sega Mega Drive"; case .pce: return "PC Engine"; case .n64: return "Nintendo 64"; case .nds: return "Nintendo DS"; case .n3ds: return "Nintendo 3DS"; case .ps1: return "PlayStation"; case .ps2: return "PlayStation 2"; case .ps3: return "PlayStation 3"; case .ps4: return "PlayStation 4"; case .psp: return "PlayStation Portable"; case .psvita: return "PlayStation Vita"; case .gc: return "GameCube"; case .wii: return "Wii"; case .wiiu: return "Wii U"; case .xbox: return "Xbox"; case .xbox360: return "Xbox 360"; case .dreamcast: return "Dreamcast"; case .saturn: return "Sega Saturn"; case .switchConsole: return "Nintendo Switch"; case .unknown: return "Unidentified" } }
 public var core: String? { switch self { case .wiiu:return "cemu";case .xbox:return "xemu";case .xbox360:return "xenia";case .ps3:return "rpcs3";case .ps2:return "armsx2";case .psvita:return "vita3k";case .switchConsole:return "ryujinx";case .ps4:return "shadps4";case .n3ds:return "lime3ds";case .n64:return "parallel_n64";case .psp:return "ppsspp";case .gc,.wii:return "dolphin";case .nes:return "nestopia";case .snes:return "snes9x";case .gb,.gbc:return "gambatte";case .gba:return "mgba";case .ps1:return "duckstation";case .nds:return "melondsds";case .genesis:return "genesis_plus_gx";case .pce:return "mednafen_pce_fast";default:return nil } }
 /// Provider names and imported folder aliases share the same system identity.
 public static func artworkPlatform(_ name: String) -> Platform? {
  let key=name.lowercased().filter { $0.isLetter || $0.isNumber }
  let aliases: [String: Platform] = ["ps2":.ps2,"playstation2":.ps2,"sonyplaystation2":.ps2,"psp":.psp,"playstationportable":.psp,"sonyplaystationportable":.psp,"ps3":.ps3,"playstation3":.ps3,"sonyplaystation3":.ps3,"ps4":.ps4,"playstation4":.ps4,"sonyplaystation4":.ps4,"x360":.xbox360,"xbox360":.xbox360,"microsoftxbox360":.xbox360,"wiiu":.wiiu,"nintendowiiu":.wiiu,"switch":.switchConsole,"nintendoswitch":.switchConsole]
  return aliases[key]
 }
 public static func detect(_ url: URL, header: Data = Data()) -> Platform {
 let ext=url.pathExtension.lowercased()
 if header.starts(with: [0x4e,0x45,0x53,0x1a]) { return .nes }
 let direct:[String:Platform] = ["nes":.nes,"fds":.nes,"sfc":.snes,"smc":.snes,"gb":.gb,"gbc":.gbc,"gba":.gba,"md":.genesis,"gen":.genesis,"smd":.genesis,"pce":.pce,"z64":.n64,"n64":.n64,"v64":.n64,"nds":.nds,"3ds":.n3ds,"cci":.n3ds,"cso":.psp,"pbp":.psp,"gdi":.dreamcast,"nsp":.switchConsole,"xci":.switchConsole,"nro":.switchConsole,"nso":.switchConsole,"nca":.switchConsole,"nsz":.switchConsole,"xcz":.switchConsole,"ncz":.switchConsole,"wud":.wiiu,"wux":.wiiu,"wbfs":.wii,"xex":.xbox360]
 if let p=direct[ext] { return p }
 let folders:[String:Platform] = ["nes":.nes,"snes":.snes,"gb":.gb,"gbc":.gbc,"gba":.gba,"genesis":.genesis,"megadrive":.genesis,"pce":.pce,"n64":.n64,"nds":.nds,"n3ds":.n3ds,"3ds":.n3ds,"ps1":.ps1,"psx":.ps1,"ps2":.ps2,"ps3":.ps3,"ps4":.ps4,"psp":.psp,"psvita":.psvita,"gc":.gc,"gamecube":.gc,"wii":.wii,"wiiu":.wiiu,"xbox":.xbox,"xbox 360":.xbox360,"dreamcast":.dreamcast,"saturn":.saturn,"switch":.switchConsole]
 for part in url.deletingLastPathComponent().pathComponents.reversed() { if let p=artworkPlatform(part) ?? folders[part.lowercased()] {return p} }
 return .unknown
 }
}
public func stableID(_ string:String)->String { SHA256.hash(data:Data(string.utf8)).map{String(format:"%02x",$0)}.joined() }
public struct Location: Codable, Equatable, Sendable {
 public var path:String; public var bookmark:Data?; public var volumeUUID:String?
 public init(_ url:URL) {path=url.path;bookmark=try? url.bookmarkData(options:[],includingResourceValuesForKeys:[.volumeUUIDStringKey],relativeTo:nil);volumeUUID=(try? url.resourceValues(forKeys:[.volumeUUIDStringKey]))?.volumeUUIDString}
 public func resolve() throws -> URL {
 var stale=false
 let url = bookmark.flatMap{try? URL(resolvingBookmarkData:$0,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale)} ?? URL(fileURLWithPath:path)
 var isDir:ObjCBool=false
 guard FileManager.default.fileExists(atPath:url.path,isDirectory:&isDir),isDir.boolValue else {throw AkitoStationError.message("Storage unavailable: \(path). Reconnect the volume or choose a location in Settings.")}
 if let expected=volumeUUID, let actual=(try? url.resourceValues(forKeys:[.volumeUUIDStringKey]))?.volumeUUIDString,expected != actual { throw AkitoStationError.message("The volume at \(path) is not the configured volume.") }
 return url
 }
}
public enum StorageKind:String,CaseIterable,Codable,Identifiable {case saves,states,caches,firmware,controllers,profiles,screenshots,metadata,runtimes,logs,downloads;public var id:String{rawValue};public var title:String{switch self{case .states:return "Save States";case .caches:return "Shader / Pipeline Caches";case .firmware:return "Firmware / BIOS / System Resources";case .metadata:return "Metadata / Database";case .runtimes:return "Runtime Engines";case .downloads:return "Downloads / Build Data";default:return rawValue.capitalized}}}
public struct StorageConfiguration:Codable {
 public var root:Location; public var libraries:[Location]=[];public var overrides:[String:Location]=[:]
 public init(root:Location){self.root=root}
 public func directory(_ kind:StorageKind) throws -> URL {
 if let override=overrides[kind.rawValue]{return try override.resolve()}
 let base=try root.resolve();let dir=base.appendingPathComponent(kind.rawValue,isDirectory:true)
 try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);return dir
 }
}
public struct Game:Codable,Identifiable,Hashable,Sendable {
 public var id:String; public var title:String; public var platform:Platform;public var libraryPath:String;public var relativePath:String;public var bytes:Int64;public var favorite=false;public var lastPlayed:Date?;public var playSeconds:Double=0;public var artwork:String?;public var status="Not tested"
 public var url:URL{URL(fileURLWithPath:libraryPath).appendingPathComponent(relativePath)}
 public init(url:URL,root:URL,bytes:Int64){relativePath=url.pathComponents.suffix(url.pathComponents.count-root.pathComponents.count).joined(separator:"/");libraryPath=root.path;id=stableID(root.path+"/"+relativePath);title=url.deletingPathExtension().lastPathComponent;platform=Platform.detect(url);self.bytes=bytes}
}
public struct GameProfile:Codable,Equatable {
 public var renderer="Metal";public var resolutionScale=1;public var vsync=true;public var aspect="Original";public var volume:Double=0.8;public var fullscreen=false;public var controller="Automatic";public var options:[String:String]=[:];public var knownGoodRuntime:String?;public var verifiedAt:Date?
 public init(){}
 public var coreOptions:String{options.filter{!$0.key.hasPrefix("arm.")}.sorted{$0.key<$1.key}.map{"\($0.key)=\($0.value)"}.joined(separator:"\n")}
}
public enum JSONStore {
 public static func read<T:Decodable>(_ type:T.Type,from url:URL) throws -> T {try JSONDecoder().decode(type,from:Data(contentsOf:url))}
 public static func write<T:Encodable>(_ value:T,to url:URL) throws {let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];try e.encode(value).write(to:url,options:.atomic)}
}
public enum LibraryScanner {
 public static let extensions:Set<String>=["nes","fds","sfc","smc","gb","gbc","gba","md","gen","smd","pce","z64","n64","v64","nds","3ds","cci","cso","pbp","iso","chd","cue","gdi","nsp","xci","nro","nso","nca","nsz","xcz","ncz","wud","wux","wua","wbfs","rvz","gcz","xex","rpx","m3u"]
 public static func scan(_ locations:[Location]) throws -> [Game] {
 var games:[Game]=[];var seen=Set<String>()
 for location in locations {let root=try location.resolve().resolvingSymlinksInPath();var enumerationError:Error?
 guard let enumerator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants],errorHandler:{_,error in enumerationError=error;return true}) else {throw AkitoStationError.message("Cannot enumerate \(root.path)")}
 for case let url as URL in enumerator {
 if let folder=try ConsoleFolder.game(at:url,root:root) {
 enumerator.skipDescendants()
 if seen.insert(url.standardizedFileURL.path).inserted {games.append(folder)}
 continue
 }
 if url.deletingLastPathComponent().lastPathComponent=="game",url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent=="dev_hdd0" {enumerator.skipDescendants();continue}
 guard extensions.contains(url.pathExtension.lowercased()),!url.lastPathComponent.hasPrefix("._"),!url.lastPathComponent.lowercased().hasPrefix("[bios]") else {continue}
 let values=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]);guard values.isRegularFile==true,values.isSymbolicLink != true else{continue}
 guard seen.insert(url.standardizedFileURL.path).inserted else{continue}
 var g=Game(url:url,root:root,bytes:Int64(values.fileSize ?? 0));g.libraryPath=location.path;g.id=stableID(location.path+"/"+g.relativePath);if let f=try? FileHandle(forReadingFrom:url){let h=(try? f.read(upToCount:16)) ?? Data();try? f.close();g.platform=Platform.detect(url,header:h)}
 for ext in ["png","jpg","jpeg"]{let art=url.deletingPathExtension().appendingPathExtension(ext);if FileManager.default.fileExists(atPath:art.path){g.artwork=art.path;break}}
 games.append(g)
 }
 if let e=enumerationError{throw e}
 }
 return games.sorted{$0.title.localizedStandardCompare($1.title) == .orderedAscending}
 }
 public static func merge(_ discovered:[Game],existing:[Game])->[Game]{let old=Dictionary(existing.map{($0.id,$0)},uniquingKeysWith:{$1});return discovered.map{var g=$0;if let p=old[g.id]{g.favorite=p.favorite;g.lastPlayed=p.lastPlayed;g.playSeconds=p.playSeconds;g.status=p.status;if g.artwork==nil{g.artwork=p.artwork}};return g}}
}
