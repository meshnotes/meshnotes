import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block_impl.dart';
import 'package:my_log/my_log.dart';
import '../controller/callback_registry.dart';
import '../controller/controller.dart';
import '../document/document.dart';

class SelectionController {
  LayerLink? _layerLinkOfStartHandle;
  LayerLink? _layerLinkOfEndHandle;
  BuildContext? _context;
  OverlayEntry? _handleOfStart;
  OverlayEntry? _handleOfEnd;
  bool _shouldShowSelectionHandle = false;
  int lastBaseBlockIndex = -1;
  int lastExtentBlockIndex = -1;
  int lastBaseBlockPos = -1;
  int lastExtentBlockPos = -1;

  void dispose() {
    hideTextSelectionHandles();
    _context = null;
    _shouldShowSelectionHandle = false;
    _layerLinkOfStartHandle = null;
    _layerLinkOfEndHandle = null;
    lastBaseBlockIndex = -1;
    lastExtentBlockIndex = -1;
    lastBaseBlockPos = -1;
    lastExtentBlockPos = -1;
  }

  LayerLink? getLayerLinkOfStartHandle() => _layerLinkOfStartHandle;
  LayerLink? getLayerLinkOfEndHandle() => _layerLinkOfEndHandle;

  void showTextSelectionHandles() {
    if(!_shouldShowSelectionHandle) {
      return;
    }
    if(_context == null || _handleOfStart != null || _handleOfEnd != null) { // No context or already displayed handles
      return;
    }
    if(_layerLinkOfStartHandle == null || _layerLinkOfEndHandle == null) {
      return;
    }
    MyLogger.info('SelectionController: add selection overlay handle');
    double _handleSize = 22;
    _handleOfStart = _buildStartHandle(_handleSize);
    _handleOfEnd = _buildEndHandle(_handleSize);
    Overlay.of(_context!).insert(_handleOfStart!);
    Overlay.of(_context!).insert(_handleOfEnd!);
  }
  void hideTextSelectionHandles() {
    if(_handleOfStart != null) {
      _handleOfStart!.remove();
      _handleOfStart!.dispose();
      _handleOfStart = null;
    }
    if(_handleOfEnd != null) {
      _handleOfEnd!.remove();
      _handleOfEnd!.dispose();
      _handleOfEnd = null;
    }
    lastBaseBlockIndex = -1;
    lastExtentBlockIndex = -1;
    lastBaseBlockPos = -1;
    lastExtentBlockPos = -1;
  }

  OverlayEntry _buildStartHandle(double _handleSize) {
    return _buildHandle(_handleSize, _layerLinkOfStartHandle!, _HandleType.start);
  }
  OverlayEntry _buildEndHandle(double _handleSize) {
    return _buildHandle(_handleSize, _layerLinkOfEndHandle!, _HandleType.end);
  }
  OverlayEntry _buildHandle(double _handleSize, LayerLink _link, _HandleType type) {
    var container = Container(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _handleSize,
        height: _handleSize,
        child: CustomPaint(
          painter: _HandlePainter(),
        ),
      ),
    );
    var gesture = GestureDetector(
      onPanStart: (DragStartDetails details) {
        MyLogger.info('selection handle: drag start');
      },
      onPanUpdate: (DragUpdateDetails details) {
        MyLogger.debug('selection handle: drag update');
        // handle circle has an offset from actual point of text line, depending on start handle or end handle.
        var globalOffset = details.globalPosition + (type == _HandleType.start? Offset(0, _handleSize): Offset(0, -_handleSize));
        var modifyType = type == _HandleType.start? _ExtendType.base: _ExtendType.extend;
        updateSelectionByOffset(globalOffset, type: modifyType);
      },
      onPanEnd: (DragEndDetails details) {
        MyLogger.info('selection handle: drag end');
      },
      onPanCancel: () {
        MyLogger.info('selection handle: drag cancel');
      },
      child: container,
    );
    Offset offset;
    if(type == _HandleType.start) {
      offset = Offset(-_handleSize / 2, -_handleSize);
    } else {
      offset = Offset(-_handleSize / 2, 0);
    }
    return OverlayEntry(
      builder: (BuildContext context) {
        var result = CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: offset,
          child: gesture,
        );
        return result;
      },
    );
  }

  void requestCursorAtGlobalOffset(Offset offset) {
    final document = Controller.instance.document;
    if(document == null) return;

    final block = _findBlockState(document.paragraphs, offset, _ExtendType.extend);
    if(block == null) return;

    final blockId = block.getBlockId();
    final render = block.getRender();
    if(render == null) return;

    int index = _getIndexOfBlock(blockId);
    int pos = _getPosFromRender(render, offset);
    if(lastBaseBlockIndex != -1 && lastExtentBlockIndex != -1) {
      int startIndex = min(lastBaseBlockIndex, lastExtentBlockIndex);
      int endIndex = max(lastBaseBlockIndex, lastExtentBlockIndex);
      for(int idx = startIndex; idx <= endIndex; idx++) {
        if(idx != index) {
          // document.paragraphs[idx].clearTextSelection();
          document.paragraphs[idx].getEditState()?.releaseCursor();
        }
      }
    }
    lastBaseBlockIndex = index;
    lastExtentBlockIndex = index;
    lastBaseBlockPos = pos;
    lastExtentBlockPos = pos;
    block.requestCursorAtPosition(pos);
  }

  void updateSelectionInBlock(String blockId, TextSelection newSelection) {
    var paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

    for(int idx = 0; idx < paragraphs.length; idx++) {
      if(paragraphs[idx].getBlockId() == blockId) {
        lastBaseBlockIndex = idx;
        lastExtentBlockIndex = idx;
        lastBaseBlockPos = newSelection.baseOffset;
        lastExtentBlockPos = newSelection.extentOffset;
        paragraphs[idx].setTextSelection(newSelection);
        return;
      }
    }
  }

  void updateSelectionByOffset(Offset offset, {_ExtendType type = _ExtendType.extend}) {
    final document = Controller.instance.document;
    if(document == null) return;

    final block = _findBlockState(document.paragraphs, offset, type);
    final render = block?.getRender();
    if(render != null) {
      final blockId = block!.getBlockId();
      int index = _getIndexOfBlock(blockId);
      int pos = _getPosFromRender(render, offset);
      int baseBlockIndex = lastBaseBlockIndex;
      int baseBlockPos = lastBaseBlockPos;
      int extentBlockIndex = lastExtentBlockIndex;
      int extentBlockPos = lastExtentBlockPos;
      switch(type) {
        case _ExtendType.base:
          baseBlockIndex = index;
          baseBlockPos = pos;
          break;
        case _ExtendType.extend:
          extentBlockIndex = index;
          extentBlockPos = pos;
          break;
      }
      MyLogger.info('efantest: baseBlockIndex=$baseBlockIndex, baseBlockPos=$baseBlockPos, extentBlockIndex=$extentBlockIndex, extentBlockPos=$extentBlockPos');
      _updateSelection(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos, document);
    }
  }
  void updateSelectionByIndexAndPos(int blockIndex, int pos, {_ExtendType type = _ExtendType.extend}) {
    final document = Controller.instance.document;
    if(document == null) return;

    int baseBlockIndex = lastBaseBlockIndex;
    int baseBlockPos = lastBaseBlockPos;
    int extentBlockIndex = lastExtentBlockIndex;
    int extentBlockPos = lastExtentBlockPos;
    switch(type) {
      case _ExtendType.base:
        baseBlockIndex = blockIndex;
        baseBlockPos = pos;
        break;
      case _ExtendType.extend:
        extentBlockIndex = blockIndex;
        extentBlockPos = pos;
        break;
    }
    _updateSelection(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos, document);
  }

  void _updateSelection(int baseBlockIndex, int baseBlockPos, int extentBlockIndex, int extentBlockPos, Document document) {
    /// startBlockIndex: minimal block index in selection
    /// endBlockIndex: maximum block index in selection
    /// startBlockPos: position in start block
    /// endBlockPos: position in end block
    /// * If in the same block, startBlockPos should be the minimal position, and endBlockPos should be the maximum position
    var (startBlockIndex, startBlockPos) = _getStartIndexAndPos(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos);
    var (endBlockIndex, endBlockPos) = _getEndIndexAndPos(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos);
    int startIndex = startBlockIndex;
    int endIndex = endBlockIndex;
    if(lastBaseBlockIndex != -1) {
      startIndex = min(startIndex, lastBaseBlockIndex);
      endIndex = max(endIndex, lastBaseBlockIndex);
    }
    if(lastExtentBlockIndex != -1) {
      startIndex = min(startIndex, lastExtentBlockIndex);
      endIndex = max(endIndex, lastExtentBlockIndex);
    }
    for(int idx = startIndex; idx <= endIndex; idx++) {
      /// 1. Clear selection in blocks which are out of range [startBlockIndex, endBlockIndex]
      /// 2. Set selection in start block to be [startBlockPos, length]
      /// 3. Set selection in end block to be [0, endBlockPos]
      /// 4. If start and end block is the same, set the selection to be [startBlockPos, endBlockPos]
      final node = document.paragraphs[idx];
      final blockState = node.getEditState();
      if(blockState == null) continue;

      if(idx < startBlockIndex || idx > endBlockIndex) {
        blockState.releaseCursor();
        continue;
      }
      int startPos = 0, endPos = document.paragraphs[idx].getPlainText().length;
      if(idx == startBlockIndex) {
        startPos = startBlockPos;
      }
      if(idx == endBlockIndex) {
        endPos = endBlockPos;
      }

      if(idx == extentBlockIndex) {
        if(endPos == extentBlockPos) {
          node.setTextSelection(TextSelection(baseOffset: startPos, extentOffset: endPos), isEditing: true);
        } else {
          node.setTextSelection(TextSelection(baseOffset: endPos, extentOffset: startPos), isEditing: true);
        }
      } else {
        node.setTextSelection(TextSelection(baseOffset: startPos, extentOffset: endPos), isEditing: false);
      }
      node.getEditState()?.getRender()?.markNeedsPaint();
    }
    lastBaseBlockIndex = baseBlockIndex;
    lastBaseBlockPos = baseBlockPos;
    lastExtentBlockIndex = extentBlockIndex;
    lastExtentBlockPos = extentBlockPos;
    CallbackRegistry.refreshTextEditingValue();
    Controller.instance.selectionController.showTextSelectionHandles();
  }
  void updateSelectionByPosRange(Offset globalOffset) {
    final controller = Controller.instance;
    final document = controller.document;
    if(document == null) return;

    final blockState = _findBlockState(document.paragraphs, globalOffset, _ExtendType.extend);
    if(blockState == null) return;
    final render = blockState.getRender();
    if(render == null) return;

    final localOffset = render.globalToLocal(globalOffset);
    var (startPos, endPos) = blockState.getWordPosRange(localOffset);
    final blockId = blockState.getBlockId();
    blockState.requestCursorAtPosition(startPos);
    if(startPos != endPos) {
      final node = controller.getBlockDesc(blockId)!;
      var newTextSelection = node.getTextSelection(extentOffset: endPos)!;
      node.setTextSelection(newTextSelection);
      CallbackRegistry.refreshTextEditingValue();
      var render = blockState.getRender()!;
      render.markNeedsPaint();
      Controller.instance.selectionController.showTextSelectionHandles();
    }
  }

  /// Cancel selection and move cursor to the start position
  void collapseToStart() {
    if(lastBaseBlockIndex == lastExtentBlockIndex && lastBaseBlockPos == lastExtentBlockPos) return;
    var (startBlockIndex, startBlockPos) = _getStartIndexAndPosFromLastMember();
    collapseTo(startBlockIndex, startBlockPos);
  }
  void collapseToEnd() {
    if(lastBaseBlockIndex == lastExtentBlockIndex && lastBaseBlockPos == lastExtentBlockPos) return;
    var (endBlockIndex, endBlockPos) = _getEndIndexAndPosFromLastMember();
    collapseTo(endBlockIndex, endBlockPos);
  }
  void collapseTo(int blockIndex, int pos) {
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

    var (startBlockIndex, startBlockPos) = _getStartIndexAndPosFromLastMember();
    var (endBlockIndex, _) = _getEndIndexAndPosFromLastMember();
    for(int idx = startBlockIndex; idx <= endBlockIndex; idx++) {
      final blockState = paragraphs[idx].getEditState();
      if(idx != blockIndex) {
        blockState?.releaseCursor();
      }
    }
    lastBaseBlockIndex = lastExtentBlockIndex = blockIndex;
    lastBaseBlockPos = lastExtentBlockPos = pos;
    paragraphs[blockIndex].getEditState()?.requestCursorAtPosition(pos);
  }

  bool isCollapsed() {
    return isInSingleBlock() && lastBaseBlockPos == lastExtentBlockPos;
  }
  bool isInSingleBlock() {
    return lastBaseBlockIndex == lastExtentBlockIndex;
  }

  // Setters
  void updateContext(BuildContext context) {
    _context = context;
  }
  void updateLayerLink(LayerLink startHandle, LayerLink endHandle) {
    _layerLinkOfStartHandle = startHandle;
    _layerLinkOfEndHandle = endHandle;
  }
  void setShouldShowSelectionHandle(bool _b) {
    _shouldShowSelectionHandle = _b;
  }

  void deleteSelectedContent({bool isExtentEditing = false, int newExtentPos = 0}) {
    if(isCollapsed()) return;
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

    List<String> toBeRemove = [];
    var (startBlockIndex, startBlockPos) = _getStartIndexAndPosFromLastMember();
    var (endBlockIndex, _) = _getEndIndexAndPosFromLastMember();
    String endBlockId = paragraphs[endBlockIndex].getBlockId();
    final startBlockId = paragraphs[startBlockIndex].getBlockId();
    final _ = paragraphs[lastExtentBlockIndex].getBlockId();
    for(int idx = startBlockIndex; idx <= endBlockIndex; idx++) {
      final block = paragraphs[idx];
      final blockState = block.getEditState();
      if(idx != lastBaseBlockIndex && idx != lastExtentBlockIndex) {
        toBeRemove.add(paragraphs[idx].getBlockId());
      } else {
        if(idx != lastExtentBlockIndex || !isExtentEditing) {
          blockState?.deleteSelection();
        }
      }
    }
    if(toBeRemove.isNotEmpty) {
      for(var blockId in toBeRemove) {
        Controller.instance.document?.removeParagraph(blockId);
      }
    }
    if(startBlockIndex != endBlockIndex) {
      final startBlockState = paragraphs[startBlockIndex].getEditState();
      startBlockState?.mergeParagraph(endBlockId);
    }
    if(lastBaseBlockIndex != lastExtentBlockIndex) {
      CallbackRegistry.refreshDoc(activeBlockId: startBlockId, position: startBlockPos + newExtentPos);
    }
    lastExtentBlockIndex = lastBaseBlockIndex = startBlockIndex;
    lastExtentBlockPos = lastBaseBlockPos = startBlockPos + newExtentPos;
  }

  /// Find which block contains the globalPosition
  /// 1. The point is contained in a block
  /// 2. The point is not contained in any block(in the gap between two blocks, or at the top or bottom edge)
  /// +--------+
  /// | block 1|
  /// +--------+
  ///    | position
  /// +--------+
  /// | block 2|
  /// +--------+
  ///   2.1 If the type is base, that means we should return block 2
  ///   2.2 If the type is extend, that means we should return block 1
  ///   * block 1 or block 2 could be null when the position is at the edge
  MindEditBlockState? _findBlockState(List<ParagraphDesc> paragraphs, Offset globalPosition, _ExtendType type) {
    ParagraphDesc? lastPara;
    for(var para in paragraphs) {
      final state = para.getEditState();
      if(state == null) continue;

      final render = state.getRender();
      if(render == null) continue;

      final box = render.currentBox;
      if(box == null) continue;

      if(box.contains(globalPosition)) {
        return state; // Case 1
      }

      if(box.top > globalPosition.dy) {
        if(type == _ExtendType.base) {
          return state; // Case 2.1
        } else {
          return lastPara?.getEditState(); // Case 2.2
        }
      }
      lastPara = para;
    }
    return lastPara?.getEditState(); // Case 2.1 or 2.2
  }

  int _getPosFromRender(MindBlockImplRenderObject render, Offset offset) {
    final localOffset = render.globalToLocal(offset);
    int pos = render.getPositionByOffset(localOffset);
    return pos;
  }

  int _getIndexOfBlock(String? blockId) {
    if(blockId == null) return -1;

    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return -1;
    int idx = 0;
    for(var para in paragraphs) {
      if(para.getBlockId() == blockId) return idx;
      idx++;
    }
    return -1;
  }

  (int, int) _getStartIndexAndPosFromLastMember() {
    return _getStartIndexAndPos(lastBaseBlockIndex, lastBaseBlockPos, lastExtentBlockIndex, lastExtentBlockPos);
  }
  (int, int) _getStartIndexAndPos(int baseIndex, int basePos, int extentIndex, int extentPos) {
    if(baseIndex < extentIndex) {
      return (baseIndex, basePos);
    } else if(baseIndex > extentIndex) {
      return (extentIndex, extentPos);
    }
    return (baseIndex, min(basePos, extentPos));
  }
  (int, int) _getEndIndexAndPosFromLastMember() {
    return _getEndIndexAndPos(lastBaseBlockIndex, lastBaseBlockPos, lastExtentBlockIndex, lastExtentBlockPos);
  }
  (int, int) _getEndIndexAndPos(int baseIndex, int basePos, int extentIndex, int extentPos) {
    if(baseIndex < extentIndex) {
      return (extentIndex, extentPos);
    } else if(baseIndex > extentIndex) {
      return (baseIndex, basePos);
    }
    return (baseIndex, max(basePos, extentPos));
  }
}

enum _ExtendType {
  base,
  extend,
}

enum _HandleType {
  start,
  end,
}

class _HandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();
    paint.color = Colors.blueAccent;
    paint.style = PaintingStyle.fill;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;

    var radius = size.width * 0.5;
    Offset offset = Offset(radius, radius);
    canvas.drawCircle(offset, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}