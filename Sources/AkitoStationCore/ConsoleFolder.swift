import Foundation

/// Bounded little-endian PARAM.SFO reader shared by PS3, PS4 and Vita folder discovery.
public enum ParamSFO {
 public static func read(_ url:URL)throws->[String:String] {
 let d=try Data(contentsOf:url);guard d.count>=20,d.count<=1024*1024,d.prefix(4)==Data([0,80,83,70]) else{return [:]}
 func u(_ offset:Int,_ count:Int)->Int {guard offset>=0,offset+count<=d.count else{return -1};return (0..<count).reduce(0){$0 | Int(d[offset+$1]) << ($1*8)}}
 let keys=u(8,4),values=u(12,4),count=u(16,4)
 guard count>=0,count<4096,20+count*16<=d.count,keys>=20,values>=keys,values<=d.count else{return [:]}
 var result:[String:String]=[:]
 for i in 0..<count {let e=20+i*16;let k=keys+u(e,2),v=values+u(e+12,4),length=u(e+4,4)
 guard k>=keys,k<values,v>=values,length>=0,length<=d.count-v,let end=d[k..<values].firstIndex(of:0) else{continue}
 let key=String(decoding:d[k..<end],as:UTF8.self)
 if u(e+2,2)==0x0204 {result[key]=String(decoding:d[v..<v+length].prefix(while:{$0 != 0}),as:UTF8.self)}
 }
 return result
 }
}
public enum ConsoleFolder {
 public static func game(at url:URL,root:URL)throws->Game? {
 let fm=FileManager.default
 let properties=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
 guard properties.isDirectory==true,properties.isSymbolicLink != true else{return nil}
 let disc=url.appendingPathComponent("PS3_GAME")
 let content=fm.fileExists(atPath:disc.appendingPathComponent("PARAM.SFO").path) ? disc:url
 if fm.fileExists(atPath:content.appendingPathComponent("PARAM.SFO").path),fm.fileExists(atPath:content.appendingPathComponent("USRDIR/EBOOT.BIN").path) {
 let info=try ParamSFO.read(content.appendingPathComponent("PARAM.SFO"))
 guard ["DG","HG"].contains(info["CATEGORY"] ?? "") else{return nil}
 var g=Game(url:url,root:root,bytes:0);g.platform = .ps3;g.title=info["TITLE"] ?? url.lastPathComponent
 let icon=content.appendingPathComponent("ICON0.PNG");if fm.fileExists(atPath:icon.path){g.artwork=icon.path};return g
 }
 if fm.fileExists(atPath:url.appendingPathComponent("sce_sys/param.sfo").path),fm.fileExists(atPath:url.appendingPathComponent("eboot.bin").path) {
 let info=try ParamSFO.read(url.appendingPathComponent("sce_sys/param.sfo"));var g=Game(url:url,root:root,bytes:0)
 // sce_module is shared by PS4 and Vita; title metadata takes precedence over folder hints.
 let titleID=(info["TITLE_ID"] ?? "").uppercased()
 if titleID.hasPrefix("CUSA") {g.platform = .ps4}
 else if titleID.hasPrefix("PCS") {g.platform = .psvita}
 else {
 let hint=url.pathComponents.reversed().map{$0.lowercased()}.first{["ps4","psvita","ux0"].contains($0)}
 g.platform = hint == "psvita" || hint == "ux0" ? .psvita:.ps4
 }
 g.title=info["TITLE"] ?? url.lastPathComponent;return g
 }
 return nil
 }
}
