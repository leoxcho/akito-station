import SwiftUI
import AkitoStationCore
import UniformTypeIdentifiers

struct ArtworkEditor:View {
 @EnvironmentObject var store:LibraryStore
 @Environment(\.dismiss) var dismiss
 let game:Game
 @State private var query=""
 @State private var results:[ArtworkCache.Result]=[]
 @State private var busy=false
 @State private var allSystems=false
 @State private var message="Search the online cover collection or choose an image from your Mac."
 var body:some View{
 VStack(alignment:.leading,spacing:16){
 HStack{Text("Box art").font(.title2.bold());Spacer();Button("Done"){dismiss()}}
 Text(game.title).foregroundStyle(.secondary)
 HStack{TextField("Game title",text:$query).onSubmit{search()};Button("Search online"){search()}.disabled(busy || query.trimmingCharacters(in:.whitespaces).isEmpty);Button("Choose image…"){importImage()}.disabled(busy)}
 Toggle("All systems (includes covers from other editions)",isOn:$allSystems).disabled(busy)
 Text(message).font(.caption).foregroundStyle(.secondary)
 if busy{ProgressView()}
 ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:18){ForEach(results){result in
 Button{select(result)}label:{VStack{AsyncImage(url:result.url){image in image.resizable().scaledToFit()}placeholder:{ProgressView()}.frame(width:140,height:170).clipped();Text(result.title+" · "+result.platform.title).font(.caption).lineLimit(3).frame(width:140,height:48)}}.buttonStyle(.plain).disabled(busy)
 }}}
 Text("Online front covers: Libretro Thumbnails and TheGamesDB. Imported images are copied into Akito Station’s artwork storage; your original file stays untouched.").font(.caption2).foregroundStyle(.secondary)
 }.padding(24).frame(width:700,height:550).onAppear{query=game.title;allSystems=game.platform == .unknown}
 }
 func search(){guard !busy else{return};busy=true;message="Searching…";Task{defer{busy=false};do{results=try await ArtworkCache.shared.search(query,platform:game.platform,allSystems:allSystems);message=results.isEmpty ? "No covers found. Try a shorter title or choose a local image.":"Choose a cover to use it (\(results.count) results)."}catch{message=error.localizedDescription}}}
 func select(_ result:ArtworkCache.Result){busy=true;Task{defer{busy=false};do{let data=try await ArtworkCache.shared.download(result);try await store.installArtwork(data,for:game,source:result.url.absoluteString);dismiss()}catch{message=error.localizedDescription}}}
 func importImage(){let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.tiff,.heic,.webP];panel.canChooseDirectories=false;panel.allowsMultipleSelection=false;panel.prompt="Use cover";guard panel.runModal() == .OK,let url=panel.url else{return};busy=true
  Task{defer{busy=false};do{let data=try await Task.detached{let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=8*1024*1024 else{throw AkitoStationError.message("Choose an image smaller than 8 MB")};return try Data(contentsOf:url)}.value;try await store.installArtwork(data,for:game,source:url.lastPathComponent);dismiss()}catch{message=error.localizedDescription}}
 }
}
