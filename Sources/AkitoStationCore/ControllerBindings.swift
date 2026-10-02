import Foundation

public struct ControllerBindings:Codable,Equatable {
 public var keyboard:[String:UInt16] = ["B":6,"Y":0,"Select":48,"Start":36,"Up":126,"Down":125,"Left":123,"Right":124,"A":7,"X":1,"L":12,"R":13,"L2":18,"R2":19]
 public var gamepad:[String:String] = ["B":"A","Y":"X","Select":"Options","Start":"Menu","Up":"Up","Down":"Down","Left":"Left","Right":"Right","A":"B","X":"Y","L":"L1","R":"R1","L2":"L2","R2":"R2","L3":"L3","R3":"R3"]
 public var wiiMode:String? = nil
 public var deadZone:Float=0.2
 public var gameCubeDevice="Quartz/0/Keyboard & Mouse"
 public var gameCube:[String:String] = ["Buttons/A":"`X`","Buttons/B":"`Z`","Buttons/X":"`C`","Buttons/Y":"`S`","Buttons/Z":"`D`","Buttons/Start":"`Return`","Main Stick/Up":"`Up`","Main Stick/Down":"`Down`","Main Stick/Left":"`Left`","Main Stick/Right":"`Right`","Triggers/L":"`Q`","Triggers/R":"`W`","D-Pad/Up":"`T`","D-Pad/Down":"`G`","D-Pad/Left":"`F`","D-Pad/Right":"`H`","C-Stick/Up":"`I`","C-Stick/Down":"`K`","C-Stick/Left":"`J`","C-Stick/Right":"`L`"]
 public init(){}
 public static let actions=["B","Y","Select","Start","Up","Down","Left","Right","A","X","L","R","L2","R2","L3","R3"]
 public static let padInputs=["None","A","B","X","Y","Options","Menu","Up","Down","Left","Right","L1","R1","L2","R2","L3","R3"]
 public static let keys:[(String,UInt16)]=[("Unbound",65535),("A",0),("S",1),("D",2),("F",3),("H",4),("G",5),("Z",6),("X",7),("C",8),("V",9),("B",11),("Q",12),("W",13),("E",14),("R",15),("Y",16),("T",17),("1",18),("2",19),("3",20),("4",21),("6",22),("5",23),("9",25),("7",26),("8",28),("0",29),("O",31),("U",32),("I",34),("P",35),("Return",36),("L",37),("J",38),("K",40),("N",45),("M",46),("Tab",48),("Space",49),("Backspace",51),("Escape",53),("Left",123),("Right",124),("Down",125),("Up",126)]
 public func validate()throws {
  guard wiiMode == nil || ["Nunchuk","Classic","Sideways"].contains(wiiMode!) else{throw AkitoStationError.message("Invalid Wii controller mode")}
  guard (0...0.9).contains(deadZone),gamepad.values.allSatisfy({Self.padInputs.contains($0)}),keyboard.values.allSatisfy({v in Self.keys.contains{$0.1==v}}) else{throw AkitoStationError.message("Invalid controller mapping")}
  guard gameCube.keys.allSatisfy({ControllerBindings().gameCube[$0] != nil}),!gameCubeDevice.contains(where:{$0.isNewline}),gameCube.values.allSatisfy({!$0.contains(where:{$0.isNewline})}) else{throw AkitoStationError.message("Controller expressions must be one line")}
 }
 public func dolphinPadINI()->String {"[GCPad1]\nDevice = "+gameCubeDevice+"\n"+gameCube.keys.sorted().map{$0+" = "+gameCube[$0]!}.joined(separator:"\n")+"\n"}
}

extension ControllerBindings {
 public func dolphinGamepadINI()->String {
 var map=["Buttons/A":"Button S","Buttons/B":"Button E","Buttons/X":"Button W","Buttons/Y":"Button N","Buttons/Z":"Shoulder R","Buttons/Start":"Start","Triggers/L":"Trigger L","Triggers/R":"Trigger R","Triggers/L-Analog":"Trigger L","Triggers/R-Analog":"Trigger R"]
 for (group,stick) in [("Main Stick","Left"),("C-Stick","Right")]{for (direction,axis) in [("Up","Y+"),("Down","Y-"),("Left","X-"),("Right","X+")]{map[group+"/"+direction]=stick+" "+axis}}
 for (direction,input) in [("Up","Pad N"),("Down","Pad S"),("Left","Pad W"),("Right","Pad E")]{map["D-Pad/"+direction]=input}
 return "[GCPad1]\nDevice = SDL/0/Gamepad\n"+map.keys.sorted().map{$0+" = `"+map[$0]!+"`"}.joined(separator:"\n")+"\nMain Stick/Dead Zone = \(deadZone*100)\nC-Stick/Dead Zone = \(deadZone*100)\n"
 }
 public func dolphinWiiINI(mode:String)->String {
 var map=["Buttons/A":"Button S","Buttons/B":"Trigger R","Buttons/1":"Button W","Buttons/2":"Button E","Buttons/+":"Start","Buttons/-":"Back","Buttons/Home":"Guide","Nunchuk/Buttons/C":"Shoulder L","Nunchuk/Buttons/Z":"Trigger L","Classic/Buttons/A":"Button E","Classic/Buttons/B":"Button S","Classic/Buttons/X":"Button N","Classic/Buttons/Y":"Button W","Classic/Buttons/ZL":"Shoulder L","Classic/Buttons/ZR":"Shoulder R","Classic/Buttons/+":"Start","Classic/Buttons/-":"Back","Classic/Buttons/Home":"Guide","Classic/Triggers/L":"Trigger L","Classic/Triggers/R":"Trigger R","Classic/Triggers/L-Analog":"Trigger L","Classic/Triggers/R-Analog":"Trigger R","Shake/X":"Thumb R","Shake/Y":"Thumb R","Shake/Z":"Thumb R"]
 for (group,stick) in [("Nunchuk/Stick","Left"),("Classic/Left Stick","Left"),("Classic/Right Stick","Right"),("IR","Right")]{for (direction,axis) in [("Up","Y+"),("Down","Y-"),("Left","X-"),("Right","X+")]{map[group+"/"+direction]=stick+" "+axis}}
 for group in ["D-Pad","Classic/D-Pad"]{for (direction,input) in [("Up","Pad N"),("Down","Pad S"),("Left","Pad W"),("Right","Pad E")]{map[group+"/"+direction]=input}}
 return "[Wiimote1]\nSource = 1\nDevice = SDL/0/Gamepad\nExtension = \(mode == "Sideways" ? "None":mode)\nOptions/Sideways Wiimote = \(mode == "Sideways" ? "True":"False")\n"+map.keys.sorted().map{$0+" = `"+map[$0]!+"`"}.joined(separator:"\n")+"\n"
 }
}
