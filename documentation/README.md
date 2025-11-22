# Mesh Notes Documentation

Welcome to the Mesh Notes technical docs. This library describes each technical facet of the project.

## 📚 Docs Index

### [01. Architecture](01-architecture.md)
Deep dive into Mesh Notes architecture, core modules, and design patterns.

**Includes**:
- Project structure and module layout
- Core components like Controller, DocumentManager, PluginManager
- Data flow and state management
- CallbackRegistry observer pattern
- Design patterns (singleton, factory, proxy, etc.)
- Performance optimizations

**For**: architects, tech leads, new engineers

---

### [02. UI Interface](02-ui-interface.md)
UI implementation details: page structure, custom widgets, and rendering.

**Includes**:
- App entry and navigation
- DocumentNavigator, DocumentView, etc.
- Multi-layer rendering (selection, tips, menus, dialogs)
- MindEditField and MindEditBlock components
- Drag-and-drop reordering
- Responsive design and platform adaptations
- Themes, styles, animations

**For**: frontend engineers, UI/UX designers

---

### [03. Network Protocol](03-network-protocol.md)
P2P protocol three-layer architecture and communication mechanisms.

**Includes**:
- Stack architecture (network, overlay, application)
- Packet structure/types (Connect, Data, Announce, Bye, etc.)
- Reliability (sequence, keepalive, retransmit)
- Node discovery (mDNS/Bonjour, manual config)
- Message types (Provide, Query, Publish)
- Version sync protocol
- Encryption/signature (Ed25519, AES)
- Network isolation (Isolate)

**For**: network engineers, protocol developers

---

### [04. Platform Specific](04-platform-specific.md)
Adapting for Windows, macOS, Linux, iOS, Android.

**Includes**:
- Platform detection and device identity
- Desktop traits (block handler, mouse cursor, window events)
- Mobile traits (soft keyboard, lifecycle, iOS backspace handling)
- Network adaptation (LAN discovery, permissions)
- Storage adaptation (SQLite, file paths)
- Permissions
- Build configs (Android, iOS, macOS, Windows, Linux)
- Icons and splash

**For**: full-stack, mobile, and desktop engineers

---

### [05. Editor](05-editor.md)
Rich-text editor core implementation and data model.

**Includes**:
- Document and ParagraphDesc data models
- TextDesc rich-text spans
- MindEditField editing area
- TextInputClient keyboard handling
- Text diff algorithm
- RenderMindEditBlock custom rendering
- Selection system (SelectionController, SelectionHandle)
- Gesture handling (tap, double-tap, drag)
- Keyboard shortcuts
- Toolbar implementation

**For**: editor and frontend engineers

---

### [06. P2P Sync](06-p2p-sync.md)
Version chain protocol and conflict resolution.

**Includes**:
- Version chain and DAG
- VersionContent and VersionContentItem structures
- Sync flow (generation, broadcast, request, transfer, receive, merge)
- Three-way merge
- Operation generation (Add, Delete, Move, Modify)
- Conflict detection/resolution
- Operation application
- DB design (documents, blocks, versions, objects, conflicts)
- Performance (incremental sync, batching, dedupe)

**For**: distributed systems and collaboration-tool engineers

---

### [07. AI Plugin](07-ai-plugin.md)
Plugin architecture and AI integration.

**Includes**:
- Plugin architecture (PluginManager, PluginInstance, PluginProxy)
- PluginProxy APIs (read content, modify docs, dialogs, events)
- PluginAI implementation
- AI text assistant (continue, improve, translate, summarize)
- AI auto suggestions (listen to block changes)
- LLM integrations (OpenAI, Kimi, DeepSeek, Qwen)
- AiExecutor
- Real-time voice chat (WebRTC)
- AI settings UI
- Building new plugins

**For**: plugin developers, AI engineers

---

## 🚀 Getting Started

### Onboarding path

1. **Architecture** → [01-architecture.md](01-architecture.md)
   - Understand the overall structure
   - Get familiar with core modules and patterns

2. **UI** → [02-ui-interface.md](02-ui-interface.md)
   - Learn page structure/navigation
   - See custom component implementations

3. **Specialties**:
   - **Frontend** → [05-editor.md](05-editor.md)
   - **Networking** → [03-network-protocol.md](03-network-protocol.md) + [06-p2p-sync.md](06-p2p-sync.md)
   - **Cross-platform** → [04-platform-specific.md](04-platform-specific.md)
   - **AI** → [07-ai-plugin.md](07-ai-plugin.md)

---

## 📝 Doc Maintenance

**Important**: Always update docs when code changes!

### Principles

1. **Incremental updates**: update docs with code changes
2. **Precise references**: include file paths/line numbers when relevant
3. **Synced examples**: keep snippets aligned with implementation
4. **Explain decisions**: capture the "why" not just the "what"
5. **Cross-reference**: link related docs

### Update matrix

| Code change | Update doc |
|-------------|------------|
| New modules, controllers | 01-architecture.md |
| UI components, pages | 02-ui-interface.md |
| Network protocol | 03-network-protocol.md |
| Platform adaptation | 04-platform-specific.md |
| Editor features | 05-editor.md |
| Sync logic | 06-p2p-sync.md |
| Plugins, AI | 07-ai-plugin.md |

See detailed rules in [CLAUDE.md](../CLAUDE.md#documentation).

---

## 🔗 Links

- **Repo**: [GitHub](https://github.com/meshnotes/meshnotes)
- **Issues**: [GitHub Issues](https://github.com/meshnotes/meshnotes/issues)
- **Flutter docs**: [flutter.dev](https://flutter.dev/)
- **Dart docs**: [dart.dev](https://dart.dev/)

---

## 📄 License

Documentation follows the project license.

---

## 🤝 Contributing

Contributions welcome! If you find issues or have suggestions:

1. Open an issue describing the problem
2. Submit a PR with fixes
3. Ensure your changes match the codebase behavior

---
