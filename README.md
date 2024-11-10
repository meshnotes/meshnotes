# Mesh Notes
## Overview

Mesh Notes is an open source cross-platform note application built by flutter.
- Local first, no cloud service
- Never charged, no ads forever
- Synchronizing between devices

My goal is to build an note application that is not controlled by any company, and synchronizing data between my own devices.
So there are two principles:
1. Keep this project small and simple, in order to ensure it could be developed and maintained by a single individual or a part-time small team. No need for an entire team of full-time staffs.
2. Reduce the dependence on servers to avoid excessive costs, so P2P technology is the first choice.

Currently supports Windows, macOS, Linux, iOS, iPad, Android platforms.

## How to synchronize data(even without cloud service)?
There are several ways to synchronize data:
1. Using LAN broadcast, find peers in the same network, and synchronize data between peers with the same user key.
2. Set the upstream IP:port manually.
Both these two ways you need to run mesh notes on both devices. But by the third way, that's not necessary.
3. Using a server to synchronize data between devices. But the server runs like a tracker in BT, it won't store data permanently. The data is safe only when stored in your devices.

## Building and testing environment
Build and test in Flutter 3.22.0 stable, with Dart 3.4.0.
For mac: Cursor 0.42.3 + Xcode 15.1
For windows: Visual Studio 2022

## How to setup environment and run it
1. Install rust, the super_clipboard package needs it. Please refer to [package super_clipboard](https://pub.dev/packages/super_clipboard)
2. Run the `pre_build.sh` first, to create icons
3. Run flutter `run -d <your device>` to run and debug
4. Run flutter `run -d <your device> --release` to run it in release mode
5. Run flutter `build <macos/windows> --release` to build it in release mode

# Using Mesh Notes
Mesh Notes is a note application, I use it to write down light-weight text contents, like my reading notes, my memo, my idea about anything.
It supports synchronizing data between your own devices. Currently only when your devices are all connected to your LAN environment. The Internet P2P synchronizing will be supported in the future.

## Before using it
It's strongly recommended that you create your own key before using it. Although you may select "Just want to try it". But the synchronizing feature requires a public-private key pair.

## How to synchronize data between devices
Currently only supports synchronizing data in Local Area Network(LAN).
1. Using local multicasting
Connect your devices into the same WIFI or the same LAN Switch, launch Mesh Notes, wait for a minute, they will synchronize data automatically, no configuration is required.
2. Set the server IP
The first way may not work, since some WIFI router may disable the local multicast. Use one of your devices as the server(you'll need to set it as fixed IP, let's say 192.168.1.100), and set other devices' server IP and port to be 192.168.1.100:17974(17974 is the default port). Launch Mesh Notes on your devices, they will synchronize data in a minute.
3. Synchronizing anywhere
Not supported yet, but this feature is in the plan.
In the previous two ways, your data is saved on your own devices

# Source code structure
There are 5 parts of code:
1. mesh notes, main code in this project, in lib/ directory.
2. libp2p, the P2P library, in the sub-directory packages/libp2p/.
3. keygen, encapsulation of the encryption and signing library, in the sub-directory packages/keygen/.
4. my_logger, a simple logger, in the sub-directory packages/my_logger/.(Yes, bad naming)
5. server, can be run without GUI, like a running shell of libp2p, not implemented yet. In the sub-directory packages/server/.

## Source code for mesh notes
- mindeditor/: main code for mesh notes
  - mindeditor/controller/: some functions need to be invoked in any other modules, are encapsulated in this directory.
  - mindeditor/document/: document related logic, model, and database layer
  - mindeditor/setting/: define constants and implementation of dynamic settings.
  - mindeditor/view/: UI widgets, including toolbar, edit field, paragraph block, etc.
- net/: network proxy, its job is to spawn a new isolate, and run libp2p in the new isolate.
- page/: UI page widgets, such as login, navigation, title bar, etc.
- plugin/: plugin manager and proxy, extended feature(like AI assistant, etc.) will be implemented in the form of plugin(but I don't know how to dynamically load dart code yet)
- tasks/: a framework to run periodic tasks, event triggered tasks, not implemented yet

## Source code for libp2p
- network/: the bottom layer of libp2p, implements the underlying protocol based on UDP.
- overlay/: the overlay layer manage the topologic of peers, based on the network layer.
- application/: the top layer of libp2p, implements the "chain of version" protocol.

## Source code for plugins

## Proposal for ROP(Reader Oriented Programming)

# Documentation for implementation details
[Screen layers for UI elements](./documentation/layers.md "Layers")

