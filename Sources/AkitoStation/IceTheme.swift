import SwiftUI

// Shared Akito identity; retain existing component names and saved theme preferences.
enum IceTheme {
 static let red = Color(red: 1, green: 0.025, blue: 0.10)
 static let gold = Color(red: 1, green: 0.68, blue: 0.25)
 static let cyan = Color(red: 0.24, green: 0.78, blue: 0.76)
 static let blue = Color(red: 0.27, green: 0.60, blue: 0.88)
 static let purple = Color(red: 0.29, green: 0.19, blue: 0.48)
 static let pale = Color(red: 0.94, green: 0.94, blue: 0.98)
 static let navy = Color(red: 0.025, green: 0.035, blue: 0.085)
 static let chrome = LinearGradient(colors: [pale, Color(red: 0.79, green: 0.80, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing)
 static let panel = LinearGradient(colors: [Color(red: 0.105, green: 0.10, blue: 0.20), Color(red: 0.045, green: 0.055, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct IceBackdrop: View {
 @AppStorage("premiumConsoleTheme") private var theme = "Ice"
 @AppStorage("premiumWallpaper") private var wallpaper = ""
 @State private var wallpaperImage:NSImage?
 var body: some View {
  GeometryReader { geometry in
   ZStack(alignment: .topTrailing) {
    LinearGradient(colors: [Color(red: 0.095, green: 0.075, blue: 0.19), IceTheme.navy, Color(red: 0.018, green: 0.035, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
    if theme != "Ice" {
     (theme == "Violet" ? Color.purple : Color.green).opacity(0.10)
    }
    if !wallpaper.isEmpty, let image = wallpaperImage {
     Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.14)
    }
    Circle().fill(IceTheme.purple.opacity(0.22)).frame(width: 650, height: 650).blur(radius: 100).offset(x: 210, y: -400)
    Canvas { context, size in
     var lines = Path()
     for x in stride(from: CGFloat(0), through: size.width, by: 64) { lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height)) }
     for y in stride(from: CGFloat(0), through: size.height, by: 64) { lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y)) }
     context.stroke(lines, with: .color(IceTheme.cyan.opacity(0.025)), lineWidth: 0.5)
    }
    Ellipse().stroke(IceTheme.blue.opacity(0.07), lineWidth: 1).frame(width: geometry.size.width * 0.8, height: 250).rotationEffect(.degrees(-25)).offset(x: 200, y: -80)
   }
  }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
  .task(id:wallpaper) {
   wallpaperImage=nil
   guard !wallpaper.isEmpty else{return}
   let image=await CoverImageCache.shared.image(wallpaper,maxPixelSize:2560)
   guard !Task.isCancelled else{return}
   wallpaperImage=image
  }
 }
}

struct StationMark: View {
 private static let logo = Bundle.main.url(forResource: "StationLogo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
 var body: some View {
  Group {
   if let logo = Self.logo { Image(nsImage: logo).resizable().scaledToFit() }
  }.frame(width: 44, height: 44).accessibilityLabel("Akito Station")
 }
}
