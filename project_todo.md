# MeshNotes Project TODO & Roadmap

> [!IMPORTANT]
> **Task Tracking Rules:**
> - **Planned Items**: Represented as unchecked checkboxes: `- [ ]`
> - **Completed Items**: Represented as checked checkboxes: `- [x]`
> - Every time a feature is implemented or an optimization is completed, mark its checkbox as checked.
> - Any new optimization suggestions or future requirements identified during development must be added to this document as unchecked items.

---

## 1. P2P Sync & Network Layer (packages/libp2p & lib/net)
- [x] **Relay Server Node-to-Node Sync**: Implement `publishAppType` handling to broadcast and relay document version updates among peer nodes.
- [x] **Relay Server Query Resolution**: Implement `queryAppType` handling to reply to client queries for missing version trees or version data.
- [ ] **Relay Publish Forward Deduplication**: Before re-enabling relay server publish forwarding, record which `latest_version` announcements have already been forwarded to avoid relay storms.
- [ ] **Overlay Node Bootstrapping (Sponsors)**: Expose command-line flags or YAML configurations to specify sponsor/bootstrapping nodes for standalone relay servers.
- [ ] **Network Transmission Performance**: Refactor P2P message broadcast in `application_layer.dart` to support targeted unicast instead of user-wide broadcast.
- [ ] **Graceful Node Termination**: Complete the termination listener in P2P isolate (`net_isolate.dart`) and ensure clean release of UDP socket and SQLite DB resources.
- [ ] **Keep-Alive and Peer Health Checks**: Maintain connection health with at least one active peer node.
- [x] **Network Sliding Windows Expansion**: Increased `initialSendingWindow` and `initialReceivingWindow` from 64 to 256 to allow larger in-flight payloads.
- [x] **Time Cost Statistics**: Added isolate-to-application roundtrip time monitoring (`TimeCostStatistics`) for latency analysis.
- [x] **Allow sending data to public server**: Added setting to allow sending data to public servers (nodes with different public keys) and filter outgoing business sync data when the option is disabled.
- [ ] **Optional Cross-Public-Key App Storage**: Add an explicit app-side option for P2P-style mode where an app may store data signed by other public keys; default should remain saving only the current user's data.
- [ ] **Relay Server Sync Manifest**: Add a signed, server-readable manifest for version trees so standalone servers without user decryption keys can know every version/content object ID that must be stored and verify download completeness.

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
- [ ] **Multi-Window Sync**: Verify real-time database reactivity and UI refresh when editing the same document in multi-window environments.
- [x] **iPad OS 26+ Multitasking Layout Inset Validation**: Implemented Stage Manager/iPad windowed multitasking padding offset fallback adjustments.
