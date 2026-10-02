import Foundation

/// Records the exact selected file and argv for user-installed Switch runtime handoffs.
public struct SwitchLaunchRecord:Codable {
 public let runtime:String
 public let executable:String
 public let game:String
 public let arguments:[String]
 public init(runtime:String,executable:String,game:String,arguments:[String]){self.runtime=runtime;self.executable=executable;self.game=game;self.arguments=arguments}
}
