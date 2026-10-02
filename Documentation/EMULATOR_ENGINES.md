# Emulator engine selection

Every console is listed in Settings > Emulator Settings and has an Emulator engine control. Engine selections are saved per console and used by launch routing. Installed managed versions can be activated from the same panel; activation verifies the manifest and binary hash. Shared engines share the selected version. Game version pins remain overrides for the same engine.

PS1 and PSP retain their existing alternate adapters. Additional software libretro engines can be discovered from installed runtime manifests with an explicit `platforms` array of Platform raw values (for example `["nes"]`), `validated: true`, and both `libretro` and `softwareVideo` capabilities. These declarations supplement the existing integration-validation process; they are not proof of gameplay compatibility. Hardware-only cores and arbitrary desktop applications require dedicated adapters.

Vita, Switch and PS4 retain their installed Vita3K, Eden and shadPS4 application routes. Their engine controls identify that integration; alternate desktop engines are not implemented. Dreamcast and Saturn show no compatible engine until one is installed with the required integration metadata. This change does not install or validate new emulator engines.
