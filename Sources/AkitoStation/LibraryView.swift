import SwiftUI
import AkitoStationCore
import ImageIO

let accent=IceTheme.red
struct LibraryView:View {
 @EnvironmentObject var store:LibraryStore
 @State private var settings=false
 @State private var section="Games"
 @FocusState private var searchFocused:Bool
 var body:some View {
 NavigationSplitView {
 VStack(alignment:.leading,spacing:24){HStack(spacing:12){StationMark();VStack(alignment:.leading){Text("Akito Station").font(.system(size:20,weight:.black,design:.rounded));Text("アキト・ステーション").font(.system(size:8,weight:.medium)).tracking(1).foregroundStyle(.secondary)}}.padding(.top,25)
 VStack(alignment:.leading,spacing:7){ForEach(["Games", "Consoles", "Memory cards"],id: \.self){item in Button{section=item}label:{Label(item,systemImage:item == "Games" ? "square.grid.2x2.fill" : item == "Consoles" ? "gameconsole.fill" : "externaldrive.fill").frame(maxWidth:.infinity,alignment:.leading).padding(10).background(section == item ? accent.opacity(0.2):.clear,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)};Divider().padding(.vertical,8);nav("All games","square.grid.2x2.fill","all");nav("Favorites","heart.fill","favorites");nav("Recently played","clock.fill","recent")}
 Text("SYSTEMS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(2)
 ScrollView{VStack(alignment:.leading,spacing:5){ForEach(Platform.allCases.filter{p in store.games.contains{$0.platform==p}}){p in nav(p.title,"circle.grid.2x2",p.rawValue)}}}
 Spacer();Label(store.controllerName,systemImage:"gamecontroller").font(.caption).foregroundStyle(.secondary)
 Button{settings=true}label:{Label("Settings",systemImage:"gearshape").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).padding(.bottom,18)
 }.padding(.horizontal,20).frame(minWidth:200).background(IceTheme.navy)
 } detail: {
 Group { if section == "Consoles" { ConsoleCollection() } else if section == "Memory cards" { MemoryCardCollection() } else { VStack(alignment:.leading,spacing:0){header
 if store.games.isEmpty{ContentUnavailableView{Label("Your next adventure starts here",systemImage:"gamecontroller")}description:{Text("Choose your ROM libraries in Settings. Your original games and saves stay untouched.")}actions:{Button("Open Settings"){settings=true}.buttonStyle(.borderedProminent)}.frame(maxWidth:.infinity,maxHeight:.infinity)}else{
 ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:170,maximum:225),spacing:22)],spacing:24){ForEach(store.visible){game in GameCard(game:game,selected:store.selected?.id==game.id).task(id:game.id){await store.loadArtwork(game)}.onTapGesture{store.selected=game}.onTapGesture(count:2){store.play(game)}.contextMenu{Button("Play"){store.play(game)};Button(game.favorite ? "Remove favorite":"Favorite"){store.favorite(game)}
}}}.padding(28)}
 }
 if !store.artworkProgress.isEmpty{HStack{if store.scrapingArtwork{ProgressView().controlSize(.small)};Text(store.artworkProgress).lineLimit(2);Spacer();if store.scrapingArtwork{Button("Cancel"){store.cancelArtworkScrape()}}else{Button("Dismiss"){store.artworkProgress=""}}}.font(.caption).padding(.horizontal,28).padding(.vertical,8)}
 HStack{Circle().fill(store.busy ? IceTheme.gold:IceTheme.cyan).frame(width:6,height:6);Text(store.activity);Spacer();Text("\(store.visible.count) games")}.font(.caption).foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,12).background(.black.opacity(0.15))
 }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading) } }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(IceBackdrop())
 }.navigationSplitViewStyle(.balanced).tint(IceTheme.cyan).preferredColorScheme(.dark).frame(minWidth:980,minHeight:660)
 .sheet(item:$store.runtimeConsole){platform in OptionalRuntimeSheet(platform:platform).environmentObject(store)}
 .alert("No emulator installed",isPresented:Binding(get:{store.missingRuntime != nil},set:{if !$0{store.missingRuntime=nil}})){
  Button("Install Emulator"){store.runtimeConsole=store.missingRuntime;store.missingRuntime=nil}
  Button("Choose Existing Installation"){store.runtimeConsole=store.missingRuntime;store.missingRuntime=nil}
  Button("Cancel",role:.cancel){store.missingRuntime=nil}
 }message:{Text("No emulator is installed for \(store.missingRuntime?.title ?? "this console").")}
 .sheet(isPresented:$settings){AkitoStationSettings().environmentObject(store).frame(width:900,height:650)}
 .sheet(item:$store.selected){game in GameDetail(game:game).environmentObject(store).frame(width:760,height:570)}
 .alert("Akito Station",isPresented:Binding(get:{store.message != nil},set:{if !$0{store.message=nil}})){Button("OK"){store.message=nil}}message:{Text(store.message ?? "")}
 .toolbar{ToolbarItem{Button("Scrape all box art",systemImage:"photo.badge.arrow.down"){store.scrapeAllArtwork()}.help("Find missing covers across the entire library using Libretro Thumbnails. Existing covers are preserved.").disabled(store.scrapingArtwork || store.games.isEmpty || store.busy)};ToolbarItem{Button{store.scan()}label:{Image(systemName:"arrow.clockwise")}.help("Refresh library").disabled(store.busy)}}
 .onOpenURL{url in if url.scheme=="akito",let game=store.games.first(where:{$0.id==url.host}){store.play(game)}}
 }
 var header:some View{VStack(alignment:.leading,spacing:18){HStack{VStack(alignment:.leading,spacing:5){Text("コレクション  /  THE COLLECTION").font(.caption2.weight(.bold)).tracking(3).foregroundStyle(IceTheme.gold);Text(store.filter=="favorites" ? "Your favorites":store.filter=="recent" ? "Jump back in":"Your library").font(.system(size:38,weight:.light,design:.rounded)).foregroundStyle(IceTheme.chrome)};Spacer();Picker("Sort",selection:$store.sort){Text("Title").tag("Title");Text("Recently played").tag("Recently played");Text("Play time").tag("Play time")}.frame(width:185)
 PROMembershipControl().padding(.leading,12)
 };HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Search your collection",text:$store.search).textFieldStyle(.plain).focused($searchFocused);if store.busy{ProgressView().controlSize(.small)}}.padding(12).background(IceTheme.panel,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(searchFocused ? IceTheme.cyan : IceTheme.pale.opacity(0.14),lineWidth:searchFocused ? 2:1))}.padding(28).padding(.bottom,-4)}
 func nav(_ title:String,_ icon:String,_ value:String)->some View{Button{section="Games";store.filter=value}label:{HStack{Image(systemName:icon).frame(width:20);Text(title).lineLimit(1);Spacer()}.font(.system(size:13,weight:.medium)).padding(10).background(section=="Games" && store.filter==value ? accent.opacity(0.18):.clear,in:RoundedRectangle(cornerRadius:8)).foregroundStyle(section=="Games" && store.filter==value ? IceTheme.pale:.secondary)}.buttonStyle(.plain)}
}
struct GameCard: View {
 let game: Game
 var selected = false
 @State private var cover: NSImage?
 var body: some View {
  VStack(alignment: .leading) {
   if let cover { Image(nsImage: cover).resizable().scaledToFit().frame(height: 200) }
   Text(game.title).font(.headline).lineLimit(2)
   Text(game.platform.title).font(.caption)
  }.padding().frame(maxWidth: .infinity, minHeight: 235)
   .background(Color(nsColor: .controlBackgroundColor))
   .border(selected ? Color.accentColor : Color.clear)
   .task(id: game.artwork) {
    cover = nil
    if let path = game.artwork { cover = await CoverImageCache.shared.image(path) }
   }
 }
}
struct GameDetail:View {
 @EnvironmentObject var store:LibraryStore;@Environment(\.dismiss) var dismiss;let game:Game;@State var profile=GameProfile();@State var advanced=false;@State var artworkEditor=false
 var currentGame:Game{store.games.first(where:{$0.id==game.id}) ?? game}
 var body:some View{VStack(alignment:.leading,spacing:22){HStack{Text(game.platform.title.uppercased()).font(.caption.weight(.bold)).tracking(2).foregroundStyle(accent);Spacer();Button("Done"){dismiss()}};HStack(alignment:.top,spacing:28){VStack{GameCard(game:currentGame);Button("Change box art…"){artworkEditor=true}}.frame(width:185);VStack(alignment:.leading,spacing:18){Text(game.title).font(.largeTitle.bold());Label(store.health(game),systemImage:store.engine(game.platform)==nil ? "exclamationmark.circle":"checkmark.shield").foregroundStyle(.secondary);Text("\(Int(game.playSeconds/60)) minutes played · \(game.status)").font(.caption);HStack{Button{store.play(game);dismiss()}label:{Label("Play",systemImage:"play.fill").frame(width:110)}.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction);Button{store.favorite(game)}label:{Image(systemName:"heart")}};
ScrollView{GameEmulatorPicker(platform:game.platform,profile:$profile);ProfileEditor(profile:$profile,nativeGPU:GraphicsConfiguration.scalableEngines.contains(store.engine(game.platform) ?? ""),engine:store.engine(game.platform) ?? "")}.frame(maxHeight:220);Button("Save game profile"){store.attempt{try store.saveProfile(profile,game:game)}};Button("Roll back profile"){store.rollbackProfile(game)}}};if advanced{ScrollView{Text(store.assistantLog).font(.system(.caption,design:.monospaced)).textSelection(.enabled)}};Spacer()}.padding(28).background(IceBackdrop()).sheet(isPresented:$artworkEditor){ArtworkEditor(game:currentGame).environmentObject(store)}.onAppear{store.attempt{profile=try store.profile(game)}}}
}

/// Image I/O runs on a serial worker, never during SwiftUI layout or scrolling.
/// A bounded decoded-image cache keeps returning rows inexpensive.
@MainActor final class CoverImageCache {
 static let shared=CoverImageCache()
 private let cache=NSCache<NSString,NSImage>()
 private let worker=DispatchQueue(label:"app.akitostation.thumbnails",qos:.userInitiated)
 init(){cache.totalCostLimit=96*1024*1024}
 func image(_ path:String,maxPixelSize:Int=512,cacheRevision:String="")async->NSImage? {
  let key="\(maxPixelSize):\(path):\(cacheRevision)" as NSString
  if let image=cache.object(forKey:key){return image}
  guard !Task.isCancelled else{return nil}
  let cg:CGImage?=await withCheckedContinuation { continuation in
   worker.async {
    let thumbnail:CGImage?=autoreleasepool {
     guard let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else{return nil}
     return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxPixelSize,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
    }
    continuation.resume(returning:thumbnail)
   }
  }
  guard let cg else{return nil}
  let image=NSImage(cgImage:cg,size:.zero)
  cache.setObject(image,forKey:key,cost:cg.bytesPerRow*cg.height)
  return image
 }
}
