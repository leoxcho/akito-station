import Foundation
/// UI submission is synchronous and ordered; encoding/volume access happens on one worker.
/// A flush barrier lets reload and ordinary app termination wait without blocking the UI.
public enum LibraryPersistence {
 private static let worker=DispatchQueue(label:"app.akitostation.library-writes",qos:.utility)
 public static func submit(_ games:[Game],configuration:StorageConfiguration,completion:@escaping(Error?)->Void) {
  worker.async {
   do{try JSONStore.write(games,to:configuration.directory(.metadata).appendingPathComponent("library.json"));completion(nil)}catch{completion(error)}
  }
 }
 public static func flush(completion:@escaping()->Void){worker.async{completion()}}
 public static func flush()async {await withCheckedContinuation{continuation in flush{continuation.resume()}}}
}
