import SwiftUI
import StoreKit
import AkitoStationCore


struct PremiumSettings: View {
    @ObservedObject private var premium = PremiumStore.shared
    @AppStorage("premiumConsoleTheme") private var theme = "Ice"
    @AppStorage("premiumWallpaper") private var wallpaper = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(BuildEdition.isDeveloper ? "Developer · all features available" : (premium.allows(.consoleThemes) ? "Akito Station Premium" : "Akito Station Free")).font(.title2)
            Text("Your library, emulators, controllers and saves are included in Free.")
            Picker("Console-inspired theme", selection: $theme) {
                Text("Ice (default)").tag("Ice"); Text("16-bit violet").tag("Violet"); Text("Arcade green").tag("Arcade")
            }.disabled(!premium.allows(.consoleThemes))
            HStack {
                Button("Choose wallpaper…") {
                    guard premium.allows(.wallpapers) else { return }
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = false
                    guard panel.runModal() == .OK, let source = panel.url else { return }
                    do {
                        let folder = BuildEdition.customizationRoot
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let destination = folder.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
                        try FileManager.default.copyItem(at: source, to: destination); wallpaper = destination.path
                    } catch { NSAlert(error: error).runModal() }
                }.disabled(!premium.allows(.wallpapers))
                Button("Default background") { wallpaper = "" }
            }
            Text("Online profile: service not configured.").foregroundStyle(.secondary)
            Text("Premium includes the console themes and wallpaper controls shown here. Online profiles are unavailable.").font(.caption)

        }.task { await premium.start() }
    }
}
