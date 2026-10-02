import Foundation
import Darwin
/// Content hashes are reused only while inode/device/size/mtime/ctime/mode agree.
/// Metadata is checked on every lookup; changed nested files invalidate independently.
public enum RuntimeFileHashes {
 private struct Stamp:Equatable {let device:Int32;let inode:UInt64;let size:Int64;let modified:Int;let modifiedNano:Int;let changed:Int;let changedNano:Int;let mode:UInt16}
 private static let lock=NSLock()
 private static var cache:[String:(Stamp,String)]=[:]
 private static func stamp(_ url:URL)throws->Stamp {
  var value=stat();guard lstat(url.path,&value)==0 else{throw AkitoStationError.message("Runtime file is missing or unavailable")}
  return Stamp(device:value.st_dev,inode:value.st_ino,size:value.st_size,modified:value.st_mtimespec.tv_sec,modifiedNano:value.st_mtimespec.tv_nsec,changed:value.st_ctimespec.tv_sec,changedNano:value.st_ctimespec.tv_nsec,mode:value.st_mode)
 }
 public static func hash(_ url:URL)throws->String {
  let file=url.resolvingSymlinksInPath(),key=file.path,before=try stamp(file)
  lock.lock();let entry=cache[key];lock.unlock()
  if let entry,entry.0==before{return entry.1}
  let value=try digest(file)
  guard try stamp(file)==before else{throw AkitoStationError.message("Runtime changed while being verified; retry after update finishes")}
  lock.lock();if cache.count>=4096{cache.removeAll(keepingCapacity:true)};cache[key]=(before,value);lock.unlock()
  return value
 }
 public static func invalidate(){lock.lock();cache.removeAll();lock.unlock()}
}
