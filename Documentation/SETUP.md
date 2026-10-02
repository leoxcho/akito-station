# Akito Station Public 1.0.0 setup guide

Start with [Getting Started in the README](../README.md#getting-started). This guide describes the approved Public 1.0.0 implementation, not features from Developer or other builds. The README screenshot is illustrative; the released app uses plain system-style replacements for excluded visual assets.

## First launch and storage selection

Download the ARM64 ZIP from the [official 1.0.0 release](https://github.com/leoxcho/akito-station/releases/tag/v1.0.0), extract it, move the app into Applications and open it. Use the README's per-app approval steps only for developer-verification/missing-notarization warnings. Never bypass malware or damaged-app warnings.

On a fresh launch, **Games** shows **Your next adventure starts here**, asks you to choose ROM libraries in Settings, and offers **Open Settings**. The sidebar includes **Games**, **Consoles**, **Memory cards** and **Settings**. There is no mandatory storage-selection wizard and no bundled runtime to start playing immediately.

Open **Settings → Storage Locations** (the initial settings category). By default, preferences live under `~/Library/Application Support/AkitoStationPublic`, with managed data in its `Data` folder. These are generic user-relative paths, not developer-machine locations. Leave the defaults if you are unsure. Your ROM library folders are separate from the managed data root.

**Master Akito Station data root → Choose…** selects a different existing folder. Individual storage categories also have **Choose…** and **Reset to master root**. Choosing a path changes the configuration; it does not transfer files. For existing managed data, use the migration buttons described below. Do not select an unavailable drive and expect the app to recreate it locally.

## Emulator runtimes

An emulator runtime is the separately installed software that runs a game. A libretro **core** is a compatible native library hosted by Akito's Player; a desktop emulator is an application with its own window and settings. Nothing in the table below is bundled with Akito Station.

### Common installation and registration steps

1. Open **Settings → Emulators** and choose **Console**.
2. For rows offering **Install**, Akito queries that project's configured GitHub releases. A single suitable ZIP can proceed directly; other releases/assets open a browser for selection. Availability depends on current upstream releases. Read prompts and any trust information; installation failure does not prove the game is unsupported. Use **Download from Official Website** and manual registration when necessary.
3. For an independently obtained desktop `.app` or compatible native core `.dylib`, use **Choose Existing Installation**. This registers the external location without moving it. **Install a managed copy…** instead copies it into configured **Runtime Engines** storage. Keep an externally registered installation at its chosen location.
4. Use **Set Default** or **Default Emulator**. Switch requires an explicit user selection; Akito does not silently choose Eden. Game details also offer **Emulator → Use Console Default** or an override; click **Save game profile** after changing it.
5. **Test Emulator** checks startup without a ROM. Architecture, signatures/hashes or native ABI checks do not prove gameplay. **Relink Installation** and, where shown, **Relink Executable…** help repair a moved or changed installation. **Select version** chooses among installed versions; **Check for Updates** queries the configured source.

**Source-build limitation:** the catalog exposes **Build · Requires Developer Tools** / **Install from Source** for several cores, but the published `manage-runtime.py` deliberately rejects source builds: “Source adapter builds are unavailable in the initial publication; import a compatible external runtime instead.” Installing Xcode will not remove this restriction in 1.0.0. The alternative is an independently obtained compatible ARM64 core imported through **Choose Existing Installation**. An Intel desktop app may require Rosetta; Akito's hosted cores must be native ARM64. Installing the Akito app itself does not require Xcode.

### Per-system catalog and actual 1.0.0 workflow

“Release installer” means the configured **Install** workflow above, not a guarantee that a compatible asset currently exists. “Core import” means independently obtain a compatible ARM64 libretro `.dylib` and register/import it. All entries remain subject to the installed version's requirements and licenses; not every runtime/game/controller combination has been validated.

| System | Catalog choices | Workflow in Public 1.0.0 / limits |
| --- | --- | --- |
| NES | Nestopia core | Core import; source-build action disabled. |
| Super Nintendo | Snes9x core | Core import; source-build action disabled. |
| Game Boy / Game Boy Color | Gambatte or mGBA core | Core import; source-build actions disabled. |
| Game Boy Advance | mGBA core | Core import; source-build action disabled. |
| Sega Mega Drive / Genesis | Genesis Plus GX core | Core import; source-build action disabled; respect upstream non-commercial terms. |
| PC Engine | Beetle PCE Fast core | Core import; source-build action disabled. |
| Nintendo 64 | ParaLLEl N64 core | Core import; source-build action disabled; compatible rendering support is runtime-dependent. |
| Nintendo DS | melonDS DS core | Core import; source-build action disabled. Excluded melonDS-derived option metadata is not shipped. |
| Nintendo 3DS | Azahar; existing Lime3DS | Azahar release installer or existing `.app`; Lime3DS existing installation only, no mirror downloads. |
| PlayStation | DuckStation; PCSX ReARMed core | DuckStation official download and existing `.app` registration; PCSX core import (source-build action disabled). |
| PlayStation 2 | PCSX2; ARMSX2 | PCSX2 release installer or existing `.app`; ARMSX2 independently obtained `.app`. |
| PlayStation 3 | RPCS3 | Release installer or existing `.app`; firmware must be installed by the runtime. Package import is separate from boot validation. |
| PlayStation 4 | shadPS4 | Release installer or existing `.app`; experimental, game-format/system-resource support depends on the runtime. |
| PSP | PPSSPP desktop; PPSSPP core | Desktop from official website and register `.app`; core import (source-build action disabled). |
| PlayStation Vita | Vita3K | Release installer or existing `.app`; desktop route exists, embedded engine unavailable. Firmware/fonts and game installation are separate runtime tasks. Experimental. |
| GameCube / Wii | Dolphin desktop; existing Akito Dolphin adapter | Obtain Dolphin independently and register `.app` using the normal Dolphin row. Adapter row only appears if an adapter is already registered; requires an existing compatible adapter, not a standard Dolphin app. No adapter source build in this release. |
| Wii U | Cemu | Release installer or existing `.app`; internal-resolution graphics packs and resource validation belong to Cemu. |
| Xbox | xemu | Release installer or existing `.app`; requires runtime-compatible system resources. |
| Xbox 360 | Existing Xenia macOS port | Independently obtain a compatible macOS port and register it. Upstream does not provide a supported macOS installer; experimental, no blanket compatibility claim. |
| Dreamcast | Flycast | Release installer or existing `.app`. |
| Sega Saturn | Beetle Saturn core | Independently obtained compatible core import; no automatic build/install action. |

**+ Add Emulator** is available for each identified console. Its modes are **Install Supported Emulator**, **Import Existing Emulator** and **Add Custom Emulator**. For a custom emulator, choose the application/executable, console and name; verify the **Game launch method** and game arguments against that emulator's own documentation, then **Save Emulator**. The app supports command-line arguments or opening the game as a document; it cannot infer every custom launch interface. Use **Edit**, **Test Emulator** and **Set as Default** afterward. This can register additional choices such as a user-supplied Switch app, but is not proof of their game compatibility.

Managed uninstall removes managed runtime files; externally installed apps are only unregistered. Games, saves, firmware, BIOS, keys and profiles remain. **Test Emulator** does not establish publisher trust or a working game session. Review the displayed trust information; stop a running runtime before changing/removing it.

### BIOS, firmware, keys and system resources

Use **Settings → BIOS / Firmware / Keys**, select **Console**, then **Import BIOS / firmware / keys…** to copy your own resources with copy verification. Originals stay unchanged. This import stores files under **Saves / SystemImports / console**, not simply in the separate Firmware directory. The **Firmware / BIOS / System Resources** location is also used by resource routing; do not assume changing that location moves previous imports.

An imported file is labeled **runtime validation required** or **runtime installation required**. A copied `.PUP`, firmware archive or NAND archive is **not installed firmware**. Complete installation and resource selection through the selected runtime's supported procedures; external desktop routes can require setup in that emulator itself. Akito's copy check does not establish compatibility. Consult the runtime's official documentation; Akito does not obtain these files for you.

| System | Resource guidance exposed by Akito |
| --- | --- |
| NES | Famicom Disk System BIOS for disk games; cartridge games generally do not need it. |
| GB / GBC / GBA | Optional original boot ROM / GBA BIOS. |
| PC Engine | System-card BIOS for CD games; not HuCard games. |
| DS | Your `bios7.bin`, `bios9.bin`, `firmware.bin`. |
| 3DS | Required AES keys, seed database or other system data, as validated by the runtime. |
| PS1 | BIOS dump; selected engine checks region/checksum compatibility. |
| PS2 | BIOS plus accompanying NVM/MEC files where needed; engine must select/validate them. |
| PS3 | Firmware update `.PUP`; install through the PS3 runtime. |
| Vita | System firmware and font packages; install both through the Vita runtime. |
| Switch | Your console keys and firmware; firmware installation belongs to the runtime. |
| Wii U | Required keys/system resources; Cemu validates them. |
| GameCube / Wii | IPL, NAND or other resources if required; NAND archives require runtime installation. |
| PS4 | Requirements depend on the selected runtime; firmware packages require an installer. |
| Dreamcast / Saturn / Xbox / Xbox 360 | Runtime-required BIOS, firmware or system-data dumps; runtime validation required. |
| Other systems | Only resources required by the selected engine/game; no universal requirement implied. |

This is a description of the import UI, not a guide to extracting copyrighted data or bypassing encryption/protection.

## Add games

For ordinary game files, open **Settings → Storage Locations → ROM Libraries → Add folder…**. Select a folder on your Mac or connected external drive. It is scanned automatically; files are indexed in place rather than copied. Add multiple folders as needed. **Scan libraries** or toolbar **Refresh library** rescans after additions. Library merge preserves existing favorite/play metadata for matching indexed entries.

There is no regular individual-file import picker or drag-and-drop import handler in this Public library view. Put a supported file into a configured library folder and scan. Supported scanner extensions include cartridge formats (`nes`, `fds`, `sfc`, `smc`, `gb`, `gbc`, `gba`, `md`, `gen`, `smd`, `pce`, `z64`, `n64`, `v64`, `nds`), disc/playlist formats (`iso`, `chd`, `cue`, `gdi`, `m3u`, `cso`, `pbp`, `wbfs`, `rvz`, `gcz`), 3DS (`3ds`, `cci`), Wii U (`wud`, `wux`, `wua`, `rpx`), Switch (`nsp`, `xci`, `nro`, `nso`, `nca`, `nsz`, `xcz`, `ncz`) and `xex`. **Recognition by the scanner does not mean the chosen runtime can launch that format.** Generic ZIP archives are not ordinary scanner game inputs.

System identification uses recognized extensions, supported header checks and ancestor folder aliases. Keep ambiguous formats such as ISO/CHD/CUE beneath a console folder (`ps1`, `ps2`, `psp`, `gamecube`, `wii`, `saturn`, etc.). Shared formats can remain **Unidentified** when the source path lacks a recognized console name. There is no documented manual console-edit control in the library details; correct the folder organization and rescan. Folder-based console content also has special recognition rules.

After scanning, titles appear in **Games**, derived from filenames; use search, **Sort**, system filters, **Favorites** and **Recently played**. Import does not test gameplay; entries begin as **Not tested**.

For PS3/PS4/Vita package workflows, **Settings → Packages / Licenses** provides a console selector, configured **ROM library** destination, **Choose PKG…**, detected package information and **Install package**. Vita also exposes selection of a matching user-supplied license; PS4 exposes **Install extracted PS4 game folder…**. These specialized workflows check package/platform consistency and can fail for unsupported packages. They are not a general ROM picker, a firmware installer or a compatibility guarantee. Only use packages/licenses you are entitled to use; this guide gives no decryption or circumvention steps.

## Cover artwork

Click a game to open details, then **Change box art…**. In **Box art**, edit **Game title**, click **Search online**, then select a result. **All systems (includes covers from other editions)** broadens the search. A shorter title can help. Online editor search uses Libretro Thumbnails and TheGamesDB; search requests disclose the query/system to providers, not ROM contents.

**Choose image…** accepts PNG, JPEG, TIFF, HEIC or WebP up to 8 MiB (the UI asks for an image smaller than 8 MB). The chosen image is copied/installed into artwork storage; your original stays unchanged. Covers/cache metadata live under configured **Metadata / Database** storage.

Automatic missing-cover lookup and **Scrape all box art** use Libretro thumbnails; bulk scraping preserves existing covers and offers **Cancel**. **Settings → General → Use local artwork only** disables automatic card lookup; explicit **Search online** and **Scrape all box art** still trigger network actions. Use **Choose image…** if you want local artwork. No game covers are bundled with the app.

## Launch a game

Click a library card → **Play**, double-click a card, or right-click → **Play**. In details, **Emulator** selects the console default or a per-game override; use **Save game profile**. **Manage Emulators** opens that console's runtime panel.

With no selected engine, **No emulator installed** offers **Install Emulator** and **Choose Existing Installation**. An engine with missing/invalid files may instead fail runtime validation and show an error; open **Settings → Emulators** to install/relink/select it. Startup checks cannot replace a real-game test.

Desktop runtime routes use their own windows; some managed integrations launch with Akito-owned settings/save/cache locations. Externally registered desktop apps can retain their own settings and save locations. Native libretro cores use the Akito Player. Vita/Switch embedded engines are unavailable in 1.0.0; desktop routes for catalog choices exist separately and do not make them embedded gameplay. Not every registration, managed-copy and launch combination is equivalent. If an embedded-engine-unavailable error appears, use a supported external desktop registration rather than expecting that app to run inside Akito.

## Storage and saves

**Storage Locations** lists Saves, Save States, Shader / Pipeline Caches, Firmware / BIOS / System Resources, Controllers, Profiles, Screenshots, Metadata / Database, Runtime Engines, Logs and Downloads / Build Data. Defaults are subfolders of the master root; categories can have individual overrides.

For Akito's libretro Player, saves are per indexed game; battery save data is persisted on stop. **Save State** / **Load State** (⌘S / ⌘L) operate on a single quick-state slot when supported by the core. **Pause** uses ⌘P. Serialization can fail or be incompatible after changing a core; use normal in-game saves and backups as well. These Player controls do not control an independently launched desktop emulator; use that emulator's own controls for save states. Desktop save locations vary by route, runtime and imported settings. **Memory cards** browses configured save collections; it does not prove all external-emulator saves are discovered.

Managed runtimes live in **Runtime Engines**, outside the app bundle. External registrations reference the original installation. Caches, logs and downloads also stay outside the bundle. Avoid deleting save/runtime folders while games are running.

Use **Move managed data with verification…** for a master-root migration, or **Move managed data…** for an eligible individual category. The app copies and verifies managed data, retains the original and updates the selected location; individual overrides remain in place during a master migration. Firmware has no individual Move button. **Choose…**, resets and ROM-library removal change paths/configuration without moving/deleting those files. Save backups before reconfiguration. **Reset All Settings…** also clears library paths; it is not a first-line troubleshooting step.

External locations record bookmarks and volume identity. A missing/wrong volume stops access instead of silently replacing it; failed library scans preserve the existing index. Reconnect the original drive. If a library actually moved, remove its old library entry, **Add folder…** for the new location and scan. Because game identity includes the library path, favorites, artwork links, profiles and per-game managed save associations may not carry over to a newly indexed path. Keep old data and backups; this release has no dedicated library-relocation wizard.

## Controllers

Pair/connect a controller through macOS, then check the detected name in **Settings → Controllers** (the fallback is **Keyboard**). The frontend uses Apple's GameController discovery; supported extended gamepads can navigate with the D-pad and launch with A. Device support depends on macOS and the runtime; every controller has not been tested.

For hosted cores, choose **Console profile → Shared defaults** or an available console, select keyboard/gamepad mappings and stick dead zone, then **Save mappings**. Changes apply on the next game start. **Settings → Systems** or game profile **Input → Keyboard** disables physical gamepad input for libretro games; **Automatic** permits it.

The **GameCube / Wii gamepad** mapping tab concerns compatible Dolphin adapter/native-settings routes. Ordinary Dolphin desktop applications and other desktop runtimes require their own controller setup. Where native settings are enabled, use **Emulator Settings**. Do not assume Akito's mapping screen controls an independently launched emulator or provides Wii motion/peripheral support for every game.

## Troubleshooting

| Symptom | Action supported by this implementation |
| --- | --- |
| Akito will not open | Check Apple Silicon/macOS 14+, extract into a normal app and use the official release. For the specified developer-verification warning, use the README's per-app approval. Stop for malware or damaged-app warnings; do not remove security protections. |
| Runtime absent or damaged | Select the correct Console; register the installed `.app`/compatible `.dylib`, **Relink Installation** or **Relink Executable…**. Set the default and inspect the validation error/trust information. Changed external executables need re-verification. |
| Source-build installation fails | This operation is deliberately unavailable in 1.0.0. Import an independently obtained compatible core; adding build tools does not enable it. |
| Game fails to launch | Read the error. Confirm its console/folder, readable file, selected runtime/version, supported format and installed/validated resources. Use **Test Emulator** for startup only. Consult the runtime's own documentation/settings; a library card is not a boot test. |
| Firmware marked imported but boot still fails | Copy verification does not install firmware or certify compatibility. Complete the selected runtime's installation/validation; external runtime settings may need explicit resource selection. |
| Cover not found | Shorten the title, try **All systems**, or supply a local image. Check **Use local artwork only** for automatic lookup. A missing provider cover is not a game error. |
| Drive disconnected/moved | Reconnect the original volume; storage access is refused if unavailable or volume identity differs. For moved folders, reselect/add the location and scan, preserving backups and old per-game data. |
| Controller missing | Check macOS pairing/connection and the name in **Controllers**; save mappings and restart the game. For desktop emulators, configure input there. Unsupported device/runtime combinations are not repaired by a frontend mapping. |

When reporting an issue, include the app version, console/runtime version, steps and the displayed error. Review logs before sharing: they can contain your game filenames or local paths. Never upload games, console keys, licenses, credentials or private data to public issues.

## Safety, rights and evidence limits

Akito Station provides no games, ROMs, BIOS, firmware, console encryption keys or other copyrighted system files. Obtain and use content/software in accordance with applicable law and licenses. See [license scope](../LICENSE_SCOPE.json) and [third-party notices](THIRD_PARTY_NOTICES.md).

The 1.0.0 release passed its source/app boundary scans and Public tests (122 tests, zero failures, two optional live-provider skips). Tests cover fixtures, scanning/storage safeguards, runtime registration/ABI and other implementation behavior; they do not establish every real runtime, game, save/controller workflow or clean-machine setup. Production payment/PRO functionality is not fully validated and is not required for this basic setup guide.

This guide was checked against the Public source shipped at commit `7a437abef7f1f98546e045c1611d65e4e8e1c71f`: Store, LibraryView, SettingsView, OptionalRuntimeView/Store, AddEmulatorView, ArtworkEditor, ControllerSettings, FirmwareSettings, ContentInstallView, Player, Models, RuntimeCatalog, ConsoleResources, EmbeddedRuntime, runtime tools and corresponding storage/artwork/runtime/controller/import tests. Catalog/UI support is described as such, not as a guarantee of current upstream availability or successful gameplay.
