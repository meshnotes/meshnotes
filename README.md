# Mesh Notes
## Overview

Mesh Notes is an open source cross-platform note application built by flutter.
- Local first, no cloud service
- Never charged, no ads forever
- Synchronizing between devices

The goal is to build an note application that is not controlled by any company, and synchronizing data between my own devices.
So there are two principles:
1. Keep this project small and simple, in order to ensure it could be developed and maintained by a single individual or a part-time small team. No need for an entire team of full-time staffs.
2. Reduce the dependence on servers to avoid excessive costs, so P2P technology is the first choice.

Currently supports Windows, macOS, Linux, iOS, iPad, Android platforms.


## Building and testing environment
Build and test in Flutter 3.19.6 stable, with Dart 3.3.4.
Xcode 15.1
Visual Studio 2019

## How to setup environment and run it
1. Install rust, the super_clipboard package needs it. Please refer to [super_clipboard](https://pub.dev/packages/super_clipboard)
2. Run the pre_build.sh first, to create icons
3. Run flutter run -d <your device> to run and debug
4. Run flutter run -d <your device> --release to run it in release mode
5. Run flutter build <macos/windows> --release to build it in release mode

# Source code structure
## Source code for mesh notes
## Source code for libp2p