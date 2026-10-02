import Foundation
public enum EditionStorage {
 public static func customizationRoot(support:URL,developer:Bool)->URL{support.appendingPathComponent(developer ? "AkitoStation/Customization":"AkitoStationPublic/Customization")}
 public static func ownsWallpaper(_ path:String,support:URL,developer:Bool)->Bool{URL(fileURLWithPath:path).resolvingSymlinksInPath().path.hasPrefix(customizationRoot(support:support,developer:developer).resolvingSymlinksInPath().path+"/")}
}
