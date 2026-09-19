# MeshNotes Project TODO & Roadmap

> [!IMPORTANT]
> **Task Tracking Rules:**
> - **Planned Items**: Represented as unchecked checkboxes: `- [ ]`
> - **Completed Items**: Represented as checked checkboxes: `- [x]`
> - Every time a feature is implemented or an optimization is completed, mark its checkbox as checked.
> - Any new optimization suggestions or future requirements identified during development must be added to this document as unchecked items.

---

## 1. P2P Sync & Network Layer (packages/libp2p & lib/net)
- [x] **Same-Endpoint UDP Reconnect**: Distinguish duplicate connects from new source IDs, retire stale peers before replacement, and reject old-session handshake packets; cover reconnect and cleanup with loopback UDP regression tests.
- [ ] **Mobile Reconnect Smoke Test**: On a real phone, disconnect/reopen on the same UDP endpoint before heartbeat expiry and verify reconnect plus sync (manual validation by user).
- [x] **Relay Server Node-to-Node Sync**: Implement `publishAppType` handling to broadcast and relay document version updates among peer nodes.
- [x] **Relay Server Query Resolution**: Implement `queryAppType` handling to reply to client queries for missing version trees or version data.
- [ ] **Relay Publish Forward Deduplication**: Before re-enabling relay server publish forwarding, record which `latest_version` announcements have already been forwarded to avoid relay storms.
- [ ] **Overlay Node Bootstrapping (Sponsors)**: Expose command-line flags or YAML configurations to specify sponsor/bootstrapping nodes for standalone relay servers.
- [ ] **Network Transmission Performance**: Refactor P2P message broadcast in `application_layer.dart` to support targeted unicast instead of user-wide broadcast.
- [ ] **Graceful Node Termination**: Complete the termination listener in P2P isolate (`net_isolate.dart`) and ensure clean release of UDP socket and SQLite DB resources.
- [ ] **Heartbeat Test Callback**: Fix the pre-existing `heartbeat_test.dart` timeout: heartbeat failure calls `onConnectionFail`, but `Disconnect while heartbeat timeout 5 times` waits for `onDisconnect` (also reproduced at `877cf5a`).
- [ ] **Keep-Alive and Peer Health Checks**: Maintain connection health with at least one active peer node.
- [x] **Network Sliding Windows Expansion**: Increased `initialSendingWindow` and `initialReceivingWindow` from 64 to 256 to allow larger in-flight payloads.
- [x] **Time Cost Statistics**: Added isolate-to-application roundtrip time monitoring (`TimeCostStatistics`) for latency analysis.
- [x] **Allow sending data to public server**: Added setting to allow sending data to public servers (nodes with different public keys) and filter outgoing business sync data when the option is disabled.
- [ ] **Optional Cross-Public-Key App Storage**: Add an explicit app-side option for P2P-style mode where an app may store data signed by other public keys; default should remain saving only the current user's data.
- [x] **Version Required Object Manifest Cache**: Persist each version's required object list as a local database text manifest so `SendVersions` can read dependencies without recalculating doc/block traversal.
- [x] **Staged Missing-Object Expansion**: `_findWaitingOrMissingVersions` no longer skips a version already in `_missingObjects`. After the version JSON arrives it expands document/block hashes instead of merging with an incomplete object set. Already-arrived hashes are dropped by `_removeAvailableObjectsFromMissingObjects`.
- [ ] **Relay Server Version List Request**: After sending a version tree to a standalone server, add a server-specific request/manifest so the server can know all version hashes it should hold without decrypting user data; do not add this extra payload for same-user devices that already have the key, because the data may be large.


## 2. Standalone Relay Server CLI (packages/server)
- [ ] **WAL (Write-Ahead Logging) Mode**: Enable SQLite WAL mode in `ServerDbHelper` to prevent database locking during high-concurrency client updates.
- [ ] **Graceful Shutdown Hook**: Add shutdown signal hooks (SIGINT, SIGTERM) to safely close sqlite databases and clean up network ports.
- [ ] **Integration Tests**: Replace mock tests in `packages/server/test/server_test.dart` with automated P2P sync and DB assertion test cases.
- [x] **Key Generation & Persistence**: Support key-pair generation (`--gen-key`) and local configuration storage in `server_config.yaml`.
- [x] **CLI Flag Parsing**: Add arguments for `--port`, `--dir`, and `--help`.
- [x] **Standalone DB Configuration**: Decouple database setup from Flutter-specific path providers to support raw Dart CLI environments.

## 3. Editor & UI (lib/mindeditor & lib/page)
- [ ] **High-Performance Long-Document Rendering**: Optimize layout and paint operations of `MindEditField` to support smooth scrolling for documents exceeding 1000 blocks.
- [ ] **Version History Loading**: Complete `doc_utils.dart` to support loading historic document states directly via version hash.
- [ ] **Conflict Resolution UI**: Enhance user interface cues when multi-user editing conflicts arise (merge conflict indicators/actions).
- [ ] **Format Change Event Tracing**: Streamline change events even for null formatting state selections.
- [x] **Visual Drag-and-Drop Feedback**: Implemented visual feedback and dashed outlines for block drag-and-drop operations in editor.
- [x] **Mobile Magnifier**: Supported mobile magnifier feature for dragging selection handles in `SelectionHandleLayer`.

## 4. Multi-Platform Support
- [x] **macOS DMG Packaging and Notarization**: Added a single release script that builds with FVM, signs the app and DMG, submits through Apple's `notarytool`, staples the ticket, and reads credentials only from a gitignored env file.
- [ ] **Multi-Window Sync**: Verify real-time database reactivity and UI refresh when editing the same document in multi-window environments.
- [x] **iPad OS 26+ Multitasking Layout Inset Validation**: Implemented Stage Manager/iPad windowed multitasking padding offset fallback adjustments.
- [x] **Android Release Build Hang Fix**: Injected a `flutter` extension into plugin subprojects in `android/build.gradle` so plugins built for Flutter 3.27+ (`record_android` 1.5.2, ...) can read `flutter.compileSdkVersion` under Flutter 3.24.
- [x] **Google Play targetSdk 36**: Raised `compileSdk`/`targetSdk` from 35 to 36 in `android/app/build.gradle` and the plugin `flutter` shim in `android/build.gradle` so Play Console accepts app updates after 2026-08-31.
- [x] **Google Play 16 KB page sizes**: Upgraded to Flutter 3.35.2, AGP 8.9.1, Gradle 8.11.1, NDK r28 (`28.2.13676358`), and `sqlite3_flutter_libs` 0.5.39 so 64-bit `.so` files are 16 KB ELF-aligned. Release APK verified with `llvm-objdump` (`align 2**14+`) and `zipalign -c -P 16`.
- [x] **libmp_audio_stream.so NDK r21**: Play flagged `base/lib/arm64-v8a/libmp_audio_stream.so`. The plugin pins NDK 21.1.6352462; `android/build.gradle` now overrides every Android module to NDK r28 so that library is rebuilt with a 16 KB-compliant linker.
- [ ] **Replace mp_audio_stream with flutter_sound**: The NDK r28 override for `mp_audio_stream` 0.2.2 is a Play-compliance workaround, not a maintained fix. Swap realtime PCM playback in `NativeAudioPlayerProxyImpl` (`lib/plugin/ai/realtime_chat/native_ws_implement/audio_player_proxy.dart`, 24 kHz mono) to `flutter_sound`, then drop `mp_audio_stream` and the Gradle NDK override for that plugin.
- [ ] **Android 16 targetSdk 36 smoke test**: Before the Play production update, test camera, microphone, WebRTC, LAN discovery, and edge-to-edge layout on an Android 16 device or emulator.
- [x] **iOS 27 UIScene launch**: Xcode 27 / iOS 27 SDK refuse apps without a scene lifecycle. Added `UIApplicationSceneManifest` and `SceneDelegate` so debug can leave the splash and release no longer exits immediately. Remaining: adopt `FlutterImplicitEngineDelegate` when FVM moves to 3.38+.
- [x] **Flutter SDK Upgrade (3.35.2)**: Pinned fvm to 3.35.2. Plugin projects now get the `flutter` extension natively; the shim in `android/build.gradle` stays as a skipped safety net (`findByName("flutter") != null`).
- [x] **Kotlin Incremental Cache on Windows**: Kotlin 2.1 fails the release build when pub cache is on `C:` and the project is on `E:`. Workaround: `kotlin.incremental=false` in `android/gradle.properties`. Still consider relocating `PUB_CACHE` onto the same drive to restore incremental compiles.
