import Foundation
import Darwin
public struct ProcessResult:Sendable {public let exitCode:Int32;public let elapsed:Double}
private final class OperationCancellation:@unchecked Sendable {
 let lock=NSLock();var cancelled=false
 func cancel(){lock.lock();cancelled=true;lock.unlock()}
 var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
}
private enum OwnedOperationGroups {
 static let lock=NSLock()
 static var groups=Set<pid_t>()
 static let registration:Void = {atexit{OwnedOperationGroups.stopAll()}}()
 static func add(_ pid:pid_t){_=registration;lock.lock();groups.insert(pid);lock.unlock()}
 static func remove(_ pid:pid_t){lock.lock();groups.remove(pid);lock.unlock()}
 static func stopAll(){lock.lock();let active=groups;lock.unlock();for pid in active{kill(-pid,SIGKILL)}}
}
public enum ProcessRunner {
 /// Each owned operation starts in a new POSIX process group, assigned atomically at
 /// spawn. Negative-PID signals reach only that group, never the caller's group.
 public static func run(executable:URL,arguments:[String],log:URL,timeout:Double=180,environment:[String:String]?=nil,workingDirectory:URL?=nil)async throws->ProcessResult {
  let cancellation=OperationCancellation()
  return try await withTaskCancellationHandler(operation:{
   try await Task.detached(priority:.userInitiated){
    try execute(executable:executable,arguments:arguments,log:log,timeout:timeout,environment:environment,cancellation:cancellation,workingDirectory:workingDirectory)
   }.value
  },onCancel:{cancellation.cancel()})
 }
 private static func execute(executable:URL,arguments:[String],log:URL,timeout:Double,environment:[String:String]?,cancellation:OperationCancellation,workingDirectory:URL?)throws->ProcessResult {
  let fd=open(log.path,O_WRONLY|O_CREAT|O_APPEND,0o600)
  guard fd>=0 else{throw AkitoStationError.message("Cannot create runtime log")};defer{close(fd)}
  var actions:posix_spawn_file_actions_t?;var attributes:posix_spawnattr_t?
  posix_spawn_file_actions_init(&actions);posix_spawnattr_init(&attributes)
  defer{posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attributes)}
  if let folder=workingDirectory{guard posix_spawn_file_actions_addchdir_np(&actions,folder.path)==0 else{throw AkitoStationError.message("Cannot set runtime working directory")}}
  posix_spawn_file_actions_adddup2(&actions,fd,STDOUT_FILENO);posix_spawn_file_actions_adddup2(&actions,fd,STDERR_FILENO)
  posix_spawnattr_setflags(&attributes,Int16(POSIX_SPAWN_SETPGROUP));posix_spawnattr_setpgroup(&attributes,0)
  let argv=([executable.path]+arguments).map{strdup($0)}+[nil]
  let env=(environment ?? ProcessInfo.processInfo.environment).map{strdup($0.key+"="+$0.value)}+[nil]
  defer{argv.forEach{free($0)};env.forEach{free($0)}}
  var pid:pid_t=0
  let start=Date()
  let error=argv.withUnsafeBufferPointer{a in env.withUnsafeBufferPointer{e in posix_spawn(&pid,executable.path,&actions,&attributes,UnsafeMutablePointer(mutating:a.baseAddress!),UnsafeMutablePointer(mutating:e.baseAddress!))}}
  guard error==0 else{throw AkitoStationError.message("Could not start runtime operation: \(String(cString:strerror(error)))")}
  // Also clean remaining descendants after success/failure of the group leader.
  OwnedOperationGroups.add(pid)
  defer{kill(-pid,SIGKILL);OwnedOperationGroups.remove(pid)}
  var status:Int32=0
  while true {
   if cancellation.isCancelled || Date().timeIntervalSince(start)>timeout {
    kill(-pid,SIGTERM)
    let deadline=Date().addingTimeInterval(0.5)
    while Date()<deadline{Thread.sleep(forTimeInterval:0.02)}
    kill(-pid,SIGKILL);while waitpid(pid,&status,0)<0 && errno==EINTR{}
    if cancellation.isCancelled{throw CancellationError()}
    throw AkitoStationError.message("Runtime process exceeded its time limit; evidence retained in \(log.lastPathComponent)")
   }
   let waited=waitpid(pid,&status,WNOHANG)
   if waited==pid{break}
   if waited<0 && errno != EINTR{throw AkitoStationError.message("Cannot observe runtime operation")}
   Thread.sleep(forTimeInterval:0.025)
  }
  let code=(status & 0x7f)==0 ? (status >> 8)&0xff:128+(status & 0x7f)
  return ProcessResult(exitCode:code,elapsed:Date().timeIntervalSince(start))
 }
 public static func testRuntime(executable:URL,arguments:[String],workingDirectory:URL?=nil,environment:[String:String]?=nil,log:URL)async throws {
  guard FileManager.default.isExecutableFile(atPath:executable.path) else{throw AkitoStationError.message("Executable not found. Edit the emulator and relink its installation.")}
  // posix_spawn chdir action is confined to this owned child.
  // Runtime tests that require a working directory are launched via the system shell
  // with positional argv; no user text is interpolated as shell code.
  let target=workingDirectory == nil ? executable:URL(fileURLWithPath:"/bin/sh")
  let args=workingDirectory.map{["-c","cd -- \"$1\" && shift && exec \"$@\"","akito-test",$0.path,executable.path]+arguments} ?? arguments
  do{let result=try await run(executable:target,arguments:args,log:log,timeout:2,environment:environment);guard result.exitCode==0 else{throw AkitoStationError.message("Emulator exited during startup. See its test log.")}}
  catch let error as AkitoStationError {if !error.localizedDescription.contains("exceeded its time limit"){throw error}}
 }
}
