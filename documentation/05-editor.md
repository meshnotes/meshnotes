# Mesh Notes - Editor Implementation

## Overview

The Mesh Notes editor is a custom rich-text editor with hierarchy, multiple block types, and real-time collaboration. It follows an MVC style that separates data and view layers.

## Data Model

### Document

**Location**: [lib/mindeditor/document/document.dart](../lib/mindeditor/document/document.dart)

```dart
class Document {
  String id;                                    // Document ID (UUID)
  List<ParagraphDesc> paragraphs;               // Paragraph list
  Map<String, ParagraphDesc> _mapOfParagraphs;  // Fast lookup map
  bool _hasModified;                            // Dirty flag
  int _lastUpdate;                              // Last update timestamp
  String? _editingBlockId;                      // Current editing block ID
  DocumentManager? manager;                     // Owning manager
  DbHelper? _db;                                // DB access
}
```

**Key methods**:

```dart
// Add paragraph
ParagraphDesc addNewParagraph({
  required _BlockType type,
  String? afterId,
  int level = 0,
});

// Delete paragraph
void removeParagraph(String id);

// Merge paragraphs
void mergeParagraphs(String id1, String id2);

// Split paragraph
void splitParagraph(String id, int offset);

// Save to DB
Future<void> save();

// Load from DB
static Future<Document> load(String id, DbHelper db);
```

### ParagraphDesc

**Location**: [lib/mindeditor/document/paragraph_desc.dart](../lib/mindeditor/document/paragraph_desc.dart)

```dart
class ParagraphDesc {
  String _id;                           // Paragraph ID (UUID)
  List<TextDesc> _texts;                // Rich-text segments
  Map<String, ExtraInfo> _extra;        // Extra info (AI suggestions, etc.)
  _BlockType _type;                     // Block type
  _BlockListing _listing;               // List style
  int _level;                           // Indent level
  ParagraphDesc? _previous, _next;      // Doubly linked list
  TextSelection? _editingPosition;      // Cursor/selection
  MindEditBlockState? _state;           // UI state reference
}
```

**Block types**:

```dart
enum _BlockType {
  title,      // Document title
  text,       // Body text
  headline1,  // H1
  headline2,  // H2
  headline3,  // H3
}
```

**List styles**:

```dart
enum _BlockListing {
  none,       // None
  bulleted,   // Bulleted list
  checked,    // Checkbox (checked)
  unchecked,  // Checkbox (unchecked)
}
```

**Key methods**:

```dart
// Insert text
void insertText(int offset, String text, {TextStyle? style});

// Delete text
void deleteText(int start, int end);

// Apply style
void applyStyle(int start, int end, TextStyle style);

// Get plain text
String getPlainText();

// Get rich text
List<TextDesc> getTexts();

// Set indent
void setLevel(int level);

// Set type
void setType(_BlockType type);

// Set list style
void setListing(_BlockListing listing);
```

### TextDesc

**Location**: [lib/mindeditor/document/text_desc.dart](../lib/mindeditor/document/text_desc.dart)

```dart
class TextDesc {
  String text;              // Content
  bool bold;                // Bold
  bool italic;              // Italic
  bool underline;           // Underline
  bool strikethrough;       // Strikethrough
  Color? textColor;         // Text color

  TextDesc({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.textColor,
  });

  // Convert to Flutter TextStyle
  TextStyle toTextStyle({double? fontSize}) {
    return TextStyle(
      fontSize: fontSize ?? 15.0,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      decoration: _getDecoration(),
      color: textColor ?? Colors.black87,
    );
  }

  TextDecoration _getDecoration() {
    final decorations = <TextDecoration>[];
    if (underline) decorations.add(TextDecoration.underline);
    if (strikethrough) decorations.add(TextDecoration.lineThrough);
    return TextDecoration.combine(decorations);
  }
}
```

### ExtraInfo

```dart
class ExtraInfo {
  String source;            // Source (e.g., "plugin:ai")
  String content;           // Content
  Map<String, dynamic> metadata;  // Metadata

  ExtraInfo({
    required this.source,
    required this.content,
    this.metadata = const {},
  });
}
```

**Uses**:
- AI suggestions
- Reference links
- Error hints
- Annotations

## Editor View

### MindEditField

**Location**: [lib/mindeditor/view/mind_edit_field.dart](../lib/mindeditor/view/mind_edit_field.dart)

Main editing container responsible for:
- Keyboard input
- Scroll management
- Rendering block list
- Focus management

```dart
class MindEditField extends StatefulWidget {
  final Document document;
  final ScrollController scrollController;

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

  TextEditingValue _lastValue = TextEditingValue.empty;

  @override
  void updateEditingValue(TextEditingValue value) {
    // 1. Handle iOS backspace
    if (_isIosBackspace(value)) {
      _handleBackspace();
      return;
    }

    // 2. Compute text diff
    final diff = _calculateDiff(_lastValue.text, value.text);

    // 3. Apply change
    if (diff.isInsertion) {
      _insertText(diff.position, diff.text);
    } else if (diff.isDeletion) {
      _deleteText(diff.start, diff.end);
    }

    _lastValue = value;
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) {
      _handleNewLine();
    }
  }
}
```

**Text diff calculation**:

```dart
class TextDiff {
  final bool isInsertion;
  final bool isDeletion;
  final int position;
  final int start;
  final int end;
  final String text;
}

TextDiff _calculateDiff(String oldText, String newText) {
  // Find common prefix
  int leftCommon = 0;
  while (leftCommon < oldText.length &&
         leftCommon < newText.length &&
         oldText[leftCommon] == newText[leftCommon]) {
    leftCommon++;
  }

  // Find common suffix
  int rightCommon = 0;
  while (rightCommon < oldText.length - leftCommon &&
         rightCommon < newText.length - leftCommon &&
         oldText[oldText.length - 1 - rightCommon] ==
         newText[newText.length - 1 - rightCommon]) {
    rightCommon++;
  }

  // Determine change type and range
  final changeStart = leftCommon;
  final changeEndOld = oldText.length - rightCommon;
  final changeEndNew = newText.length - rightCommon;

  if (changeEndNew > changeStart) {
    // Insertion
    return TextDiff(
      isInsertion: true,
      isDeletion: false,
      position: changeStart,
      text: newText.substring(changeStart, changeEndNew),
    );
  } else {
    // Deletion
    return TextDiff(
      isInsertion: false,
      isDeletion: true,
      start: changeStart,
      end: changeEndOld,
    );
  }
}
```

### MindEditBlock

**Location**: [lib/mindeditor/view/mind_edit_block.dart](../lib/mindeditor/view/mind_edit_block.dart)

UI for a single paragraph:

```dart
class MindEditBlock extends StatefulWidget {
  final ParagraphDesc desc;
  final bool showHandler;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left controls (desktop)
        if (showHandler) _buildBlockHandler(),

        // Indent space
        SizedBox(width: desc.level * 20.0),

        // Block content
        Expanded(child: _buildBlockContent()),

        // Extra content (AI suggestions, etc.)
        if (desc.hasExtra) _buildExtraContent(),
      ],
    );
  }
}
```

**Block content rendering**:

```dart
Widget _buildBlockContent() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // List marker
      if (desc.listing != _BlockListing.none) _buildListMarker(),

      // Text content
      MindEditBlockImpl(
        desc: desc,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
      ),
    ],
  );
}
```

**List marker**:

```dart
Widget _buildListMarker() {
  switch (desc.listing) {
    case _BlockListing.bulleted:
      return Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
      );

    case _BlockListing.checked:
      return Checkbox(
        value: true,
        onChanged: (value) => desc.setListing(_BlockListing.unchecked),
      );

    case _BlockListing.unchecked:
      return Checkbox(
        value: false,
        onChanged: (value) => desc.setListing(_BlockListing.checked),
      );

    default:
      return SizedBox.shrink();
  }
}
```

### RenderMindEditBlock (custom render)

**Location**: [lib/mindeditor/view/mind_edit_block_impl.dart](../lib/mindeditor/view/mind_edit_block_impl.dart)

Custom `RenderObject` for text rendering:

```dart
class RenderMindEditBlock extends RenderBox {
  ParagraphDesc _desc;
  TextPainter? _textPainter;
  bool _needsLayout = true;

  @override
  void performLayout() {
    if (_needsLayout) {
      _buildTextPainter();
      _textPainter!.layout(maxWidth: constraints.maxWidth);
    }

    size = Size(
      constraints.maxWidth,
      _textPainter!.height + 8.0,  // vertical padding
    );

    _needsLayout = false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    // 1. Selection background
    if (_desc.editingPosition != null) {
      _paintSelection(canvas, offset);
    }

    // 2. Text
    _textPainter!.paint(canvas, offset + Offset(4.0, 4.0));

    // 3. Cursor
    if (_desc.isEditing) {
      _paintCursor(canvas, offset);
    }
  }

  void _buildTextPainter() {
    final spans = <TextSpan>[];

    for (var textDesc in _desc.getTexts()) {
      spans.add(TextSpan(
        text: textDesc.text,
        style: textDesc.toTextStyle(
          fontSize: _getFontSize(_desc.type),
        ),
      ));
    }

    _textPainter = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
  }

  double _getFontSize(_BlockType type) {
    switch (type) {
      case _BlockType.title:
        return 28.0;
      case _BlockType.headline1:
        return 24.0;
      case _BlockType.headline2:
        return 20.0;
      case _BlockType.headline3:
        return 18.0;
      default:
        return 15.0;
    }
  }

  void _paintSelection(Canvas canvas, Offset offset) {
    final selection = _desc.editingPosition!;
    final start = _textPainter!.getOffsetForCaret(
      TextPosition(offset: selection.start),
      Rect.zero,
    );
    final end = _textPainter!.getOffsetForCaret(
      TextPosition(offset: selection.end),
      Rect.zero,
    );

    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromPoints(
        offset + start + Offset(4.0, 4.0),
        offset + end + Offset(4.0, 4.0 + 20.0),
      ),
      paint,
    );
  }

  void _paintCursor(Canvas canvas, Offset offset) {
    if (_desc.editingPosition == null) return;

    final cursorOffset = _textPainter!.getOffsetForCaret(
      TextPosition(offset: _desc.editingPosition!.baseOffset),
      Rect.zero,
    );

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      offset + cursorOffset + Offset(4.0, 4.0),
      offset + cursorOffset + Offset(4.0, 24.0),
      paint,
    );
  }
}
```

## Selection System

### SelectionController

**Location**: [lib/mindeditor/controller/selection_controller.dart](../lib/mindeditor/controller/selection_controller.dart)

```dart
class SelectionController {
  String? _startBlockId;
  int? _startOffset;
  String? _endBlockId;
  int? _endOffset;

  // Set selection
  void setSelection({
    required String startBlockId,
    required int startOffset,
    required String endBlockId,
    required int endOffset,
  }) {
    _startBlockId = startBlockId;
    _startOffset = startOffset;
    _endBlockId = endBlockId;
    _endOffset = endOffset;

    _notifyListeners();
  }

  // Clear selection
  void clearSelection() {
    _startBlockId = null;
    _startOffset = null;
    _endBlockId = null;
    _endOffset = null;

    _notifyListeners();
  }

  // Get selected text
  String getSelectedText(Document doc) {
    if (_startBlockId == null) return '';

    if (_startBlockId == _endBlockId) {
      // Single-block selection
      final block = doc.getBlock(_startBlockId!);
      final text = block.getPlainText();
      return text.substring(_startOffset!, _endOffset!);
    } else {
      // Cross-block selection
      final buffer = StringBuffer();
      bool inSelection = false;

      for (var block in doc.paragraphs) {
        if (block.id == _startBlockId) {
          inSelection = true;
          buffer.write(block.getPlainText().substring(_startOffset!));
          buffer.write('\n');
        } else if (block.id == _endBlockId) {
          buffer.write(block.getPlainText().substring(0, _endOffset!));
          break;
        } else if (inSelection) {
          buffer.write(block.getPlainText());
          buffer.write('\n');
        }
      }

      return buffer.toString();
    }
  }
}
```

### SelectionHandle

**Location**: [lib/mindeditor/view/selection/selection_handle.dart](../lib/mindeditor/view/selection/selection_handle.dart)

```dart
class SelectionHandle extends StatelessWidget {
  final Offset position;
  final bool isStart;
  final Function(DragUpdateDetails) onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 6,
      top: position.dy - (isStart ? 20 : 0),
      child: GestureDetector(
        onPanUpdate: onDrag,
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

## Gesture Handling

### GestureHandler

**Location**: [lib/mindeditor/controller/gesture_handler.dart](../lib/mindeditor/controller/gesture_handler.dart)

```dart
class GestureHandler {
  // Tap: set cursor
  void onTap(String blockId, Offset localPosition) {
    final block = _getBlock(blockId);
    final offset = _getTextOffset(block, localPosition);

    block.setEditingPosition(TextSelection.collapsed(offset: offset));
    _focusBlock(blockId);
  }

  // Double-tap: select word
  void onDoubleTap(String blockId, Offset localPosition) {
    final block = _getBlock(blockId);
    final offset = _getTextOffset(block, localPosition);
    final text = block.getPlainText();

    // Find word boundaries
    int start = offset;
    while (start > 0 && !_isWordBoundary(text[start - 1])) {
      start--;
    }

    int end = offset;
    while (end < text.length && !_isWordBoundary(text[end])) {
      end++;
    }

    block.setEditingPosition(TextSelection(
      baseOffset: start,
      extentOffset: end,
    ));
  }

  // Long-press: show menu
  void onLongPress(String blockId, Offset globalPosition) {
    _showContextMenu(blockId, globalPosition);
  }

  // Drag: extend selection
  void onPanUpdate(DragUpdateDetails details) {
    final blockId = _findBlockAtPosition(details.globalPosition);
    if (blockId == null) return;

    final block = _getBlock(blockId);
    final localPosition = _globalToLocal(details.globalPosition, blockId);
    final offset = _getTextOffset(block, localPosition);

    _extendSelection(blockId, offset);
  }

  int _getTextOffset(ParagraphDesc block, Offset localPosition) {
    final textPainter = block.state?.textPainter;
    if (textPainter == null) return 0;

    return textPainter.getPositionForOffset(localPosition).offset;
  }

  bool _isWordBoundary(String char) {
    return char == ' ' || char == '\n' || char == '.' ||
           char == ',' || char == '!' || char == '?';
  }
}
```

## Keyboard Shortcuts

**Location**: [lib/mindeditor/controller/keyboard_handler.dart](../lib/mindeditor/controller/keyboard_handler.dart)

```dart
class KeyboardHandler {
  void onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Ctrl/Cmd + B: bold
    if (_isModified(event) && event.logicalKey == LogicalKeyboardKey.keyB) {
      _toggleBold();
      return;
    }

    // Ctrl/Cmd + I: italic
    if (_isModified(event) && event.logicalKey == LogicalKeyboardKey.keyI) {
      _toggleItalic();
      return;
    }

    // Ctrl/Cmd + U: underline
    if (_isModified(event) && event.logicalKey == LogicalKeyboardKey.keyU) {
      _toggleUnderline();
      return;
    }

    // Tab: indent
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_isModified(event)) {
        _decreaseIndent();  // Shift+Tab: outdent
      } else {
        _increaseIndent();
      }
      return;
    }

    // Enter: new line
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _handleEnter();
      return;
    }

    // Backspace: delete/merge
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _handleBackspace();
      return;
    }
  }

  bool _isModified(KeyEvent event) {
    return Environment().isMac()
        ? event.metaKey  // Cmd on macOS
        : event.controlKey;  // Ctrl elsewhere
  }

  void _toggleBold() {
    final selection = controller.selection;
    if (selection.isCollapsed) return;

    controller.document.applyStyle(
      selection.start,
      selection.end,
      TextStyle(fontWeight: FontWeight.bold),
    );
  }

  void _increaseIndent() {
    final block = _getCurrentBlock();
    if (block.level < 10) {
      block.setLevel(block.level + 1);
    }
  }

  void _handleEnter() {
    final block = _getCurrentBlock();
    final offset = block.editingPosition?.baseOffset ?? 0;

    // Split current block
    controller.document.splitParagraph(block.id, offset);
  }

  void _handleBackspace() {
    final block = _getCurrentBlock();
    final offset = block.editingPosition?.baseOffset ?? 0;

    if (offset == 0) {
      // Backspace at start merges with previous block
      if (block.previous != null) {
        controller.document.mergeParagraphs(block.previous!.id, block.id);
      }
    } else {
      // Delete previous char
      block.deleteText(offset - 1, offset);
    }
  }
}
```

## Toolbar

**Location**: [lib/page/document_view.dart](../lib/page/document_view.dart)

```dart
Widget _buildToolbar() {
  return Container(
    height: 48,
    color: Colors.grey.shade100,
    child: Row(
      children: [
        // Text styles
        _buildToolbarButton(
          icon: Icons.format_bold,
          tooltip: 'Bold',
          onPressed: () => controller.toggleBold(),
        ),
        _buildToolbarButton(
          icon: Icons.format_italic,
          tooltip: 'Italic',
          onPressed: () => controller.toggleItalic(),
        ),
        _buildToolbarButton(
          icon: Icons.format_underline,
          tooltip: 'Underline',
          onPressed: () => controller.toggleUnderline(),
        ),
        _buildToolbarButton(
          icon: Icons.format_strikethrough,
          tooltip: 'Strikethrough',
          onPressed: () => controller.toggleStrikethrough(),
        ),

        Divider(),

        // Heading levels
        _buildToolbarDropdown(
          value: _currentBlockType,
          items: [
            DropdownMenuItem(value: _BlockType.text, child: Text('Body')),
            DropdownMenuItem(value: _BlockType.headline1, child: Text('Heading 1')),
            DropdownMenuItem(value: _BlockType.headline2, child: Text('Heading 2')),
            DropdownMenuItem(value: _BlockType.headline3, child: Text('Heading 3')),
          ],
          onChanged: (type) => controller.setBlockType(type),
        ),

        Divider(),

        // List styles
        _buildToolbarButton(
          icon: Icons.format_list_bulleted,
          tooltip: 'Bulleted list',
          onPressed: () => controller.setListing(_BlockListing.bulleted),
        ),
        _buildToolbarButton(
          icon: Icons.check_box,
          tooltip: 'Checkbox',
          onPressed: () => controller.setListing(_BlockListing.unchecked),
        ),

        Divider(),

        // Indent
        _buildToolbarButton(
          icon: Icons.format_indent_increase,
          tooltip: 'Increase indent',
          onPressed: () => controller.increaseIndent(),
        ),
        _buildToolbarButton(
          icon: Icons.format_indent_decrease,
          tooltip: 'Decrease indent',
          onPressed: () => controller.decreaseIndent(),
        ),

        Spacer(),

        // Plugin buttons
        ...controller.pluginManager.getToolbarButtons(),
      ],
    ),
  );
}
```

## Performance

### 1. Viewport culling

Render only visible blocks:

```dart
class MindEditFieldState extends State<MindEditField> {
  final ScrollController _scrollController;
  List<ParagraphDesc> _visibleBlocks = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateVisibleBlocks);
  }

  void _updateVisibleBlocks() {
    final scrollOffset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;

    _visibleBlocks = widget.document.paragraphs.where((block) {
      final blockOffset = _getBlockOffset(block);
      return blockOffset >= scrollOffset - 100 &&
             blockOffset <= scrollOffset + viewportHeight + 100;
    }).toList();

    setState(() {});
  }
}
```

### 2. Active block optimization

Only the active block updates frequently:

```dart
String? _activeBlockId;

void _setActiveBlock(String blockId) {
  if (_activeBlockId != blockId) {
    // Stop listening on old active block
    _getBlock(_activeBlockId)?.setActive(false);

    // Start listening on new active block
    _getBlock(blockId)?.setActive(true);

    _activeBlockId = blockId;
  }
}
```

### 3. Text caching

Cache `TextPainter` to avoid relayout:

```dart
class ParagraphDesc {
  TextPainter? _cachedTextPainter;
  bool _needsRebuild = true;

  TextPainter getTextPainter() {
    if (_needsRebuild) {
      _cachedTextPainter = _buildTextPainter();
      _needsRebuild = false;
    }
    return _cachedTextPainter!;
  }

  void invalidate() {
    _needsRebuild = true;
  }
}
```

## Known Issues

1. **Long-document performance**: scrolling may lag beyond 1000 blocks
2. **Selection handles**: positions can drift during fast scrolling
3. **IME support**: Chinese IME candidate window sometimes misaligned
4. **Undo/redo**: not implemented

## Future Work

1. **Virtual scrolling**: more efficient large-document rendering
2. **Incremental updates**: repaint only changed portions
3. **Undo/redo stack**: full operation history
4. **Rich-text extensions**:
   - Text color
   - Background color
   - Font size
   - Font family
5. **More block types**:
   - Code block
   - Quote block
   - Divider
   - Image block
   - Table block
6. **Collaboration cursors**: show other users' caret positions
7. **Comments**: paragraph-level comments and discussions
