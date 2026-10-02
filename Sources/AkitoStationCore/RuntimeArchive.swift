import Foundation
import Darwin
import RuntimeSupport
public struct RuntimeArchiveLimits:Sendable {
 public var downloadBytes:Int64=2*1024*1024*1024
 public var extractedBytes:UInt64=8*1024*1024*1024
 public var fileCount:Int=100_000
 public var compressionRatio:UInt64=200
 public var freeSpaceReserveBytes:UInt64=16*1024*1024
 public init(){}
}
public enum RuntimeArchive {
 /// ZIP central-directory preflight before system extraction. ZIP64, encrypted,
 /// multipart and symlink entries are deliberately unsupported in automatic flow.
 private struct Entry {let name:String;let offset:Int;let compressed:Int;let expanded:UInt64;let method:Int;let crc:UInt64;let mode:UInt64}
 public static func inspectZIP(_ archive:URL,limits:RuntimeArchiveLimits=RuntimeArchiveLimits())throws {_ = try entries(archive,limits:limits)}
 private static func entries(_ archive:URL,limits:RuntimeArchiveLimits)throws->[Entry] {
  let size=(try archive.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
  guard size>0,Int64(size)<=limits.downloadBytes else{throw AkitoStationError.message("Archive exceeds download limits")}
  let data=try Data(contentsOf:archive,options:.mappedIfSafe)
  func uint(_ at:Int,_ count:Int)throws->UInt64 {
   guard at>=0,at+count<=data.count else{throw AkitoStationError.message("Truncated ZIP archive")}
   return (0..<count).reduce(UInt64(0)){$0 | UInt64(data[at+$1]) << ($1*8)}
  }
  guard data.count>=22 else{throw AkitoStationError.message("Malformed ZIP archive")}
  var end:Int?
  for offset in stride(from:data.count-22,through:max(0,data.count-65557),by:-1){if try uint(offset,4)==0x06054b50,offset+22+Int(try uint(offset+20,2))==data.count{end=offset;break}}
  guard let end=end,try uint(end+4,2)==0,try uint(end+6,2)==0 else{throw AkitoStationError.message("Unsupported multipart ZIP")}
  let count=Int(try uint(end+10,2)),centralSize=Int(try uint(end+12,4)),central=Int(try uint(end+16,4))
  guard count>0,count<65535,count<=limits.fileCount,central>=0,central+centralSize==end,try uint(end+8,2)==UInt64(count) else{throw AkitoStationError.message("ZIP directory or file count exceeds policy")}
  var offset=central,total:UInt64=0,seen=Set<String>(),result:[Entry]=[],ranges:[Range<Int>]=[],physicalPaths=Set<String>()
  for _ in 0..<count {
   guard try uint(offset,4)==0x02014b50 else{throw AkitoStationError.message("Malformed ZIP directory")}
   let flags=try uint(offset+8,2),method=try uint(offset+10,2),compressed=try uint(offset+20,4),expanded=try uint(offset+24,4)
   let nameCount=Int(try uint(offset+28,2)),extra=Int(try uint(offset+30,2)),comment=Int(try uint(offset+32,2)),mode=try uint(offset+38,4)>>16,local=Int(try uint(offset+42,4))
   guard flags & 1==0,[UInt64(0),8].contains(method),expanded<0xffffffff,compressed<0xffffffff,[UInt64(0),0x8000,0x4000].contains(mode & 0xf000),try uint(offset+34,2)==0 else{throw AkitoStationError.message("Encrypted, symlink or unsupported ZIP entry")}
   guard offset+46+nameCount+extra+comment<=end else{throw AkitoStationError.message("Truncated ZIP directory")}
   let nameData=data.subdata(in:offset+46..<offset+46+nameCount)
   guard let name=String(data:nameData,encoding:.utf8),!name.isEmpty,!name.hasPrefix("/"),!name.contains("\\"),!name.contains("\0"),!name.contains(":"),!name.split(separator:"/").contains(where:{$0==".." || $0=="."}),seen.insert(name.lowercased()).inserted else{throw AkitoStationError.message("Unsafe or duplicate ZIP path")}
   guard try uint(local,4)==0x04034b50,try uint(local+6,2)==flags,try uint(local+8,2)==method else{throw AkitoStationError.message("ZIP local entry differs from directory")}
   let localName=Int(try uint(local+26,2)),localExtra=Int(try uint(local+28,2))
   guard localName==nameCount,local+30+localName+localExtra+Int(compressed)<=central,data.subdata(in:local+30..<local+30+localName)==nameData else{throw AkitoStationError.message("ZIP entry identity or bounds mismatch")}
   let payload=local+30+localName+localExtra,range=local..<payload+Int(compressed),crc=try uint(offset+16,4)
   ranges.append(range)
   let parts=name.split(separator:"/").map(String.init);var prefix=""
   for part in parts{prefix += "/"+part;physicalPaths.insert(prefix.precomposedStringWithCanonicalMapping.lowercased())}
   guard physicalPaths.count<=limits.fileCount else{throw AkitoStationError.message("ZIP includes too many explicit or implicit paths")}
   if flags & 8==0 {guard try uint(local+14,4)==crc,try uint(local+18,4)==compressed,try uint(local+22,4)==expanded else{throw AkitoStationError.message("ZIP local size or checksum mismatch")}}
   if name.hasSuffix("/"){guard expanded==0 else{throw AkitoStationError.message("ZIP directory contains data")}}
   result.append(Entry(name:name,offset:payload,compressed:Int(compressed),expanded:expanded,method:Int(method),crc:crc,mode:mode))
   total+=expanded
   guard total<=limits.extractedBytes,expanded<=max(UInt64(1024*1024),compressed*limits.compressionRatio) else{throw AkitoStationError.message("ZIP expanded size or compression ratio exceeds policy")}
   offset+=46+nameCount+extra+comment
  }
  guard offset==end else{throw AkitoStationError.message("Unexpected ZIP directory data")}
  let sorted=ranges.sorted{$0.lowerBound<$1.lowerBound}
  for i in sorted.indices.dropFirst(){guard !sorted[i-1].overlaps(sorted[i]) else{throw AkitoStationError.message("Overlapping ZIP entries")}}
  return result
 }
 public static func applications(in root:URL)throws->[URL] {
  guard let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil) else{throw AkitoStationError.message("Cannot inspect extracted archive")}
  var apps:[URL]=[]
  while let file=files.nextObject() as? URL {if file.pathExtension=="app"{apps.append(file);files.skipDescendants()}}
  return apps
 }
 public static func extractZIP(_ archive:URL,to destination:URL,log:URL,limits:RuntimeArchiveLimits=RuntimeArchiveLimits())async throws {
  let worker=Task.detached(priority:.userInitiated){try extractBounded(archive,to:destination,limits:limits)}
  try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
 }
 private static func extractBounded(_ archive:URL,to destination:URL,limits:RuntimeArchiveLimits)throws {
  let list=try entries(archive,limits:limits),fm=FileManager.default
  guard !fm.fileExists(atPath:destination.path) else{throw AkitoStationError.message("Extraction requires fresh staging")}
  let parent=destination.deletingLastPathComponent()
  let free=(try fm.attributesOfFileSystem(forPath:parent.path)[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
  let expected=list.reduce(UInt64(0)){$0+$1.expanded}
  let required=expected.addingReportingOverflow(limits.freeSpaceReserveBytes)
  guard !required.overflow,free>=required.partialValue else{throw AkitoStationError.message("Insufficient disk space for archive staging")}
  try fm.createDirectory(at:destination,withIntermediateDirectories:false)
  do {
   let bytes=try Data(contentsOf:archive,options:.mappedIfSafe)
   for item in list {
    try Task.checkCancellation()
    let file=destination.appendingPathComponent(item.name)
    if item.name.hasSuffix("/"){try fm.createDirectory(at:file,withIntermediateDirectories:true);continue}
    try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
    let fd=open(file.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
    guard fd>=0 else{throw AkitoStationError.message("Cannot create archive member; check available disk space")}
    let status=bytes.withUnsafeBytes {raw in akito_zip_extract(raw.bindMemory(to:UInt8.self).baseAddress!+item.offset,item.compressed,Int32(item.method),fd,item.expanded,UInt(item.crc))}
    close(fd)
    try Task.checkCancellation()
    guard status==0 else{throw AkitoStationError.message("Archive checksum, expanded size, compressed stream or disk write failed")}
    try fm.setAttributes([.posixPermissions:item.mode & 0o111 != 0 ? 0o755:0o644],ofItemAtPath:file.path)
   }
  }catch{try? fm.removeItem(at:destination);throw error}
 }
}
