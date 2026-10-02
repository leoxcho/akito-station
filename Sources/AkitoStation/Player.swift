import SwiftUI
import MetalKit
import CoreImage
import AVFoundation
import GameController
import AkitoStationCore
import RetroHost

final class FrameView:MTKView {
 override var acceptsFirstResponder:Bool{true}
 var stretch=false
 override func mouseDown(with e:NSEvent){window?.makeFirstResponder(self);touch(e,true)}
 override func mouseDragged(with e:NSEvent){touch(e,true)}
 override func mouseUp(with e:NSEvent){touch(e,false)}
 func touch(_ event:NSEvent,_ pressed:Bool){let p=convert(event.locationInWindow,from:nil);let h=CGFloat(arm_height()),w=h*CGFloat(arm_aspect_ratio());guard w>0,h>0 else{return};let scale=min(bounds.width/w,bounds.height/h);let rw=stretch ? bounds.width:w*scale,rh=stretch ? bounds.height:h*scale;let x=(p.x-(bounds.width-rw)/2)/rw;let y=1-(p.y-(bounds.height-rh)/2)/rh;arm_pointer(Int16(max(-32767,min(32767,x*65534-32767))),Int16(max(-32767,min(32767,y*65534-32767))),pressed && x>=0 && x<=1 && y>=0 && y<=1 ? 1:0)}
 var keys:[UInt16:[UInt32]]=[:]
 var keyboard=KeyboardInput()
 var pressed:Set<UInt32>{keyboard.active}
 func updateAnalog(){arm_analog(0,0,0,Int16((pressed.contains(7) ? 32767:0)-(pressed.contains(6) ? 32767:0)));arm_analog(0,0,1,Int16((pressed.contains(5) ? 32767:0)-(pressed.contains(4) ? 32767:0)))}
 override func keyDown(with e:NSEvent){if let ids=keys[e.keyCode]{for id in ids{keyboard.press(id)}}else{super.keyDown(with:e)}}
 override func keyUp(with e:NSEvent){if let ids=keys[e.keyCode]{for id in ids{keyboard.release(id)}}else{super.keyUp(with:e)}}
 override func resignFirstResponder()->Bool{keyboard.clear();return super.resignFirstResponder()}

}
@MainActor final class Player:NSObject,ObservableObject,MTKViewDelegate {
 @Published var paused=false;@Published var status="Starting…";@Published var failure:String?;@Published var frameCount:UInt64=0
 let adapter=LibretroSystemAdapter()
 var timingStart=ProcessInfo.processInfo.systemUptime;var timingFrames=0;var coreMilliseconds=0.0;var peakCoreMilliseconds=0.0
 var bindings=ControllerBindings();var previousControllerPorts=0
 var timer:Timer?;var storageCheckCounter=0;var engine=AVAudioEngine();var source:AVAudioSourceNode?;var view:FrameView?;var context:CIContext?;var queue:MTLCommandQueue?;var saves:URL;var states:URL;var screenshots:URL;var profile:GameProfile;var title:String;var stopped=false;var scratch=[Float](repeating:0,count:32768);var muteOnPause=false
 init(arguments:[String]) {
 func arg(_ key:String)->String{guard let i=arguments.firstIndex(of:key),i+1<arguments.count else{return ""};return arguments[i+1]}
 saves=URL(fileURLWithPath:arg("--saves"));states=URL(fileURLWithPath:arg("--states"));screenshots=URL(fileURLWithPath:arg("--screenshots"));title=arg("--title");profile=(try? JSONStore.read(GameProfile.self,from:URL(fileURLWithPath:arg("--profile")))) ?? GameProfile()
 bindings=(try? JSONStore.read(ControllerBindings.self,from:URL(fileURLWithPath:arg("--controller-profile")))) ?? ControllerBindings()
 super.init()
 do{try bindings.validate();try adapter.loadGame(GameLoadRequest(core:URL(fileURLWithPath:arg("--core")),game:URL(fileURLWithPath:arg("--game")),system:URL(fileURLWithPath:arg("--system")),saves:saves,profile:profile));try adapter.start()}catch{failure=error.localizedDescription;status="Boot failed";return}
 _=arm_sram(saves.appendingPathComponent("battery.srm").path,0)
 do {let format=AVAudioFormat(standardFormatWithSampleRate:arm_sample_rate(),channels:2)!
 let audio=AVAudioSourceNode(format:format){_,_,count,list -> OSStatus in
 let buffers=UnsafeMutableAudioBufferListPointer(list);let frames=Int(count);var temp=[Float](repeating:0,count:frames*2);_=arm_audio(&temp,frames);for c in 0..<min(2,buffers.count){let output=buffers[c].mData!.assumingMemoryBound(to:Float.self);for i in 0..<frames{output[i]=temp[i*2+c]}};return noErr}
 source=audio;engine.attach(audio);engine.connect(audio,to:engine.mainMixerNode,format:format);engine.mainMixerNode.outputVolume=Float(profile.volume);try engine.start()
 }catch{status="Audio unavailable: \(error.localizedDescription)"}
 timer=Timer(timeInterval:1.0/arm_fps(),repeats:true){[weak self]_ in MainActor.assumeIsolated{self?.tick()}};RunLoop.main.add(timer!,forMode:.common);status="\(String(cString:arm_core_name())) • Metal • \(Int(arm_fps().rounded())) fps"
 }
 func tick(){guard !paused,!stopped else{return};storageCheckCounter += 1;if storageCheckCounter>=60{storageCheckCounter=0;if !FileManager.default.isWritableFile(atPath:saves.path) || !FileManager.default.isWritableFile(atPath:states.path){togglePause();failure="Save storage is unavailable. Reconnect its volume before resuming.";return}};for id in 0..<16{arm_input(0,UInt32(id),(view?.pressed.contains(UInt32(id)) ?? false) ? 1:0)};view?.updateAnalog();let controllers=profile.controller == "Keyboard" ? []:Array(GCController.controllers().prefix(4));if controllers.count<previousControllerPorts{for port in controllers.count..<previousControllerPorts{for id in 0..<16{arm_input(UInt32(port),UInt32(id),0)};for stick in 0..<2{for axis in 0..<2{arm_analog(UInt32(port),UInt32(stick),UInt32(axis),0)}}}};previousControllerPorts=controllers.count;for (port,c) in controllers.enumerated(){guard let g=c.extendedGamepad else{continue};for (stick,axes) in [[g.leftThumbstick.xAxis.value,-g.leftThumbstick.yAxis.value],[g.rightThumbstick.xAxis.value,-g.rightThumbstick.yAxis.value]].enumerated(){for (axis,value) in axes.enumerated(){arm_analog(UInt32(port),UInt32(stick),UInt32(axis),abs(value)<bindings.deadZone ? 0:Int16(max(-32767,min(32767,value*32767))))}};let inputs:[String:GCControllerButtonInput?]=["A":g.buttonA,"B":g.buttonB,"X":g.buttonX,"Y":g.buttonY,"Options":g.buttonOptions,"Menu":g.buttonMenu,"Up":g.dpad.up,"Down":g.dpad.down,"Left":g.dpad.left,"Right":g.dpad.right,"L1":g.leftShoulder,"R1":g.rightShoulder,"L2":g.leftTrigger,"R2":g.rightTrigger,"L3":g.leftThumbstickButton,"R3":g.rightThumbstickButton];for (id,action) in ControllerBindings.actions.enumerated(){let input=bindings.gamepad[action] ?? "None";var down=(inputs[input] ?? nil)?.isPressed ?? false;if input=="Up"{down = down || g.leftThumbstick.yAxis.value>bindings.deadZone};if input=="Down"{down = down || g.leftThumbstick.yAxis.value < -bindings.deadZone};if input=="Left"{down = down || g.leftThumbstick.xAxis.value < -bindings.deadZone};if input=="Right"{down = down || g.leftThumbstick.xAxis.value>bindings.deadZone};arm_input(UInt32(port),UInt32(id),(down || (port==0 && (view?.pressed.contains(UInt32(id)) ?? false))) ? 1:0)}};let start=ProcessInfo.processInfo.systemUptime;adapter.runFrame();view?.keyboard.didRunFrame();let elapsed=(ProcessInfo.processInfo.systemUptime-start)*1000;coreMilliseconds += elapsed;peakCoreMilliseconds=max(peakCoreMilliseconds,elapsed);timingFrames += 1;view?.draw()
 let now=ProcessInfo.processInfo.systemUptime
 if now-timingStart>=2{let fps=Double(timingFrames)/(now-timingStart);status=String(format:"%@ • %.1f / %.1f fps • core %.1f ms",String(cString:arm_core_name()),fps,arm_fps(),coreMilliseconds/Double(timingFrames));fputs(String(format:"Akito Station timing: %.1f fps, core mean %.2f ms, max %.2f ms\n",fps,coreMilliseconds/Double(timingFrames),peakCoreMilliseconds),stderr);frameCount=arm_frames();timingStart=now;timingFrames=0;coreMilliseconds=0;peakCoreMilliseconds=0}
 }
 func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize){}
 func draw(in v:MTKView){guard let drawable=v.currentDrawable,let pixels=arm_pixels(),arm_width()>0,let context=context,let command=queue?.makeCommandBuffer() else{return};let w=Int(arm_width()),h=Int(arm_height());let data=Data(bytes:pixels,count:w*h*4);let source=CIImage(bitmapData:data,bytesPerRow:w*4,size:CGSize(width:w,height:h),format:.BGRA8,colorSpace:CGColorSpaceCreateDeviceRGB());let image=profile.options["arm.display.filter"]=="Nearest" ? source.samplingNearest():source.samplingLinear();let tw=CGFloat(drawable.texture.width),th=CGFloat(drawable.texture.height);let sx=tw/CGFloat(w),sy=th/CGFloat(h);let displayWidth=CGFloat(h)*CGFloat(arm_aspect_ratio());let scale=min(tw/displayWidth,sy);let output:CIImage
 if profile.aspect=="Stretch"{output=image.transformed(by:CGAffineTransform(scaleX:sx,y:sy))}else{output=image.transformed(by:CGAffineTransform(scaleX:displayWidth/CGFloat(w)*scale,y:scale)).transformed(by:CGAffineTransform(translationX:(tw-displayWidth*scale)/2,y:(th-CGFloat(h)*scale)/2))}
 let black=CIImage(color:.black).cropped(to:CGRect(x:0,y:0,width:tw,height:th));context.render(output.composited(over:black),to:drawable.texture,commandBuffer:command,bounds:CGRect(x:0,y:0,width:tw,height:th),colorSpace:CGColorSpaceCreateDeviceRGB());command.present(drawable);command.commit()}
 func togglePause(){defer{focusGame()};if paused && (!FileManager.default.isWritableFile(atPath:saves.path) || !FileManager.default.isWritableFile(atPath:states.path)){failure="Reconnect save storage before resuming.";return};paused.toggle();if paused{adapter.pause()}else{adapter.resume()};engine.mainMixerNode.outputVolume=paused ? 0:Float(profile.volume)}
 func focusGame(){view?.window?.makeFirstResponder(view)}
 func saveState(){defer{focusGame()};let target=states.appendingPathComponent("quick.state"),temp=states.appendingPathComponent("quick.pending");if arm_state(temp.path,1) != 0{do{try Data(contentsOf:temp).write(to:target,options:.atomic);try FileManager.default.removeItem(at:temp);status="State saved"}catch{failure=error.localizedDescription}}else{failure="This runtime could not serialize the current game"}}
 func loadState(){defer{focusGame()};if arm_state(states.appendingPathComponent("quick.state").path,0)==0{failure="No compatible save state"}else{status="State restored"}}
 func screenshot(){defer{focusGame()};do{guard FileManager.default.isWritableFile(atPath:screenshots.path) else{throw AkitoStationError.message("Screenshot storage is unavailable. Reconnect its configured volume.")};guard let pixels=arm_pixels(),arm_width()>0 else{throw AkitoStationError.message("No game frame available")};let w=Int(arm_width()),h=Int(arm_height());let data=Data(bytes:pixels,count:w*h*4);let ci=CIImage(bitmapData:data,bytesPerRow:w*4,size:CGSize(width:w,height:h),format:.BGRA8,colorSpace:CGColorSpaceCreateDeviceRGB()).transformed(by:CGAffineTransform(scaleX:Double(h)*arm_aspect_ratio()/Double(w),y:1));guard let cg=context?.createCGImage(ci,from:ci.extent),let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else{throw AkitoStationError.message("Could not encode screenshot")};let name=title.replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:":",with:"-");let url=screenshots.appendingPathComponent(name+"-"+UUID().uuidString+".png");try png.write(to:url,options:.atomic);status="Screenshot saved"}catch{failure=error.localizedDescription}}

 func stop(){guard !stopped else{return};stopped=true;timer?.invalidate();engine.stop();let target=saves.appendingPathComponent("battery.srm"),temp=saves.appendingPathComponent("battery.pending");if arm_sram(temp.path,1) != 0{do{try Data(contentsOf:temp).write(to:target,options:.atomic);try FileManager.default.removeItem(at:temp)}catch{fputs("Save persistence failed: \(error)\n",stderr)}};adapter.stop()}
}
struct MetalScreen:NSViewRepresentable {
 @ObservedObject var player:Player
 func makeNSView(context:Context)->FrameView{let v=FrameView(frame:.zero,device:MTLCreateSystemDefaultDevice());v.framebufferOnly=false;v.isPaused=true;v.enableSetNeedsDisplay=false;v.colorPixelFormat = .bgra8Unorm;v.delegate=player;(v.layer as? CAMetalLayer)?.displaySyncEnabled=player.profile.vsync;v.stretch=player.profile.aspect=="Stretch";for (id,action) in ControllerBindings.actions.enumerated(){if let key=player.bindings.keyboard[action],key != 65535{v.keys[key,default:[]].append(UInt32(id))}};player.view=v;if let device=v.device{player.context=CIContext(mtlDevice:device);player.queue=device.makeCommandQueue()};DispatchQueue.main.async{v.window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);v.window?.makeFirstResponder(v);if player.profile.fullscreen{v.window?.toggleFullScreen(nil)}};return v}
 func updateNSView(_ v:FrameView,context:Context){}
}
struct PlayerView:View {
 @ObservedObject var player:Player
 var body:some View{VStack(spacing:0){MetalScreen(player:player);HStack{Text(player.status).font(.caption).foregroundStyle(.secondary);Spacer();Button(player.paused ? "Resume":"Pause"){player.togglePause()}.keyboardShortcut("p");Button("Reset"){player.adapter.reset();player.focusGame()};Button("Save State"){player.saveState()}.keyboardShortcut("s");Button("Load State"){player.loadState()}.keyboardShortcut("l");Button("Screenshot"){player.screenshot()};Button("Stop"){player.stop();NSApp.terminate(nil)}}.padding(12)}.background(.black).frame(minWidth:640,minHeight:480).alert("Runtime",isPresented:Binding(get:{player.failure != nil},set:{if !$0{player.failure=nil}})){Button("OK"){player.failure=nil}}message:{Text(player.failure ?? "")}.onDisappear{player.stop()}}
}
