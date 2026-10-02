import Foundation

/// Paths are relative to Akito Station's per-engine data directory, never an upstream installation.
public enum EmulatorSettings {
 public static let files:[String:[String]] = [
 "ppsspp_sdl":["home/.config/ppsspp/PSP/SYSTEM/ppsspp.ini","home/.config/ppsspp/PSP/SYSTEM/controls.ini"],
 "duckstation":["home/Library/Application Support/DuckStation/settings.ini"],
 "dolphin":["Dolphin/Config/GFX.ini","Dolphin/Config/Dolphin.ini","Dolphin/Config/GCPadNew.ini","Dolphin/Config/WiimoteNew.ini","Dolphin/Config/FreeLookController.ini","Dolphin/Config/FreeLook.ini","Dolphin/Config/GCKeyNew.ini","Dolphin/Config/DSUClient.ini"],
 "armsx2":["inis/PCSX2.ini"],
 "pcsx2":["inis/PCSX2.ini"],
 "rpcs3":["home/Library/Application Support/rpcs3/config.yml","home/Library/Application Support/rpcs3/input_configs/global/Default.yml","home/Library/Application Support/rpcs3/input_configs/active_profiles.yml"],
 "vita3k":["config.yml"],"ryujinx":["Config.json"],
 "lime3ds":["home/Library/Application Support/Lime3DS/config/qt-config.ini"],
 "shadps4":["home/Library/Application Support/shadPS4/config.toml","home/Library/Application Support/shadPS4/input_config/default.ini"],
 "cemu":["home/Library/Application Support/Cemu/settings.xml","home/Library/Application Support/Cemu/controllerProfiles/controller0.xml"],
 "xemu":["xemu.toml"],"xenia":["xenia-edge.config.toml"]]
 public static func native(_ profile:GameProfile)->Bool {profile.options["arm.settings.native"] == "true"}
 public static func documents(engine:String,data:URL)throws->[URL] {
 let fm=FileManager.default
 var result=(files[engine] ?? []).map{data.appendingPathComponent($0)}.filter{fm.fileExists(atPath:$0.path)}
 let subfolders:[String:[String]]=["duckstation":["home/Library/Application Support/DuckStation/inputprofiles"],"dolphin":["Dolphin/Config/Profiles","Dolphin/GameSettings"],"rpcs3":["home/Library/Application Support/rpcs3/input_configs"],"cemu":["home/Library/Application Support/Cemu/controllerProfiles"],"shadps4":["home/Library/Application Support/shadPS4/input_config"]]
 for relative in subfolders[engine] ?? [] {
 if let e=fm.enumerator(at:data.appendingPathComponent(relative),includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:.skipsHiddenFiles) {
 for case let u as URL in e where ["ini","yml","xml","json","toml"].contains(u.pathExtension) {
 let v=try u.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]);if v.isSymbolicLink==true{e.skipDescendants();continue};if v.isRegularFile==true,!result.contains(u){result.append(u)}
 }
 }
 }
 let owned=data.resolvingSymlinksInPath().path+"/"
 return result.filter{$0.resolvingSymlinksInPath().path.hasPrefix(owned)}.sorted{$0.path<$1.path}
 }
 public static func save(_ text:String,to file:URL,original:String)throws {
 guard try String(contentsOf:file)==original else{throw AkitoStationError.message("The emulator changed this file. Reload before saving.")}
 guard text.utf8.count<=4*1024*1024 else{throw AkitoStationError.message("Settings file is too large")}
 if file.pathExtension=="json"{_ = try JSONSerialization.jsonObject(with:Data(text.utf8),options:.fragmentsAllowed)}
 if file.pathExtension=="xml"{_ = try XMLDocument(xmlString:text,options:[])}
 let backup=file.appendingPathExtension("before-arm-settings")
 if !FileManager.default.fileExists(atPath:backup.path){try Data(original.utf8).write(to:backup,options:.atomic)}
 try Data(text.utf8).write(to:file,options:.atomic)
 }
}

/// Lossless line editing for native INI, TOML and YAML. Nested values keep their indentation.
public struct NativeSetting:Identifiable {
 public var id:Int;public var section:String;public var key:String;public var value:String;public var prefix:String;public var suffix:String
 public var title:String {key.replacingOccurrences(of:"_",with:" ")}
 public static func rows(_ text:String,format:String="ini")->[NativeSetting] {
 var section="General";var result:[NativeSetting]=[];var yaml:[(Int,String)]=[]
 for (i,line) in text.components(separatedBy:"\n").enumerated() {
 let trimmed=line.trimmingCharacters(in:.whitespaces)
 if trimmed.hasPrefix("["),trimmed.hasSuffix("]"){section=trimmed;continue}
 if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";"){continue}
 if trimmed.hasPrefix("- "),["yml","yaml"].contains(format) {
 let group=yaml.map{$0.1}.joined(separator:" / ");let count=result.filter{$0.section==group}.count
 let dash=line.firstIndex(of:"-")!;let prefix=String(line[...line.index(after:dash)])
 result.append(NativeSetting(id:i,section:group,key:"Binding \(count+1)",value:String(trimmed.dropFirst(2)),prefix:prefix,suffix:""));continue
 }
 let separator:Character = format == "yml" || format == "yaml" ? ":":"="
 guard let split=line.firstIndex(of:separator) else{continue}
 let key=line[..<split].trimmingCharacters(in:.whitespaces)
 guard !key.isEmpty,!key.contains("<") else{continue}
 let tail=String(line[line.index(after:split)...]);var quote:Character?;var escaped=false;var comment:String.Index?
 for index in tail.indices {
 let c=tail[index]
 if escaped{escaped=false;continue};if c=="\\",quote != nil{escaped=true;continue}
 if let q=quote{if c==q{quote=nil};continue}
 if c=="\"" || c=="'"{quote=c;continue}
 if c=="#" || (c==";" && format != "yml" && format != "yaml"){comment=index;break}
 }
 let valuePart=comment.map{String(tail[..<$0])} ?? tail
 let value=valuePart.trimmingCharacters(in:.whitespaces)
 let suffix=comment.map{" "+String(tail[$0...])} ?? ""
 let indent=line.prefix(while:{$0==" "}).count
 if separator==":" {
 while let last=yaml.last,last.0>=indent{yaml.removeLast()}
 if value.isEmpty{yaml.append((indent,key));continue}
 section=yaml.map{$0.1}.joined(separator:" / ");if section.isEmpty{section="General"}
 }
 result.append(NativeSetting(id:i,section:section,key:key,value:value,prefix:String(line[...split])+" ",suffix:suffix))
 }
 return result
 }
 public func replacing(in text:String,with value:String)->String {
 var lines=text.components(separatedBy:"\n");guard id<lines.count,!value.contains("\n"),!value.contains("\r") else{return text};lines[id]=prefix+value+suffix;return lines.joined(separator:"\n")
 }
}
