# Overview

This file provides guidance to AI coding agents when working with this repository.

## Project Overview

Mesh Notes is a cross-platform Flutter note-taking app with P2P synchronization. No cloud required. Supports Windows, macOS, Linux, iOS, iPad, and Android.

## Quick Commands

```bash
flutter pub get              # Install dependencies
flutter run -d <device>      # Run debug
flutter build <platform>     # Build release
flutter analyze              # Static analysis
flutter test                 # Run tests
```

## Architecture Summary

**Main App (`lib/`)**
- `mindeditor/` - Editor (controller, document, view, setting)
- `net/` - P2P network (runs in isolate)
- `page/` - UI pages
- `plugin/` - Plugin system (AI)
- `tasks/` - Event framework

**Packages (`packages/`)**
- `libp2p/` - P2P networking (UDP-based)
- `keygen/` - Encryption/signing (Ed25519, AES)
- `my_log/` - Logging

**Key Patterns**
- Version-based conflict resolution (DAG)
- Multi-layer UI rendering (no overlays)
- Network isolation (separate isolate)
- Plugin architecture

## Database

SQLite3 with tables: `documents`, `blocks`, `versions`, `objects`, `conflicts`

## Development

- Flutter 3.24.0+, Dart 3.5.0+
- Run tests: `flutter test` + `flutter test packages/*/test/`

## Documentation

**CRITICAL: Update documentation when changing code!**

See [documentation/README.md](documentation/README.md) for full docs.

| Change Type | Update File |
|------------|-------------|
| Architecture/modules | `documentation/01-architecture.md` |
| UI/pages/widgets | `documentation/02-ui-interface.md` |
| Network protocol | `documentation/03-network-protocol.md` |
| Platform code | `documentation/04-platform-specific.md` |
| Editor features | `documentation/05-editor.md` |
| Sync/collaboration | `documentation/06-p2p-sync.md` |
| Plugins/AI | `documentation/07-ai-plugin.md` |

**Rules**: Update immediately • Include file paths • Explain WHY • Keep examples synced
