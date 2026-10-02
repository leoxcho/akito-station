# Support matrix — implementation is not gameplay certification

The authoritative September 30 assessment lists the console paths below. Remediation fixture tests cover native registration, ABI/policy and rollback logic; none certify a real game for every console. No current physical-controller, audio/save/gameplay, clean-machine or live upstream install acceptance was performed.

B = optional source build Requires Developer Tools; G = official GitHub release, automatic bounded ZIP only; M = official manual download/import. All listed paths have source implementation.

| Console | Catalog emulator choices | Advertised route | Install | Import | Launch | Real game | Audio | Controller | Save | Update | Clean machine |
|---|---|---|---|---|---|---|---|---|---|---|
| NES | Nestopia core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| SNES | Snes9x core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Game Boy | Gambatte, mGBA cores | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Game Boy Color | Gambatte, mGBA cores | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Game Boy Advance | mGBA core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Mega Drive | Genesis Plus GX core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PC Engine | Beetle PCE Fast core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Nintendo 64 | ParaLLEl N64 core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Nintendo DS | melonDS DS core | B | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Nintendo 3DS | Azahar; Lime3DS existing | G / M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PlayStation | PCSX ReARMed core; DuckStation | B / M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PlayStation 2 | PCSX2; ARMSX2 | G / M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PlayStation 3 | RPCS3 | G | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PlayStation 4 | shadPS4 | G | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PSP | PPSSPP core / desktop | B / M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| PS Vita | Vita3K | G | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| GameCube | Dolphin desktop; existing Akito adapter | M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Wii | Dolphin desktop; existing Akito adapter | M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Wii U | Cemu | G | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Xbox | xemu | G | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Xbox 360 | Xenia existing macOS port | M, compatible port required | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Dreamcast | Flycast | G | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Saturn | Beetle Saturn core | M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |
| Switch | Eden; Ryujinx existing | M | Untested current real upstream | Fixture only; real upstream untested | Fixture/adapter only | Untested | Untested | Untested | Untested | Fixture only | Untested |

## Known limitations

- Source-build early-console cores require Developer Tools; compatible prebuilt core import is the clean-user alternative and still needs upstream acceptance.
- Desktop handoff opens the selected emulator window; it is not embedded playable rendering.
- Dolphin Akito adapter requires a compatible existing adapter; standard Dolphin uses the desktop catalog path.
- Xenia needs an independently supplied compatible macOS port, not a claimed supported upstream macOS installer.
- Ryujinx/Eden/Lime3DS/Vita3K support depends on actual supplied version/adapter; registration is not game certification.
- Required firmware/BIOS/keys are user supplied; no such resources or emulators are bundled.
- Automatic ZIP import rejects symlinks/ZIP64/encrypted/multipart archives. Use official manual extraction/import for legitimate incompatible formats.
- Existing historical test reports may help choose representative tests but are not current-run PASS evidence.

For release fill each evidence cell with exact emulator version, install source/hash, macOS/Mac, test date and evidence file. Use Documentation/RELEASE_ACCEPTANCE.md.
