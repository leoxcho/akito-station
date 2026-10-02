import Foundation
public struct LibraryDiskSnapshot {
 public let sources:[RuntimeSource];public let games:[Game];public let systems:[String:GameProfile]
 public let inventory:RuntimeManager.Inventory;public let controllers:ControllerBindings
 public let profileErrors:[String:String];public let profiles:[String:GameProfile];public let selections:[String:String]
}
public enum LibrarySnapshotLoader {
 /// Injectable reader supports offline latency/disconnection tests without developer tools.
 public static func load(_ configuration:StorageConfiguration,reader:@escaping @Sendable(URL)throws->Data={try Data(contentsOf:$0)})async throws->LibraryDiskSnapshot {
  await LibraryPersistence.flush()
  return try await Task.detached(priority:.userInitiated){
   let metadata=try configuration.directory(.metadata),profiles=try configuration.directory(.profiles),root=try configuration.directory(.runtimes),controllers=try configuration.directory(.controllers)
   func read<T:Decodable>(_ type:T.Type,_ url:URL,_ fallback:T)throws->T{FileManager.default.fileExists(atPath:url.path) ? try JSONDecoder().decode(type,from:reader(url)):fallback}
   var gameProfiles:[String:GameProfile]=[:],profileErrors:[String:String]=[:]
   for file in try FileManager.default.contentsOfDirectory(at:profiles,includingPropertiesForKeys:nil) where file.pathExtension=="json" && file.lastPathComponent != "systems.json" {
    do{gameProfiles[file.deletingPathExtension().lastPathComponent]=try read(GameProfile.self,file,GameProfile())}catch{profileErrors[file.deletingPathExtension().lastPathComponent]=error.localizedDescription}
   }
   let manager=RuntimeManager(root:root),inventory=try manager.inventory(validateIntegrity:true)
   var selections:[String:String]=[:]
   for id in Set(inventory.manifests.map(\.id)){selections[id]=(try? manager.selection(id))?.current}
   return LibraryDiskSnapshot(sources:try read([RuntimeSource].self,metadata.appendingPathComponent("runtime-sources.json"),[]),games:try read([Game].self,metadata.appendingPathComponent("library.json"),[]),systems:try read([String:GameProfile].self,profiles.appendingPathComponent("systems.json"),[:]),inventory:inventory,controllers:try read(ControllerBindings.self,controllers.appendingPathComponent("bindings.json"),ControllerBindings()),profileErrors:profileErrors,profiles:gameProfiles,selections:selections)
  }.value
 }
}
