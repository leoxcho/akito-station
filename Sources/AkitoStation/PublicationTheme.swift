import SwiftUI

enum IceTheme {
 static let red = Color.accentColor
 static let gold = Color.secondary
 static let cyan = Color.accentColor
 static let blue = Color.accentColor
 static let purple = Color.secondary
 static let pale = Color.primary
 static let navy = Color(nsColor: .windowBackgroundColor)
 static let chrome = LinearGradient(colors: [.primary, .primary], startPoint: .top, endPoint: .bottom)
 static let panel = LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .controlBackgroundColor)], startPoint: .top, endPoint: .bottom)
}
struct IceBackdrop: View {
 var body: some View { Color(nsColor: .windowBackgroundColor).ignoresSafeArea().allowsHitTesting(false) }
}
enum AppLogo: String, CaseIterable, Identifiable {
 case aurora, classic, chrome, neon, ice, gold, blueprint
 var id: String { rawValue }
 var title: String { rawValue.capitalized }
 var image: NSImage? {
  Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("logo_" + rawValue + ".png")) }
 }
}
struct StationMark: View {
 @AppStorage("appLogo.v1") private var selection = "aurora"
 var logo: AppLogo { AppLogo(rawValue: selection) ?? .aurora }
 var body: some View {
  Group {
   if let image = logo.image { Image(nsImage: image).resizable().scaledToFit() }
   else { Text("AS").font(.title) }
  }.frame(width: 44, height: 44).accessibilityLabel("Akito Station")
   .onAppear { NSApplication.shared.applicationIconImage = logo.image }
   .onChange(of: selection) { _, _ in NSApplication.shared.applicationIconImage = logo.image }
 }
}
struct AppLogoSettings: View {
 @AppStorage("appLogo.v1") private var selection = "aurora"
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   Text("App Logo").font(.headline)
   LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 12) {
    ForEach(AppLogo.allCases) { logo in
     Button {
      selection = logo.rawValue
      NSApplication.shared.applicationIconImage = logo.image
     } label: {
      VStack {
       if let image = logo.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 72, height: 72) }
       Text(logo.title + (selection == logo.rawValue ? " ✓" : ""))
      }.frame(maxWidth: .infinity).padding(8)
     }.accessibilityLabel(logo.title + " app logo" + (selection == logo.rawValue ? " selected" : ""))
    }
   }
   Text("Applies inside Akito Station and to its Dock icon while running. Finder uses the packaged default icon.").font(.caption).foregroundStyle(.secondary)
  }
 }
}
