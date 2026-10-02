import Foundation
public enum LibraryPresentation {
 public static func visible(_ games:[Game],query:String,category:String,order:String)->[Game] {
  games.filter{g in (query.isEmpty || g.title.localizedCaseInsensitiveContains(query)) && (category=="all" || (category=="favorites" && g.favorite) || (category=="recent" && g.lastPlayed != nil) || category==g.platform.rawValue)}.sorted{a,b in switch order {case "Recently played":return (a.lastPlayed ?? .distantPast)>(b.lastPlayed ?? .distantPast);case "Play time":return a.playSeconds>b.playSeconds;default:return a.title.localizedStandardCompare(b.title) == .orderedAscending}}
 }
}

/// Sorted orders are rebuilt when library values change, then reused across queries.
public actor LibraryPresentationIndex {
 private var revision:Int = -1
 private var games:[Game]=[]
 private var orders:[String:[Int]]=[:]
 public init(){}
 public func visible(_ source:[Game],revision:Int,query:String,category:String,order:String)throws->[Game] {
  try Task.checkCancellation()
  if self.revision != revision {
   games=source;self.revision=revision
   let indices=Array(source.indices)
   orders["Title"]=indices.sorted{source[$0].title.localizedStandardCompare(source[$1].title) == .orderedAscending}
   orders["Recently played"]=indices.sorted{(source[$0].lastPlayed ?? .distantPast)>(source[$1].lastPlayed ?? .distantPast)}
   orders["Play time"]=indices.sorted{source[$0].playSeconds>source[$1].playSeconds}
  }
  var result:[Game]=[]
  for (position,index) in (orders[order] ?? orders["Title"] ?? []).enumerated() {
   if position%1024==0{try Task.checkCancellation()}
   let g=games[index]
   if (query.isEmpty || g.title.localizedCaseInsensitiveContains(query)) && (category=="all" || (category=="favorites" && g.favorite) || (category=="recent" && g.lastPlayed != nil) || category==g.platform.rawValue){result.append(g)}
  }
  return result
 }
}
