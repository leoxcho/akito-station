import Foundation

public enum RuntimeInstallMethod:String,Codable,Sendable {case githubRelease, sourceBuild, manual}
/// Distribution and launch capabilities are independent of the installed manifest.
public struct RuntimeDefinition:Codable,Identifiable,Sendable {
 public var id:String;public var name:String;public var platforms:[Platform]
 public var officialSource:String;public var license:String;public var installation:RuntimeInstallMethod
 public var releaseRepository:String?;public var desktop:Bool
 public var architecture:String {"arm64 / universal; Intel apps require Rosetta"}
 public var verification:String {desktop ? "Bundle signature, Mach-O architecture and executable SHA-256":"Native libretro ABI and executable SHA-256"}
 public var updateMethod:String {installation == .githubRelease ? "Official releases":installation == .sourceBuild ? "Official source build":"Official website / register updated installation"}
 public init(_ id:String,_ name:String,_ platforms:[Platform],_ source:String,_ license:String,_ method:RuntimeInstallMethod = .manual,repository:String?=nil,desktop:Bool=true){self.id=id;self.name=name;self.platforms=platforms;officialSource=source;self.license=license;installation=method;releaseRepository=repository;self.desktop=desktop}
}
public enum RuntimeCatalog {
 public static let definitions:[RuntimeDefinition] = [
  .init("nestopia","Nestopia (core)",[.nes],"https://github.com/libretro/nestopia","GPL-2.0",.sourceBuild,desktop:false),
  .init("snes9x","Snes9x (core)",[.snes],"https://github.com/snes9xgit/snes9x","Snes9x non-commercial",.sourceBuild,desktop:false),
  .init("gambatte","Gambatte (core)",[.gb,.gbc],"https://github.com/libretro/gambatte-libretro","GPL-2.0",.sourceBuild,desktop:false),
  .init("mgba","mGBA (core)",[.gba,.gb,.gbc],"https://github.com/mgba-emu/mgba","MPL-2.0",.sourceBuild,desktop:false),
  .init("genesis_plus_gx","Genesis Plus GX (core)",[.genesis],"https://github.com/libretro/Genesis-Plus-GX","Non-commercial; see upstream license",.sourceBuild,desktop:false),
  .init("mednafen_pce_fast","Beetle PCE Fast (core)",[.pce],"https://github.com/libretro/beetle-pce-fast-libretro","GPL-2.0-or-later",.sourceBuild,desktop:false),
  .init("parallel_n64","ParaLLEl N64 (core)",[.n64],"https://github.com/libretro/parallel-n64","GPL-2.0-or-later",.sourceBuild,desktop:false),
  .init("melondsds","melonDS DS (core)",[.nds],"https://github.com/JesseTG/melonds-ds","GPL-3.0-or-later",.sourceBuild,desktop:false),
  .init("pcsx_rearmed","PCSX ReARMed (core)",[.ps1],"https://github.com/libretro/pcsx_rearmed","GPL-2.0",.sourceBuild,desktop:false),
  .init("ppsspp","PPSSPP (core)",[.psp],"https://github.com/hrydgard/ppsspp","GPL-2.0-or-later",.sourceBuild,desktop:false),
  .init("beetle_saturn","Beetle Saturn (core)",[.saturn],"https://github.com/libretro/beetle-saturn-libretro","GPL-2.0",desktop:false),
  .init("ppsspp_sdl","PPSSPP",[.psp],"https://www.ppsspp.org/download/","GPL-2.0-or-later"),
  .init("duckstation","DuckStation",[.ps1],"https://github.com/stenzek/duckstation","See upstream license"),
  .init("pcsx2","PCSX2",[.ps2],"https://github.com/PCSX2/pcsx2","GPL-3.0",.githubRelease,repository:"https://github.com/PCSX2/pcsx2"),
  .init("armsx2","ARMSX2",[.ps2],"https://github.com/ARMSX2/ARMSX2","See upstream license"),
  .init("rpcs3","RPCS3",[.ps3],"https://rpcs3.net/download","GPL-2.0",.githubRelease,repository:"https://github.com/RPCS3/rpcs3-binaries-mac-arm64"),
  .init("shadps4","shadPS4",[.ps4],"https://github.com/shadps4-emu/shadPS4","GPL-2.0",.githubRelease,repository:"https://github.com/shadps4-emu/shadPS4"),
  .init("vita3k","Vita3K",[.psvita],"https://vita3k.org/","GPL-2.0",.githubRelease,repository:"https://github.com/Vita3K/Vita3K"),
  .init("eden","Eden",[.switchConsole],"https://eden-emu.dev/get-started/","GPL-3.0"),
  .init("ryujinx","Ryujinx (existing installation)",[.switchConsole],"https://github.com/Ryujinx","See installed version license"),
  .init("azahar","Azahar",[.n3ds],"https://github.com/azahar-emu/azahar","GPL-2.0",.githubRelease,repository:"https://github.com/azahar-emu/azahar"),
  .init("lime3ds","Lime3DS (existing installation)",[.n3ds],"https://github.com/Lime3DS/Lime3DS","GPL-2.0"),
  .init("dolphin_app","Dolphin",[.gc,.wii],"https://dolphin-emu.org/download/","GPL-2.0-or-later"),
  .init("dolphin","Dolphin (Akito adapter)",[.gc,.wii],"https://github.com/dolphin-emu/dolphin","GPL-2.0-or-later",desktop:false),
  .init("cemu","Cemu",[.wiiu],"https://github.com/cemu-project/Cemu","MPL-2.0",.githubRelease,repository:"https://github.com/cemu-project/Cemu"),
  .init("xemu","xemu",[.xbox],"https://xemu.app/","GPL-2.0",.githubRelease,repository:"https://github.com/xemu-project/xemu"),
  .init("xenia","Xenia (existing macOS port)",[.xbox360],"https://github.com/xenia-project/xenia","BSD-3-Clause; macOS support depends on port"),
  .init("flycast","Flycast",[.dreamcast],"https://github.com/flyinghead/flycast","GPL-2.0",.githubRelease,repository:"https://github.com/flyinghead/flycast")
 ]
 public static func definition(_ id:String)->RuntimeDefinition? {definitions.first{$0.id==id}}
 public static func choices(_ platform:Platform)->[RuntimeDefinition] {definitions.filter{$0.platforms.contains(platform)}}
 public static func selected(platform:Platform,system:String?,game:String?,installed:[RuntimeManifest])->String? {
  let choices=EmulatorEngines.choices(for:platform,installed:installed)
  if let game=game,!game.isEmpty {return choices.contains(game) ? game:nil}
  if let system=system,!system.isEmpty {return choices.contains(system) ? system:nil}
  if platform == .switchConsole {return nil}
  return choices.first{candidate in installed.contains{$0.id==candidate && $0.validated}} ?? platform.core ?? choices.first
 }
 public static func desktopArguments(engine:String,platform:Platform,game:URL)throws->[String] {
  guard definition(engine)?.platforms.contains(platform)==true else{throw AkitoStationError.message("Emulator does not support this console")}
  switch engine {
  case "eden":return ["-g",game.path]
  case "ryujinx":return [game.path]
  case "shadps4":return try ExternalEmulator.arguments(.ps4,game:game)
  case "rpcs3":return ["--no-gui",game.path]
  case "duckstation":return ["-batch","--",game.path]
  case "pcsx2","armsx2":return ["-batch","--",game.path]
  case "cemu":return ["--game",game.path]
  case "xemu":return ["-dvd_path",game.path]
  case "dolphin_app":return ["--exec",game.path]
  case "xenia":return [game.path]
  default:return [game.path]
  }
 }
}
