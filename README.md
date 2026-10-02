# Akito Station

Akito Station is a native macOS emulator frontend for organizing a game library and selecting compatible, separately installed runtimes. This repository contains the Public edition.

![Akito Station library showing a user-supplied game collection](Documentation/Images/akito-station-library.png)

*Illustrative library screenshot supplied by the project owner. The pictured branding/theme differs from the plain system-style views in the rights-clean Public release. Game artwork belongs to its respective owners; games and artwork shown are not bundled with Akito Station.*

Requires macOS 14 or later and Xcode command-line tools with Swift 5.9 or later. Development and local validation target Apple Silicon (arm64); Intel compatibility has not been verified.

Akito Station ships no ROMs or games, console BIOS, firmware, console keys, or emulator runtime binaries. Supply content you are authorized to use. Optional runtimes are selected, imported or installed separately; compatibility depends on the runtime and console. External application launch does not establish embedded gameplay support.

## Build and test

```sh
swift build --build-system native --scratch-path /tmp/akito-public-build
swift test --build-system native --scratch-path /tmp/akito-public-build
```

Package.swift is the authoritative build entry point; no Xcode project is required. Open this directory as a Swift package in Xcode. Public is the only supported edition in this export. The scripts under Scripts provide runtime management and optional app packaging. Scripts/build.sh creates a local Build app and performs local signing; the commands above compile/test source without app packaging or signing. Do not treat a local package as a signed release.

## Use

After building an app, open it, import your own supported game files, select the platform and configure an appropriate runtime. Supply required firmware or keys yourself through the relevant settings. Install or relink external runtimes using the runtime controls; select the runtime explicitly where multiple choices exist. Keep backups of saves and original content.

## Status and limitations

This is a pre-publication source export. Original Akito Station code is Apache-2.0; upstream material retains its own terms and unverified artwork/patch/derived material is excluded; see Documentation/SOURCE_PUBLICATION.md and Documentation/LICENSING_INVENTORY.json. See LICENSE_SCOPE.json for exact file scope. Plain system-style views replace excluded branding and illustrations; source adapter builds are unavailable. Console support varies; passing source tests does not verify every runtime, game, controller or save workflow. No emulator runtime is approved for bundling by this export.

Payment and PRO integration code is experimental. Its complete production purchase, fulfillment, restore and account journey has not been verified. It is not advertised as production-ready.

Backend source is included directly under Backend without repository metadata. It is a reference service, deployed separately and never required for compilation. Copy Backend/.env.example into a private service environment and configure it there; every template value is empty. Never commit credentials or payment databases.

Use repository issues for support. Do not submit sensitive information publicly; private security contact is not yet configured. See SECURITY.md before reporting sensitive information.
