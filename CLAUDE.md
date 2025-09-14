# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mesh Notes is a cross-platform Flutter note-taking application built for local-first collaboration. It features P2P synchronization between devices without requiring cloud services, supporting Windows, macOS, Linux, iOS, iPad, and Android platforms.

## Development Commands

### Basic Flutter Commands
- `flutter pub get` - Install/update dependencies
- `flutter run -d <device>` - Run in debug mode
- `flutter run -d <device> --release` - Run in release mode
- `flutter build <platform> --release` - Build for production
- `flutter analyze` - Run static analysis
- `flutter test` - Run unit tests

### Icon and Splash Management
- `dart run flutter_launcher_icons` - Generate app icons
- `dart run flutter_native_splash:create` - Generate splash screens
- Configuration files: `pubspec.yaml` (icons) and `flutter_native_splash.yaml` (splash)

### Testing
- Main app tests: `test/` directory
- Package tests: `packages/*/test/` directories
- Run specific tests: `flutter test test/specific_test.dart`

## Architecture Overview

### Core Modules

**Main Application (`lib/`)**
- `mindeditor/` - Core note editing functionality
  - `controller/` - Global controllers and callback registry
  - `document/` - Document model, database layer, and collaboration logic
  - `view/` - UI components including toolbar, edit field, and layered rendering
  - `setting/` - Configuration constants and dynamic settings
- `net/` - Network layer proxy that spawns isolates for P2P communication
- `page/` - UI pages (login, navigation, settings, etc.)
- `plugin/` - Plugin system including AI assistant
- `tasks/` - Event-driven task framework
- `util/` - Shared utilities

**Local Packages (`packages/`)**
- `libp2p/` - P2P networking library with network, overlay, and application layers
- `keygen/` - Encryption and signing utilities
- `my_log/` - Custom logging implementation

### Key Architectural Patterns

**Document Collaboration System**
- Version-based conflict resolution using "chain of version" protocol
- Real-time synchronization through P2P network layer
- Operational transformation for concurrent editing

**UI Layer Architecture**
The app uses a multi-layer rendering system instead of Flutter overlays:
1. Selection layer (bottom) - selection areas and handles
2. Plugin tips layer - AI hints and suggestions
3. Popup menu layer - context menus
4. Plugin dialog layer (top) - modal dialogs

**Network Isolation**
- Main UI runs in primary isolate
- P2P networking runs in separate isolate via `net_isolate.dart`
- Communication through SendPort/ReceivePort messaging

**Plugin System**
- Extensible architecture for features like AI assistant
- Plugin manager handles registration and lifecycle
- Current plugins: AI tools with LLM provider integration

### Database & Storage
- SQLite3 backend via `sqlite3` and `sqlite3_flutter_libs`
- Document data model with DAL (Data Access Layer)
- Local-first with P2P sync, no cloud dependency

### P2P Network Features
- Automatic LAN discovery via Bonjour/mDNS
- Manual IP configuration for direct connections
- UDP-based protocol with overlay topology management
- Encryption and authentication via keygen package

## Development Environment

- Flutter 3.24.0+ with Dart 3.5.0+
- Platform-specific requirements:
  - macOS: Xcode 16.1+
  - Windows: Visual Studio 2022 + NuGet packages
  - Linux: Ubuntu 24.04, Android Studio 2023.1.1+
- IDE: Cursor (preferred)

## Testing Strategy

Comprehensive test coverage across:
- Document collaboration (conflict resolution, merging)
- P2P networking (packet handling, connections)
- Encryption and key management
- UI components and controllers

Run all tests: `flutter test` (main) + `flutter test packages/*/test/` (packages)