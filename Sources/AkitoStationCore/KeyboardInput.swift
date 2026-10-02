import Foundation

/// Retains a tap until at least one emulated frame has sampled it.
public struct KeyboardInput {
 public private(set) var held=Set<UInt32>()
 private var pending=Set<UInt32>()
 public init(){}
 public var active:Set<UInt32>{held.union(pending)}
 public mutating func press(_ button:UInt32){held.insert(button);pending.insert(button)}
 public mutating func release(_ button:UInt32){held.remove(button)}
 public mutating func didRunFrame(){pending.removeAll()}
 public mutating func clear(){held.removeAll();pending.removeAll()}
}
