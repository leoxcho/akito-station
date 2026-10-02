import Foundation

public enum SettingsReset {
 public static func defaultStorage(preferences:URL)throws->StorageConfiguration {
  let root=preferences.deletingLastPathComponent().appendingPathComponent("Data")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  return StorageConfiguration(root:Location(root))
 }
 /// Retain each configuration beside its original location for recovery.
 public static func archive(_ files:[URL])throws {
  let fm=FileManager.default, suffix="before-reset-"+UUID().uuidString
  var moved:[(URL,URL)]=[]
  do {
   for file in Set(files) where fm.fileExists(atPath:file.path) {
    let backup=file.appendingPathExtension(suffix)
    try fm.moveItem(at:file,to:backup);moved.append((file,backup))
   }
  }catch{for (file,backup) in moved.reversed(){try? fm.moveItem(at:backup,to:file)};throw error}
 }
 public static func configurationFiles(storage:StorageConfiguration)throws->[URL] {
  let fm=FileManager.default
  let profiles=try storage.directory(.profiles),controllers=try storage.directory(.controllers)
  var files=try fm.contentsOfDirectory(at:profiles,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json" && ($0.lastPathComponent=="systems.json" || ($0.deletingPathExtension().lastPathComponent.count==64 && $0.deletingPathExtension().lastPathComponent.allSatisfy{$0.isHexDigit}))}
  files += (["bindings"]+Platform.allCases.map(\.rawValue)).map{controllers.appendingPathComponent($0+".json")}
  files.append(try storage.directory(.metadata).appendingPathComponent("runtime-sources.json"))
  for engine in EmulatorSettings.files.keys {
   files += try EmulatorSettings.documents(engine:engine,data:storage.directory(.saves).appendingPathComponent("Systems/"+engine))
  }
  return files
 }
}
