# Mesh Notes - Architecture Overview

## Overview

Mesh Notes is a cross-platform Flutter note-taking app that follows a Local-First design and supports P2P sync. Core traits:

- **Offline-first**: all data stored locally, no cloud service needed
- **P2P sync**: devices sync directly without a central server
- **Real-time collaboration**: conflict resolution via version chains
- **End-to-end encryption**: encrypted storage and transport
- **Cross-platform**: Windows, macOS, Linux, iOS, and Android

## Project Structure

```
meshnotes/
├── lib/
│   ├── main.dart                    # App entry
│   ├── init.dart                    # Initialization logic
│   ├── mindeditor/                  # Core editor module
│   │   ├── controller/              # Global controller and state
│   │   ├── document/                # Document model and collaboration
│   │   ├── view/                    # UI components and rendering
│   │   ├── setting/                 # Config and constants
│   │   └── user/                    # User auth
│   ├── net/                         # Network layer proxy
│   ├── page/                        # UI pages
│   ├── plugin/                      # Plugin system
│   ├── tasks/                       # Event-driven task framework
│   └── util/                        # Utilities
└── packages/                        # Local packages
    ├── libp2p/                      # P2P networking
    ├── keygen/                      # Crypto and signing
    └── my_log/                      # Logging framework
```

## Core Modules

### 1. Controller layer

**Location**: [lib/mindeditor/controller/controller.dart](../lib/mindeditor/controller/controller.dart)

Global singleton controller that manages core state and features:

```dart
class Controller {
  static final Controller _instance = Controller._internal();

  DocumentManager docManager;       // Document management
  NetworkController network;        // Network control
  PluginManager pluginManager;      // Plugin management
  SelectionController selection;    // Selection control
  GestureHandler gestures;          // Gesture handling
  EvenTasksManager evenTasks;       // Task management
}
```

**Responsibilities**:
- Coordinate subsystems
- Manage app lifecycle
- Provide unified APIs

### 2. DocumentManager

**Location**: [lib/mindeditor/document/document_manager.dart](../lib/mindeditor/document/document_manager.dart)

Handles document lifecycle, versioning, and sync.

**Key capabilities**:
- Create/open/save/delete documents
- Build and manage the version tree
- Maintain document hierarchy
- Work with the database layer
- Trigger network sync

**Key methods**:
- `openDocument(String docId)`: open a document
- `genNewVersionTree()`: generate a new version
- `mergeVersionTree()`: merge remote versions
- `moveDocument()`: move a document (new)

### 3. NetworkController

**Location**: [lib/net/net_isolate.dart](../lib/net/net_isolate.dart)

The network stack runs in an isolated Isolate and communicates with the main thread via messages:

```dart
void netIsolateRunner(IsolateData data) {
  final villager = VersionChainVillager(sendPort: data.sendPort);
  villager.start();
}
```

**Isolation advantages**:
- Keep the UI thread unblocked
- Run networking and crypto in the background
- Higher security (keys in separate memory space)

### 4. PluginManager

**Location**: [lib/plugin/plugin_manager.dart](../lib/plugin/plugin_manager.dart)

Extensible plugin system supporting editor plugins and global plugins:

```dart
class PluginManager {
  // Editor plugins (toolbar buttons)
  Map<PluginProxy, EditorPluginRegisterInformation> _editorPluginInstances;

  // Global plugins (floating buttons)
  Map<PluginProxy, GlobalPluginRegisterInformation> _globalPluginInstances;
}
```

**Current plugins**:
- AI text assistant
- Real-time voice chat
- Auto suggestions

## Data Flow

### User input flow

```
User input
  ↓
GestureHandler
  ↓
MindEditBlock
  ↓
ParagraphDesc
  ↓
Document
  ↓
DocumentManager (mark dirty)
  ↓
Timer fires
  ↓
genNewVersionTree (build version)
  ↓
NetworkIsolate (send to network)
```

### Network sync flow

```
Remote node
  ↓
NetworkIsolate (receive)
  ↓
VersionChainVillager (decrypt + verify)
  ↓
SendPort (to main thread)
  ↓
DocumentManager (handle commands)
  ↓
Merge task queue
  ↓
Merge when idle
  ↓
Update local database
  ↓
UI refresh (CallbackRegistry)
```

## State Management

### CallbackRegistry pattern

**Location**: [lib/mindeditor/controller/callback_registry.dart](../lib/mindeditor/controller/callback_registry.dart)

Observer pattern to dispatch state changes:

```dart
class CallbackRegistry {
  static void registerDocumentChangedWatcher(String key, Function callback);
  static void triggerDocumentChangedEvent();

  static void registerNetworkStatusWatcher(Function callback);
  static void triggerNetworkStatusChanged();

  static void registerBlockContentChangeEventListener(Function callback);
  static void triggerBlockChangedEvent(BlockChangedEventData data);
}
```

**Used for**:
- Document list updates
- Network status changes
- Block content changes (AI listeners)
- Sync status updates

### State persistence

All state is persisted in SQLite.

**Location**: [lib/mindeditor/document/dal/db_helper.dart](../lib/mindeditor/document/dal/db_helper.dart)

**Core tables**:
- `documents`: metadata (title, timestamp, parent, etc.)
- `blocks`: block content (rich text, type, list style, etc.)
- `versions`: version DAG (parents, timestamp, hash)
- `objects`: content-addressed storage (hash → content)

## Design Patterns

### 1. Singleton
- `Controller`: global controller
- `DocumentManager`: document manager
- `Environment`: environment detection

### 2. Factory
- `PacketFactory`: network packet builder
- `Document.loadByNode`: document loading

### 3. Observer
- `CallbackRegistry`: event dispatch
- Plugin event listeners

### 4. Proxy
- `PluginProxy`: plugin API proxy
- `NetworkController`: network isolation proxy

### 5. Strategy
- LLM providers (OpenAI, Kimi, DeepSeek, etc.)
- Platform-specific implementations (device ID retrieval)

### 6. Command
- Network message commands
- UI event tasks

## Key Algorithms

### 1. Text diff detection

**Location**: [lib/mindeditor/view/mind_edit_field.dart](../lib/mindeditor/view/mind_edit_field.dart)

```dart
// Find common prefix
var leftCommonCount = findLeftDifferent(oldText, newText, cursor);

// Find common suffix
var rightCount = findRightDifferent(oldText, newText, cursor);

// Determine change range
var changeFrom = leftCommonCount;
var changeTo = oldText.length - rightCount;
```

### 2. Version merge

**Location**: [lib/mindeditor/document/collaborate/version_merge_manager.dart](../lib/mindeditor/document/collaborate/version_merge_manager.dart)

**Three-way merge**:
1. Find common ancestor
2. Build operation lists for both branches
3. Detect conflicts (conflicting ops on the same object)
4. Apply operations and resolve conflicts
5. Generate new version

### 3. Content addressing

Use SHA256 hash as the unique content ID:
- Deduplicate storage (store identical content once)
- Integrity verification
- Version comparison

### 4. Tree operations

Document tree uses doubly linked list + parent/child relations:
- Fast insert/delete
- Preserve order
- Support hierarchy moves

## Performance Optimization

### 1. Isolate separation
- Network runs in its own thread
- Crypto avoids blocking the UI
- Message passing instead of shared memory

### 2. Viewport culling
- Render only visible blocks
- Track `activeBlockId` for the current block
- Lazy-load history versions

### 3. Content addressing
- Incremental sync (send only changed objects)
- Deduplicated storage saves space
- Hash comparison quickly determines updates

### 4. Database indexing
- Index on doc ID, hash, and timestamp
- Fast queries and filtering

## Security Design

### 1. End-to-end encryption
- Symmetric encryption (AES)
- Asymmetric signatures (Ed25519)
- Every message is signed

### 2. Authentication
- Public key as user ID
- Private key signatures prove identity
- No central auth server

### 3. Isolated execution
- Keys live in the network Isolate
- Main thread cannot access private keys directly
- Reduces leakage risk

## Extensibility

### 1. Plugin system
- Standardized plugin interfaces
- Editor plugins and global plugins separated
- Access core features via `PluginProxy`

### 2. Protocol versioning
- Network protocol carries a version number
- Backward compatible with older versions
- Gradual upgrades

### 3. Modular design
- Reusable packages under `packages/`
- `libp2p` as a general P2P library
- `keygen` as a general crypto library

## Development Notes

### 1. Changing document structure
When modifying `ParagraphDesc` or `Document`:
- Update database schema
- Update version serialization/deserialization
- Consider backward compatibility

### 2. Adding a new plugin
1. Create a `PluginInstance` implementation
2. Register it in `PluginManager`
3. Use `PluginProxy` to access editor features
4. Listen for events or expose UI entry points

### 3. Changing the network protocol
1. Update `PacketType` or message structures
2. Update both serialization and deserialization
3. Bump protocol version
4. Test compatibility with older versions

### 4. Performance tuning
- Use Flutter DevTools for profiling
- Track `build()` call counts
- Avoid heavy computation on the UI thread
- Prefer `const` constructors

## Tech Stack

- **Flutter**: 3.24.0+
- **Dart**: 3.5.0+
- **Database**: SQLite3
- **Network**: UDP + custom protocol
- **Crypto**: Ed25519 (signature) + AES (encryption)
- **Service discovery**: mDNS/Bonjour
- **AI**: OpenAI-compatible API

## Roadmap

1. **Collaboration**
   - Real-time cursor presence
   - Online status for collaborators
   - Conflict visualization

2. **Feature expansion**
   - Image and attachment support
   - Markdown import/export
   - Theme customization

3. **Performance**
   - Virtual scrolling optimizations
   - Incremental rendering
   - Smarter sync strategies

4. **Security**
   - Key backup and recovery
   - Device management
   - Access control
