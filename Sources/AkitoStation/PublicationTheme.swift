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
struct StationMark: View {
 var body: some View { Text("A").font(.title).frame(width: 44, height: 44).accessibilityLabel("Akito Station") }
}
