# Local Windows / Ubuntu WSL build

This project includes a SwiftPM library product and xtool configuration for building an iPhone app from Linux. This route has not yet been compiled on this machine. Xcode-based simulator tests remain available through project.yml; xtool builds the device app and does not provide an iOS simulator on Linux.

## Check Ubuntu

In your Ubuntu terminal:

```bash
swift --version
command -v xtool
```

The current xtool installation instructions require Swift 6.4. Follow https://www.swift.org/install/linux/ for your Ubuntu version if Swift is missing.

## Apple SDK and signing

Download the Xcode version specified by the current xtool instructions from https://developer.apple.com/download/all/?q=Xcode in your browser. Sign in to Apple and accept the download agreement yourself. xtool extracts the iOS SDK from this archive; it does not run Xcode on Windows.

Follow https://xtool.sh/documentation/xtool/installation-linux/ to install xtool and run `xtool setup`. Complete Apple authentication and two-factor prompts yourself, and supply the Xcode archive path when asked. A Windows Downloads archive is accessible in WSL under `/mnt/c/Users/Deano/Downloads/`. Do not paste Apple passwords or verification codes into chat.

## Build

After Swift, xtool, and the iOS SDK are configured, use a Linux filesystem checkout:

```bash
git clone https://github.com/fomoco460/GoogleTVRemote.git
cd GoogleTVRemote
xtool dev
```

xtool handles building and signing, then attempts to deploy to a connected iPhone. WSL needs device access configured for direct deployment; the xtool installation instructions link to Microsoft's USB passthrough setup. We can use a separate Windows sideloading tool if direct WSL deployment proves awkward. An Apple ID is still needed for signing; GitHub billing is not involved.

Reference: https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md
