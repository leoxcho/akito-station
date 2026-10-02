import Foundation
import AkitoStationCore


enum BuildEdition {
    // Unknown configurations fail closed, including future build entry points.
    static let isDeveloper = false
    static let name = "Akito Station Public"
    static var customizationRoot:URL {
        EditionStorage.customizationRoot(support:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0],developer:isDeveloper)
    }
    static func ownsWallpaper(_ path:String)->Bool {
        URL(fileURLWithPath:path).resolvingSymlinksInPath().path.hasPrefix(customizationRoot.resolvingSymlinksInPath().path+"/")
    }
    static func migrateLegacyPreferences() {
    }
    static func visibleSetting(_ text: String) -> Bool {
        isDeveloper || !["debug", "experimental", "trace", "logging", "validation", "dump", "developer"].contains { text.lowercased().contains($0) }
    }
}
