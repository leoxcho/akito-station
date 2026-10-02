# Optional emulators — canonical Public

The existing Public app is a frontend and runtime manager. Its signed bundle contains zero emulator binaries, cores, runtime archives or seeds. Runtime installation never changes the signed application. There is no automatic seed import.

Settings → Emulators → Console lists available choices even on an empty installation. Install downloads an official release when a suitable macOS asset is available; multiple assets open a release chooser. Install from Source builds recorded official upstream code locally and checks the native ABI. Source builds require Xcode command-line tools and upstream build tools such as CMake. Manual choices open the official project or register an existing installation. No mirrors or proprietary firmware/BIOS/key downloads are provided.

| Console | Choices | Install / update method |
|---|---|---|
| NES | Nestopia core | Official source build / source update |
| SNES | Snes9x core | Official source build / source update |
| Game Boy / Game Boy Color | Gambatte, mGBA cores | Official source build / source update |
| Game Boy Advance | mGBA core | Official source build / source update |
| Mega Drive | Genesis Plus GX core | Official source build / source update |
| PC Engine | Beetle PCE Fast core | Official source build / source update |
| Nintendo 64 | ParaLLEl N64 core | Official source build / source update |
| Nintendo DS | melonDS DS core | Official source build / source update |
| Nintendo 3DS | Azahar; existing Lime3DS | Azahar official GitHub release installer/update; Lime3DS manual |
| PlayStation | DuckStation; PCSX ReARMed core | DuckStation manual; core official source build/update |
| PlayStation 2 | PCSX2; ARMSX2 | PCSX2 official GitHub release installer/update; ARMSX2 manual |
| PlayStation 3 | RPCS3 | Official ARM64 GitHub release installer/update |
| PlayStation 4 | shadPS4 | Official GitHub release installer/update |
| PSP | PPSSPP desktop; PPSSPP core | Desktop official website/manual; core official source build/update |
| PS Vita | Vita3K | Official GitHub release installer/update |
| GameCube / Wii | Dolphin; existing Akito Dolphin adapter | Standard Dolphin official website/manual; legacy adapter selectable only when already installed |
| Wii U | Cemu | Official GitHub release installer/update |
| Xbox | xemu | Official GitHub release installer/update |
| Xbox 360 | Existing compatible macOS Xenia port | External/manual only; upstream does not provide supported macOS installation |
| Dreamcast | Flycast | Official GitHub release installer/update |
| Saturn | Beetle Saturn core | User-provided compatible native libretro core; manual updates |
| Nintendo Switch | Eden; existing Ryujinx | Eden official website/manual updates; existing Ryujinx registration only |

Available catalog definitions are not claims of game compatibility. Native architecture, signatures and/or libretro ABI checks do not establish game boot compatibility. Some official releases do not contain suitable signed macOS apps; installation fails closed and offers official download/existing-installation alternatives. Source build recipes can fail when upstream APIs/dependencies change.

## Ownership and selection

Managed Runtime is an owned copy or official download/source build outside the app. External Runtime is a manifest pointing at the original app/core, with executable hash verification before launch. External application registration requires a valid existing code signature; external libretro registration requires native ABI validation. External files are not copied, re-signed or deleted. If an external updater changes the binary, register the updated installation again.

Console defaults persist in system profiles. Game → Settings → Emulator provides Use Console Default or a compatible per-game override; save the game profile. Overrides take priority on all launch paths. A missing/unavailable selected runtime opens a native prompt with Install Emulator, Choose Existing Installation and Cancel; both management actions open the relevant console's choices.

The manager shows versions, Set Default, supported update controls, Open Runtime Folder, official source/license links and Uninstall/Unregister. Managed removal deletes only the runtime ID's owned directory. It refuses overlapping game/user-data storage and detects protected data folders inside a runtime. External removal deletes registration records only, including when the original has disappeared or changed. Runtime updates retain the previous selected version; external files stay outside owned directories.

Default managed storage: `~/Library/Application Support/AkitoStationPublic/Data/runtimes`. Configured runtime storage overrides remain supported. Game/save/firmware/controller/profile storage stays separate. Desktop emulators may use their own application data; their data/configuration is never deleted by runtime removal.

## Validation

78 Swift tests passed, one optional live test skipped. 16 backend tests passed. Settings import and release installer security tests passed. Source and packaged fixture tests covered managed install, external registration, version selection, copied hash/signature checks and fixture executable launches for RPCS3, PPSSPP, PCSX2, Vita3K, Eden, shadPS4, Azahar, Dolphin and Flycast; native core fixtures verified both ownership modes. Swift tests cover default/override precedence, console compatibility, hash tampering, size/checksum rejection, unregister after external update, safe removal preserving user data, and routing of user-supplied Saturn BIOS filenames.

A real Gambatte official-source installation passed native ABI validation in temporary storage. Checking/building the official latest HEAD correctly reported the pinned revision already validated. Fixture updates exercised changing selected versions and retaining previous versions. Actual commercial-game gameplay, live signed release installation for every app, and live Auth0/payment submissions were not tested. The missing-runtime alert is implemented; its actual game-triggered UI interaction remains unexercised.

The final Public app launches and its Emulators UI was inspected. Public identity/storage separation, zero bundled runtime content, credential/personal-path/resource scans and strict main/helper signing verification pass. Developer source/app/runtime hashes remain unchanged. Existing legal clearance, Developer ID/notarization and clean-machine/provider operational release gates remain open.

Primary distribution references: [RPCS3 ARM64 releases](https://github.com/RPCS3/rpcs3-binaries-mac-arm64/releases), [Azahar macOS instructions](https://github.com/azahar-emu/azahar), [PPSSPP macOS instructions](https://www.ppsspp.org/docs/reference/mac/), [Dolphin downloads](https://dolphin-emu.org/download/), [Eden](https://eden-emu.dev/get-started/), [Beetle Saturn system resources](https://docs.libretro.com/library/beetle_saturn/). The complete source/distribution definitions are in `Sources/AkitoStationCore/RuntimeCatalog.swift`.
