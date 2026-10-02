import Foundation

/// These platforms require a host-linked engine. Imported desktop executables
/// cannot satisfy that requirement, even when their manifests pass startup checks.
public enum EmbeddedRuntime {
 public static let requiredEngines:Set<String> = ["vita3k", "ryujinx"]
 public static func unavailableReason(engine:String)->String? {
  guard requiredEngines.contains(engine) else{return nil}
  let name=engine == "vita3k" ? "PlayStation Vita":"Nintendo Switch"
  return "\(name): the embedded engine is not available in this build. The installed desktop emulator cannot run inside Akito Station. Standalone launch is disabled."
 }
 public static func requirePlayable(engine:String)throws {
  if let reason=unavailableReason(engine:engine){throw AkitoStationError.message(reason)}
 }
 public static let sourceRepositories:[String:String] = [
  "vita3k":"https://github.com/Vita3K/Vita3K",
  "ryujinx":"https://github.com/enbyte/ryujinx-mirror-cubed"
 ]
}
