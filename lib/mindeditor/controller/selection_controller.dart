import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block_impl.dart';
import 'package:my_log/my_log.dart';
import '../view/edit_cursor.dart';
import 'callback_registry.dart';
import 'controller.dart';

class SelectionController {
  LayerLink? _layerLinkOfStartHandle;
  LayerLink? _layerLinkOfEndHandle;
  LeaderLayer? _leaderLayerOfStartHandle;
  LeaderLayer? _leaderLayerOfEndHandle;
  BuildContext? _context;
  OverlayEntry? _handleOfStart;
  OverlayEntry? _handleOfEnd;
  bool _shouldShowSelectionHandle = false;
  int lastBaseBlockIndex = -1;
  int lastExtentBlockIndex = -1;
  int lastBaseBlockPos = -1;
  int lastExtentBlockPos = -1;
  EditCursor? _editCursor;

  void dispose() {
    _editCursor?.stopCursor();
    _editCursor = null;
    hideTextSelectionHandles();
    _context = null;
    _shouldShowSelectionHandle = false;
    _layerLinkOfStartHandle = _layerLinkOfEndHandle = null;
    lastBaseBlockIndex = -1;
    lastExtentBlockIndex = -1;
    lastBaseBlockPos = -1;
    lastExtentBlockPos = -1;
  }

  void clearSelection() {
    _editCursor?.stopCursor();
    _shouldShowSelectionHandle = false;
    lastBaseBlockIndex = -1;
    lastExtentBlockIndex = -1;
    lastBaseBlockPos = -1;
    lastExtentBlockPos = -1;
  }

  LayerLink? getLayerLinkOfStartHandle() => _layerLinkOfStartHandle;
  LayerLink? getLayerLinkOfEndHandle() => _layerLinkOfEndHandle;

  EditCursor getCursor() {
    _editCursor ??= EditCursor(timeoutFunc: _refreshCursor);
    return _editCursor!;
  }
  void resetCursor() {
    getCursor().resetCursor();
  }
  void releaseCursor() {
    getCursor().stopCursor();
    _releaseCursor();
  }

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
        // Handle circle has an offset from actual point of text line because it is at the bottom of cursor.
        var globalOffset = details.globalPosition + Offset(0, -_handleSize);
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
    Offset offset = Offset(-_handleSize / 2, 0);
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
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

    final blockState = _findBlockState(paragraphs, offset, _ExtendType.extend);
    if(blockState == null) return;

    final blockId = blockState.getBlockId();
    final render = blockState.getRender();
    if(render == null) return;

    int index = _getIndexOfBlock(blockId);
    int pos = _getPosFromRender(render, offset);
    _updateSelection(index, pos, index, pos, paragraphs);
    blockState.requestCursorAtPosition(pos);
  }

  void updateSelectionInBlock(String blockId, TextSelection newSelection) {
    var paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

    int blockIndex = 0;
    for(; blockIndex < paragraphs.length; blockIndex++) {
      if(paragraphs[blockIndex].getBlockId() == blockId) break;
    }
    if(blockIndex >= paragraphs.length) return;
    _updateSelection(blockIndex, newSelection.baseOffset, blockIndex, newSelection.extentOffset, paragraphs);
    var blockState = paragraphs[blockIndex].getEditState();
    blockState?.requestCursorAtPosition(newSelection.extentOffset);
  }

  void updateSelectionByOffset(Offset offset, {_ExtendType type = _ExtendType.extend}) {
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

    final block = _findBlockState(paragraphs, offset, type);
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
      MyLogger.info('updateSelectionByOffset: baseBlockIndex=$baseBlockIndex, baseBlockPos=$baseBlockPos, extentBlockIndex=$extentBlockIndex, extentBlockPos=$extentBlockPos');
      _updateSelection(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos, paragraphs);
    }
  }
  void updateSelectionByIndexAndPos(int blockIndex, int pos, {_ExtendType type = _ExtendType.extend}) {
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;

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
    _updateSelection(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos, paragraphs);
    var blockState = paragraphs[blockIndex].getEditState();
    blockState?.requestCursorAtPosition(pos);
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
    var (wordStartPos, wordEndPos) = blockState.getWordPosRange(localOffset);
    final blockId = blockState.getBlockId();
    updateSelectionInBlock(blockId, TextSelection(baseOffset: wordStartPos, extentOffset: wordEndPos));
    showTextSelectionHandles();
  }

  String getSelectedContent() {
    var paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return '';

    var (startBlockIndex, _) = _getStartIndexAndPosFromLastMember();
    var (endBlockIndex, _) = _getEndIndexAndPosFromLastMember();
    String result = '';
    for(int idx = startBlockIndex; idx <= endBlockIndex; idx++) {
      String plainText = paragraphs[idx].getSelectedPlainText();
      if(result.isNotEmpty) {
        result += '\n' + plainText;
      } else {
        result = plainText;
      }
    }
    return result;
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

    var (startBlockIndex, _) = _getStartIndexAndPosFromLastMember();
    var (endBlockIndex, _) = _getEndIndexAndPosFromLastMember();
    for(int idx = startBlockIndex; idx <= endBlockIndex; idx++) {
      final blockState = paragraphs[idx].getEditState();
      if(idx != blockIndex) {
        blockState?.clearSelectionAndReleaseCursor();
      }
    }
    _updateSelection(blockIndex, pos, blockIndex, pos, paragraphs);
    // lastBaseBlockIndex = lastExtentBlockIndex = blockIndex;
    // lastBaseBlockPos = lastExtentBlockPos = pos;
    var blockState = paragraphs[blockIndex].getEditState();
    blockState?.requestCursorAtPosition(pos);
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
  void updateLeaderLayerOfStartHandle(LeaderLayer _layer) {
    _leaderLayerOfStartHandle = _layer;
  }
  void updateLeaderLayerOfEndHandle(LeaderLayer _layer) {
    _leaderLayerOfEndHandle = _layer;
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

  void _refreshCursor() {
    if(lastExtentBlockIndex < 0) return;
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;
    final block = paragraphs[lastExtentBlockIndex];
    if(!block.hasCursor()) {
      MyLogger.warn('_refreshCursor: Incorrect state! last extent block(id=${block.getBlockId()}, index=$lastExtentBlockIndex) has no cursor!');
      return;
    }
    final blockState = block.getEditState();
    final readOnly = blockState?.widget.readOnly;
    if(readOnly == null || readOnly) return;

    final render = blockState?.getRender();
    render?.markNeedsPaint();
  }
  void _releaseCursor() {
    if(lastExtentBlockIndex < 0) return;
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;
    final block = paragraphs[lastExtentBlockIndex];
    if(!block.hasCursor()) return;
    final render = block.getEditState()?.getRender();
    render?.markNeedsPaint();
  }
  void _updateSelection(int baseBlockIndex, int baseBlockPos, int extentBlockIndex, int extentBlockPos, List<ParagraphDesc> paragraphs) {
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
    // Clear selection first
    for(int idx = startIndex; idx <= endIndex; idx++) {
      /// 1. Clear selection in blocks which are out of range [startBlockIndex, endBlockIndex]
      /// 2. Set selection in start block to be [startBlockPos, length]
      /// 3. Set selection in end block to be [0, endBlockPos]
      /// 4. If start and end block is the same, set the selection to be [startBlockPos, endBlockPos]
      final node = paragraphs[idx];
      if(idx < startBlockIndex || idx > endBlockIndex) {
        node.getEditState()?.clearSelectionAndReleaseCursor();
        continue;
      }
      int startPos = 0, endPos = paragraphs[idx].getPlainText().length;
      if(idx == startBlockIndex) {
        startPos = startBlockPos;
      }
      if(idx == endBlockIndex) {
        endPos = endBlockPos;
      }

      bool showBaseLeader = false;
      bool showExtentLeader = false;
      bool isEditing = false;
      int basePos = startPos;
      int extentPos = endPos;
      if(idx == baseBlockIndex) {
        showBaseLeader = true;
        if(startPos != baseBlockPos) {
          basePos = endPos;
          extentPos = startPos;
        }
      }
      if(idx == extentBlockIndex) {
        showExtentLeader = true;
        isEditing = true;
        if(endPos != extentBlockPos) {
          basePos = endPos;
          extentPos = startPos;
        }
      }
      node.setTextSelection(
          TextSelection(baseOffset: basePos, extentOffset: extentPos),
          isEditing: isEditing,
          showBaseLeader: showBaseLeader,
          showExtentLeader: showExtentLeader
      );
      node.getEditState()?.getRender()?.markNeedsPaint();
    }
    lastBaseBlockIndex = baseBlockIndex;
    lastBaseBlockPos = baseBlockPos;
    lastExtentBlockIndex = extentBlockIndex;
    lastExtentBlockPos = extentBlockPos;
    CallbackRegistry.refreshTextEditingValue();
    resetCursor();
    Controller.instance.selectionController.showTextSelectionHandles();
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