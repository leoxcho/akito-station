import SwiftUI
import AkitoStationCore

struct ConsoleCollection: View {
 @EnvironmentObject var store: LibraryStore
 @State private var selected: Platform?
 @State private var search = ""
 var body: some View {
  VStack(alignment: .leading, spacing: 20) {
   collectionHeading("ハードウェア  /  THE HARDWARE", "Consoles", "Your systems. Their own graphics, controls and configuration.")
   TextField("Find a console", text: $search).textFieldStyle(.roundedBorder)
   ScrollView {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 20)], spacing: 20) {
     ForEach(Platform.allCases.filter { $0 != .unknown && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { platform in
      Button { selected = platform } label: {
       CollectionTile(title: platform.title, subtitle: "\(store.games.filter { $0.platform == platform }.count) games · \(store.engine(platform) ?? "External / unavailable")", action: "Emulator settings", icon: "slider.horizontal.3") {
        ConsoleDrawing(platform: platform).frame(height: 150)
       }
      }.buttonStyle(.plain)
     }
    }
   }
  }.padding(28)
  .sheet(item: $selected) { platform in
   VStack(alignment: .leading, spacing: 18) {
    HStack { Text(platform.title).font(.title.bold()); Spacer(); Button("Done") { selected = nil }.keyboardShortcut(.cancelAction) }
    ScrollView {
     if store.engine(platform) != nil || ExternalEmulator.name(platform) != nil {
      EmulatorSettingsPanel(system: platform).id(platform.id + (store.engine(platform) ?? ""))
      Divider().padding(.vertical)
      ProfileEditor(profile: Binding(get: { store.systemProfiles[platform.rawValue] ?? GameProfile() }, set: { store.saveSystem($0, platform) }), nativeGPU: GraphicsConfiguration.scalableEngines.contains(store.engine(platform) ?? ""), engine: store.engine(platform) ?? "")
     } else { EmulatorSettingsPanel(system: platform) }
    }
   }.padding(28).background(IceBackdrop()).frame(width: 880, height: 680)
  }
 }
}

func collectionHeading(_ eyebrow: String, _ title: String, _ subtitle: String) -> some View {
 VStack(alignment: .leading, spacing: 8) {
  Text(eyebrow).font(.caption2.bold()).tracking(3).foregroundStyle(IceTheme.gold)
  Text(title).font(.system(size: 38, weight: .light, design: .rounded)).foregroundStyle(IceTheme.chrome)
  Text(subtitle).font(.callout).foregroundStyle(.secondary)
 }
}

struct CollectionTile<Artwork: View>: View {
 let title: String
 let subtitle: String
 let action: String
 let icon: String
 @ViewBuilder var artwork: Artwork
 @State private var hovered = false
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   artwork.frame(maxWidth: .infinity).padding(.top, 16)
   Text(title).font(.headline).lineLimit(1)
   Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .top)
  }.padding(18)
   .background(IceTheme.panel, in: RoundedRectangle(cornerRadius: 20))
   .overlay(alignment: .bottom) {
    if hovered { Label(action, systemImage: icon).font(.callout.bold()).frame(maxWidth: .infinity).padding(18).background(IceTheme.panel).clipShape(RoundedRectangle(cornerRadius: 18)).allowsHitTesting(false) }
   }
   .overlay(RoundedRectangle(cornerRadius: 20).stroke(hovered ? accent.opacity(0.8) : accent.opacity(0.20)))
   .shadow(color: accent.opacity(hovered ? 0.18 : 0), radius: 18, y: 8)
   .offset(y: hovered ? -3 : 0).animation(.easeOut(duration: 0.18), value: hovered)
   .onHover { hovered = $0 }.contentShape(RoundedRectangle(cornerRadius: 20))
   .accessibilityElement(children: .combine).accessibilityHint(action)
 }
}

// Publication uses text labels in place of unverified illustrations.
struct ConsoleDrawing: View {
 let platform: Platform
 var body: some View { Text(platform.title).font(.headline).frame(maxWidth: .infinity, minHeight: 100) }
}

struct SaveBrowserEntry: Identifiable, Sendable {
 let url: URL
 let directory: Bool
 let bytes: Int
 let modified: Date?
 var id: String { url.path }
}

struct MemoryCardCollection: View {
 @EnvironmentObject var store: LibraryStore
 @State private var kind: StorageKind = .saves
 @State private var folder: URL?
 @State private var entries: [SaveBrowserEntry] = []
 @State private var error = ""
 @State private var search = ""
 @State private var loading = false
 @State private var selected: SaveBrowserEntry?
 var root: URL? { try? store.directory(kind) }
 var body: some View {
  VStack(alignment: .leading, spacing: 18) {
   collectionHeading("メモリー  /  PROGRESS, PRESERVED", "Memory cards", "Browse managed saves, native emulator storage and save states.")
   HStack {
    Picker("Storage", selection: $kind) { Text("Save data").tag(StorageKind.saves); Text("Save states").tag(StorageKind.states) }.pickerStyle(.segmented).frame(width: 260)
    Spacer(); Button("Refresh") { refresh() }; Button("Show in Finder") { if let url = folder ?? root { NSWorkspace.shared.open(url) } }
   }
   HStack {
    Button("All cards") { folder = nil; refresh() }.disabled(folder == nil)
    Button { if let folder, folder.deletingLastPathComponent() != root { self.folder = folder.deletingLastPathComponent() } else { folder = nil }; refresh() } label: { Image(systemName: "chevron.left") }.disabled(folder == nil)
    Text(folder?.lastPathComponent ?? kind.title).lineLimit(1).foregroundStyle(.secondary)
    Spacer(); TextField("Find save data", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
   }
   if !error.isEmpty { Text(error).foregroundStyle(.orange) }
   if loading { ProgressView() }
   ScrollView {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 20)], spacing: 20) {
     ForEach(entries.filter { search.isEmpty || title($0).localizedCaseInsensitiveContains(search) }.sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }) { entry in
      Button { if entry.directory { folder = entry.url; search = ""; refresh() } else { selected = entry } } label: {
       CollectionTile(title: title(entry), subtitle: entry.directory ? "Save folder · click to browse" : ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file), action: entry.directory ? "Browse save data" : "View save details", icon: entry.directory ? "folder" : "doc.text.magnifyingglass") {
        MemoryCardArtwork(label: entry.directory ? "SAVE COLLECTION" : entry.url.pathExtension.uppercased()).frame(height: 160)
       }
      }.buttonStyle(.plain)
     }
    }
    if entries.isEmpty && !loading && error.isEmpty { ContentUnavailableView("No save data here yet", systemImage: "externaldrive", description: Text("Save files appear here after games create them. Use Save states to browse snapshots.")) }
   }
   Text("\(entries.count) items · Files stay in their original locations. Card images are a visual browser, not a capacity indicator.").font(.caption).foregroundStyle(.secondary)
  }.padding(28).task { refresh() }.onChange(of: kind) { _, _ in folder = nil; refresh() }
  .sheet(item: $selected) { entry in
   VStack(alignment: .leading, spacing: 18) {
    HStack { Text(title(entry)).font(.title2.bold()); Spacer(); Button("Done") { selected = nil } }
    MemoryCardArtwork(label: entry.url.pathExtension.uppercased()).frame(height: 190)
    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
    if let date = entry.modified { LabeledContent("Modified", value: date.formatted()) }
    Text(entry.url.path).font(.caption).textSelection(.enabled)
    Text("Save files and memory-card images are shown as stored; individual slots inside disk images are not decoded.").foregroundStyle(.secondary)
    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
   }.padding(28).background(IceBackdrop()).frame(width: 580)
  }
 }
 func title(_ entry: SaveBrowserEntry) -> String {
  let name = entry.url.lastPathComponent
  if let game = store.games.first(where: { $0.id == name }) { return game.title }
  if name == "Systems" { return "Emulator save storage" }
  if name.count == 64 && name.allSatisfy({ $0.isHexDigit }) { return "Unlinked save · " + name.prefix(8) }
  return name
 }
 func refresh() {
  do {
   let url = try folder ?? store.directory(kind)
   loading = true; error = ""; entries = []
   Task {
    do {
     let result = try await Task.detached(priority: .userInitiated) {
      try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]).filter { $0.lastPathComponent != ".DS_Store" }.map { file in
       let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
       return SaveBrowserEntry(url: file, directory: values.isDirectory == true && values.isSymbolicLink != true, bytes: values.fileSize ?? 0, modified: values.contentModificationDate)
      }.sorted { a, b in a.directory != b.directory ? a.directory : a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending }
     }.value
     if url == (folder ?? root) { entries = result; loading = false }
    } catch { if url == (folder ?? root) { self.error = error.localizedDescription; loading = false } }
   }
  } catch { self.error = error.localizedDescription; entries = []; loading = false }
 }
}

struct MemoryCardArtwork: View {
 let label: String
 var body: some View { Text(label.isEmpty ? "Save data" : label).font(.headline).frame(width: 150, height: 100) }
}
