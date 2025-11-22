# Mesh Notes - UI Design

## Overview

The Mesh Notes UI follows Material Design 3 with a custom multi-layer rendering system and stack-based navigation. Layouts are responsive for both desktop and mobile.

## App Entry

**Location**: [lib/page/mesh_app.dart](../lib/page/mesh_app.dart)

```dart
class MeshApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh Notes',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      home: WelcomeView(), // Login or main view
    );
  }
}
```

**Lifecycle management**:
- Use `AppLifecycleListener` to watch app state
- Save data when paused
- Check network status when resumed

## Page Structure

### 1. WelcomeView

**Location**: [lib/page/welcome.dart](../lib/page/welcome.dart)

**Purpose**:
- User login/registration
- Create or select a user profile
- Enter username/password
- Navigate to the main view

**UI elements**:
- User list (existing profiles)
- Login form
- "New user" button

### 2. LargeScreenView (desktop layout)

**Location**: [lib/page/large_screen_view.dart](../lib/page/large_screen_view.dart)

Two-pane layout for desktop:

```
┌─────────────────────────────────────┐
│ DocumentNavigator │ DocumentView    │
│  (sidebar)         │  (editor)       │
│  - Doc tree        │  - Title        │
│  - Network status  │  - Toolbar      │
│  - User info       │  - Editor       │
└─────────────────────────────────────┘
```

**Responsive design**:
- Small screens: single column, collapsible sidebar
- Large screens: two columns, fixed sidebar

### 3. DocumentNavigator

**Location**: [lib/page/doc_navigator.dart](../lib/page/doc_navigator.dart)

**Purpose**:
- Display the document tree (hierarchical)
- Drag-and-drop reorder and move documents
- Show network status and peer count
- User info popup menu

**Key components**:

#### Document list
```dart
ListView.builder(
  itemCount: docList.length + 1,
  itemBuilder: (context, index) {
    if (index < docList.length) {
      return _buildDraggableDocItem(context, index);
    } else {
      return _buildEndDropZone(context);
    }
  },
)
```

#### Drag-and-drop
**New (2024-11)**:
- Long-press to drag documents
- Show drop position in real time (blue line)
- Three drop modes:
  - As sibling (above)
  - As sibling (below)
  - As child
- Indentation line indicates depth (every 20px)

```dart
Widget _buildDraggableDocItem(BuildContext context, int index) {
  return DragTarget<int>(
    onMove: (details) {
      // Compute drop position (top/middle/bottom thirds)
      // Compute depth (by horizontal position)
      // Show indicator line
    },
    builder: (context, candidateData, rejectedData) {
      return Column(
        children: [
          if (_dropPosition == _DropPosition.above)
            _buildDropLine(indentWidth, isAsChild: false),
          LongPressDraggable<int>(
            feedbackOffset: const Offset(0, -50),
            child: _buildDocListTile(context, index, docNode, 0),
          ),
          if (_dropPosition == _DropPosition.below)
            _buildDropLine(indentWidth, isAsChild: false),
          if (_dropPosition == _DropPosition.asChild)
            _buildDropLine(indentWidth, isAsChild: true),
        ],
      );
    },
  );
}
```

#### Network status icon
```dart
Widget _buildNetworkIcon() {
  return NetworkStatusIcon(
    networkStatus: _networkStatus,  // connected/lost
    peerCount: _peerCount,           // online peers
  );
}
```

#### Document menu
- Delete document
- Rename document
- Export document
- Document properties

### 4. DocumentView

**Location**: [lib/page/document_view.dart](../lib/page/document_view.dart)

**Structure**:
```dart
Column(
  children: [
    _buildTitleBar(),       // Title bar
    _buildToolbar(),        // Toolbar
    Expanded(
      child: MindEditField(), // Editor body
    ),
  ],
)
```

#### Title bar
- Editable document title
- Back button (mobile)
- Sync status indicator

#### Toolbar
- Text styles (bold, italic, underline, strikethrough)
- Heading levels (H1, H2, H3)
- List styles (bulleted, checkbox)
- Indent/outdent
- Plugin buttons (AI assistant, etc.)

### 5. StackPageView

**Location**: [lib/page/stack_page_view.dart](../lib/page/stack_page_view.dart)

Custom single-page stack navigation container that replaces Navigator 2.0.

**Features**:
- Stack-based page management
- Page enter/exit animations
- Back-button handling
- Keep page states alive

```dart
class StackPageView extends StatefulWidget {
  void push(Widget page);
  void pop();
  void replace(Widget page);
}
```

**Use cases**:
- Settings page
- Search page
- Detail pages

## Editor UI

### 1. MindEditField

**Location**: [lib/mindeditor/view/mind_edit_field.dart](../lib/mindeditor/view/mind_edit_field.dart)

Main editor container handling:
- Scroll management
- Keyboard input
- Active block tracking
- Selection handling

```dart
class MindEditField extends StatefulWidget {
  final ScrollController scrollController;
  final TextEditingController textController;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: Scrollable(
        controller: scrollController,
        viewportBuilder: (context, position) {
          return _buildBlockList();
        },
      ),
    );
  }
}
```

**Implements TextInputClient**:
```dart
class MindEditFieldState extends State<MindEditField>
    implements TextInputClient {

  @override
  void updateEditingValue(TextEditingValue value) {
    // Handle text input
    // Compute diff
    // Update document
  }

  @override
  void performAction(TextInputAction action) {
    // Handle enter/newline/etc.
  }
}
```

### 2. MindEditBlock

**Location**: [lib/mindeditor/view/mind_edit_block.dart](../lib/mindeditor/view/mind_edit_block.dart)

UI for a single paragraph:

```dart
class MindEditBlock extends StatefulWidget {
  final ParagraphDesc desc;       // Paragraph data
  final bool showHandler;         // Whether to show controls
  final VoidCallback? onTap;      // Tap
  final VoidCallback? onDoubleTap; // Double-tap

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHandler) _buildBlockHandler(),  // Left controls
        Expanded(child: _buildBlockContent()),  // Block content
        if (hasExtra) _buildExtraContent(),     // AI suggestions etc.
      ],
    );
  }
}
```

#### Block handler
Desktop-only controls:
- Drag icon (six dots)
- Add block button (+)
- More menu (⋮)

#### Block content
Rendered with a custom RenderObject:
```dart
class MindEditBlockImpl extends LeafRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderMindEditBlock(/* ... */);
  }
}
```

`RenderMindEditBlock` handles:
- Text layout (`TextPainter`)
- Painting text, cursor, selection
- Hit testing
- Performance optimization

#### Extra content
Plugins can attach extra UI to a block:
- AI suggestions (lightbulb icon)
- Error hints
- Reference links

### 3. Multi-layer rendering

**Location**: [lib/mindeditor/view/floating_view.dart](../lib/mindeditor/view/floating_view.dart)

Uses a custom stack instead of Flutter Overlay:

```dart
class FloatingViewManager {
  Widget build() {
    return Stack(
      children: [
        _mainContent,           // Editor
        _selectionLayer,        // Selection layer
        _pluginTipsLayer,       // Plugin hints
        _popupMenuLayer,        // Context menus
        _pluginDialogLayer,     // Plugin dialogs
      ],
    );
  }
}
```

**Layers**:
1. **Selection layer**: blue background and drag handles
2. **Plugin tips layer**: AI suggestions, quick actions
3. **Popup menu layer**: context/long-press menus
4. **Plugin dialog layer**: AI dialogs, settings dialogs

**Benefits**:
- Better performance (avoid Overlay rebuilds)
- More flexible positioning
- Simplified state management

### 4. Selection system

**Location**: [lib/mindeditor/view/selection/](../lib/mindeditor/view/selection/)

Custom text selection system.

#### SelectionHandle
```dart
class SelectionHandle extends StatelessWidget {
  final Offset position;
  final bool isStart;  // start or end

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          // Drag to update selection
        },
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
```

#### SelectionArea
Draws the blue highlight for selected text.

**Cross-block selection**:
- Selection can span multiple paragraphs
- Each paragraph paints its own selection area
- Unified controller coordinates selection

## Theme and Styles

### Color scheme

```dart
ColorScheme.fromSeed(
  seedColor: Colors.blue,
  brightness: Brightness.light,
)
```

**Main colors**:
- Primary: Blue
- Selection: Blue.shade200
- Background: White
- Surface: Grey.shade50

### Text styles

```dart
// Body
TextStyle(fontSize: 15.0, color: Colors.black87)

// Heading 1
TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold)

// Heading 2
TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold)

// Heading 3
TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)
```

### Rich-text styles

Supported styles:
- **Bold** (`bold`)
- *Italic* (`italic`)
- <u>Underline</u> (`underline`)
- ~~Strikethrough~~ (`strikethrough`)
- Text color (TBD)

### Layout values

```dart
// Block indent
double indentWidth = level * 20.0;

// Line height
double lineHeight = 1.5;

// Block spacing
EdgeInsets blockMargin = EdgeInsets.symmetric(vertical: 4.0);

// Toolbar height
double toolbarHeight = 48.0;

// Sidebar width
double sidebarWidth = 280.0;
```

## Responsive Design

### Breakpoints

```dart
const double kSmallScreenWidth = 600.0;
const double kMediumScreenWidth = 1024.0;
```

### Layout behavior

**Small (< 600px)**:
- Single column
- Sidebar collapses to a drawer
- Simplified toolbar
- Hide block handlers

**Medium (600-1024px)**:
- Optional two columns
- Sidebar can expand/collapse

**Large (> 1024px)**:
- Two columns
- Fixed sidebar
- Full toolbar
- Show block handlers

### Platform-specific UI

**Desktop**:
- Show block handlers (drag/menu)
- Hover effects
- Custom mouse cursors
- Window-close confirmation

**Mobile**:
- Hide block handlers
- Touch gesture tuning
- Soft keyboard management
- Bottom navigation bar

## Animation

### Page transitions

Custom transitions via `PageRouteBuilder`:
```dart
PageRouteBuilder(
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    );
  },
)
```

### Drag feedback

```dart
LongPressDraggable<int>(
  feedbackOffset: const Offset(0, -50),
  feedback: Material(
    elevation: 6.0,
    child: Container(/* translucent preview */),
  ),
  childWhenDragging: Opacity(
    opacity: 0.3,
    child: /* faded original */,
  ),
)
```

### Drop indicator

```dart
// Animated blue line
AnimatedContainer(
  duration: Duration(milliseconds: 200),
  height: 3,
  color: Colors.blue,
  margin: EdgeInsets.symmetric(vertical: 4.0),
)
```

## Accessibility

### Semantics

```dart
Semantics(
  label: 'Document title',
  hint: 'Tap to edit title',
  child: TextField(/* ... */),
)
```

### Keyboard navigation

- Tab: focus traversal
- Enter: new block
- Backspace: delete/merge blocks
- Ctrl+B/I/U: text styles
- Ctrl+Z/Y: undo/redo (TBD)

### Screen readers

- Add semantic labels to interactive elements
- Provide text descriptions
- Manage focus

## Performance

### 1. Rendering

**Viewport culling**:
- Render only visible blocks
- Use `ListView.builder` lazy loading
- `cacheExtent` controls buffer area

**Active block tracking**:
```dart
String? _activeBlockId;  // currently edited block

void _updateActiveBlock(String blockId) {
  if (_activeBlockId != blockId) {
    _activeBlockId = blockId;
    // Rebuild only what is necessary
  }
}
```

### 2. Avoid rebuilds

**Use const**:
```dart
const Icon(Icons.description_outlined, size: 18.0)
```

**Extract helpers**:
```dart
Widget _buildStaticHeader() {
  return const Text('Mesh Notes');
}
```

**Keys**:
```dart
ListView.builder(
  itemBuilder: (context, index) {
    return MindEditBlock(
      key: ValueKey(docList[index].docId),
      // ...
    );
  },
)
```

### 3. State management

**Local updates**:
```dart
// Update document list only
setState(() {
  docList = controller.docManager.getFlattenedDocumentList();
});
```

**Avoid global refreshes**:
Use `CallbackRegistry` to notify only what must update.

## UI Development Tips

### 1. Add a new page
1. Create a file under `lib/page/`
2. Extend `StatelessWidget` or `StatefulWidget`
3. Navigate with `StackPageView.push()`
4. Mind lifecycle handling

### 2. Add a toolbar button
1. Add the button in `_buildToolbar()`
2. Implement tap handling
3. Update document state
4. Trigger UI refresh

### 3. Customize block styles
1. Modify `RenderMindEditBlock`
2. Update `ParagraphDesc` data
3. Add toolbar options
4. Sync the database

### 4. Debugging UI
- Use Flutter Inspector
- Enable `debugPaintSizeEnabled`
- Watch widget rebuild counts
- Use Performance Overlay

## Known Issues

1. **Selection handles**: may drift during fast scrolling
2. **Soft keyboard**: iOS keyboard can cover input area
3. **Drag-and-drop**: cross-window drag is unsupported
4. **Animation**: may stutter on low-end devices

## Future Work

1. **Dark mode**: follow system theme
2. **Custom themes**: user-defined colors and fonts
3. **More animations**: expand/collapse block animations
4. **Gestures**: pinch zoom, three-finger swipes
5. **Accessibility**: better screen reader support
