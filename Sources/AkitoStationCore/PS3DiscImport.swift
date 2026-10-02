import Foundation

public enum PS3DiscImport {
 public static func prepare(_ image:URL,into root:URL)throws->URL {
 guard image.pathExtension.lowercased()=="iso" else{return image}
 let destination=root.appendingPathComponent("discs/"+stableID(image.path))
 if FileManager.default.fileExists(atPath:destination.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN").path){return destination}
 let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/hdiutil");process.arguments=["attach","-readonly","-nobrowse","-plist",image.path];process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
 try process.run();let output=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
 guard process.terminationStatus==0,let plist=try PropertyListSerialization.propertyList(from:output,format:nil) as? [String:Any],let entities=plist["system-entities"] as? [[String:Any]] else{throw AkitoStationError.message("PS3 disc image could not be mounted read-only. Supply an extracted, decrypted PS3_GAME folder.")}
 let devices=entities.compactMap{$0["dev-entry"] as? String}
 defer{if let device=devices.first{let detach=Process();detach.executableURL=URL(fileURLWithPath:"/usr/bin/hdiutil");detach.arguments=["detach",device];detach.standardOutput=FileHandle.nullDevice;detach.standardError=FileHandle.nullDevice;try? detach.run();detach.waitUntilExit()}}
 guard let mount=entities.compactMap({$0["mount-point"] as? String}).map({URL(fileURLWithPath:$0)}).first(where:{FileManager.default.fileExists(atPath:$0.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN").path)}) else{throw AkitoStationError.message("This image does not contain a PS3_GAME folder. Encrypted images must be decrypted with your own disc key first.")}
 try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
 let staging=destination.deletingLastPathComponent().appendingPathComponent(".import-"+UUID().uuidString)
 do{try StorageMover.copyVerified(from:mount,to:staging);try FileManager.default.moveItem(at:staging,to:destination)}catch{try? FileManager.default.removeItem(at:staging);throw error}
 return destination
 }
}
