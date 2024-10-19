import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block_impl.dart';
import 'package:mesh_note/mindeditor/view/toolbar/popup_toolbar.dart';
import 'package:my_log/my_log.dart';
import '../view/edit_cursor.dart';
import '../view/selection_handle_layer.dart';
import 'callback_registry.dart';
import 'controller.dart';

class SelectionController {
  bool _shouldShowSelectionHandle = false;
  int lastBaseBlockIndex = -1;
  int lastExtentBlockIndex = -1;
  int lastBaseBlockPos = -1;
  int lastExtentBlockPos = -1;
  EditCursor? _editCursor;
  Offset baseHandleOffset = Offset.zero;
  Offset extentHandleOffset = Offset.zero;
  final SelectionHandleLayer _selectionHandleLayer = SelectionHandleLayer();

  SelectionController() {
    // Controller().evenTasksManager.registerEditingTask();
  }

  void dispose() {
    _selectionHandleLayer.dispose();
    clearSelection();
    releaseCursor();
    _editCursor = null;
  }

  void clearSelection() {
    _editCursor?.stopCursor();
    _shouldShowSelectionHandle = false;
    lastBaseBlockIndex = -1;
    lastExtentBlockIndex = -1;
    lastBaseBlockPos = -1;
    lastExtentBlockPos = -1;
    baseHandleOffset = Offset.zero;
    extentHandleOffset = Offset.zero;
  }

  EditCursor getCursor() {
    _editCursor ??= EditCursor(refreshFunc: _refreshCursor);
    return _editCursor!;
  }
  void resetCursor() {
    getCursor().resetCursor();
  }
  void releaseCursor() {
    _editCursor?.stopCursor();
    _releaseCursor();
  }

  void requestCursorAtGlobalOffset(Offset offset) {
    final paragraphs = Controller().document?.paragraphs;
    if(paragraphs == null) return;

    final blockState = _findBlockState(paragraphs, offset, SelectionExtentType.extent);
    if(blockState == null) return;

    final blockId = blockState.getBlockId();
    final render = blockState.getRender();
    if(render == null) return;

    int index = _getIndexOfBlock(blockId);
    int pos = _getPosFromRender(render, offset);
    _updateSelection(index, pos, index, pos, paragraphs);
    blockState.setEditingBlockAndResetCursor(forceShowKeyboard: true);
  }

  void updateSelectionInBlock(String blockId, TextSelection newSelection, bool requestKeyboard) {
    var paragraphs = Controller().document?.paragraphs;
    if(paragraphs == null) return;

    int blockIndex = 0;
    for(; blockIndex < paragraphs.length; blockIndex++) {
      if(paragraphs[blockIndex].getBlockId() == blockId) break;
    }
    if(blockIndex >= paragraphs.length) return;
    _updateSelection(blockIndex, newSelection.baseOffset, blockIndex, newSelection.extentOffset, paragraphs);
    var blockState = paragraphs[blockIndex].getEditState();
    blockState?.setEditingBlockAndResetCursor(requestKeyboard: requestKeyboard);
  }
  void collapseInBlock(String blockId, int position, bool requestKeyboard) {
    updateSelectionInBlock(
      blockId,
      TextSelection(
        baseOffset: position,
        extentOffset: position,
      ),
      requestKeyboard,
    );
  }
  void updateSelectionByIMESelection(String blockId, int leadingPositionBeforeIME, TextSelection selection) {
    updateSelectionInBlock(
      blockId,
      TextSelection(
        baseOffset: leadingPositionBeforeIME + selection.baseOffset,
        extentOffset: leadingPositionBeforeIME + selection.extentOffset,
      ),
      false,
    );
  }
  /// Only use when there's no corresponding MindEditBlockState yet.
  /// This scenario is only happened in editing or pasting multi-line texts.
  void updateSelectionWithoutBlockState(String blockId, TextSelection newSelection) {
    final controller = Controller();
    var paragraphs = controller.document?.paragraphs;
    if(paragraphs == null) return;

    int blockIndex = 0;
    for(; blockIndex < paragraphs.length; blockIndex++) {
      if(paragraphs[blockIndex].getBlockId() == blockId) break;
    }
    if(blockIndex >= paragraphs.length) return;
    _updateSelection(blockIndex, newSelection.baseOffset, blockIndex, newSelection.extentOffset, paragraphs);
    controller.setEditingBlockId(blockId);
    resetCursor();
    CallbackRegistry.requestKeyboard();
  }

  void updateSelectionByOffset(Offset offset, {SelectionExtentType type = SelectionExtentType.extent}) {
    final paragraphs = Controller().document?.paragraphs;
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
        case SelectionExtentType.base:
          baseBlockIndex = index;
          baseBlockPos = pos;
          break;
        case SelectionExtentType.extent:
          extentBlockIndex = index;
          extentBlockPos = pos;
          break;
        case SelectionExtentType.cursor:
          baseBlockIndex = index;
          baseBlockPos = pos;
          extentBlockIndex = index;
          extentBlockPos = pos;
          break;
      }
      MyLogger.info('updateSelectionByOffset: baseBlockIndex=$baseBlockIndex, baseBlockPos=$baseBlockPos, extentBlockIndex=$extentBlockIndex, extentBlockPos=$extentBlockPos');
      _updateSelection(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos, paragraphs);
      var blockState = paragraphs[extentBlockIndex].getEditState();
      blockState?.setEditingBlockAndResetCursor();
    }
  }
  void updateSelectionByIndexAndPos(int blockIndex, int pos, {SelectionExtentType type = SelectionExtentType.extent}) {
    final paragraphs = Controller().document?.paragraphs;
    if(paragraphs == null) return;

    int baseBlockIndex = lastBaseBlockIndex;
    int baseBlockPos = lastBaseBlockPos;
    int extentBlockIndex = lastExtentBlockIndex;
    int extentBlockPos = lastExtentBlockPos;
    switch(type) {
      case SelectionExtentType.base:
        baseBlockIndex = blockIndex;
        baseBlockPos = pos;
        break;
      case SelectionExtentType.extent:
      case SelectionExtentType.cursor: // Impossible
        extentBlockIndex = blockIndex;
        extentBlockPos = pos;
        break;
    }
    _updateSelection(baseBlockIndex, baseBlockPos, extentBlockIndex, extentBlockPos, paragraphs);
    var blockState = paragraphs[blockIndex].getEditState();
    blockState?.setEditingBlockAndResetCursor();
  }

  void updateSelectionByPosRange(Offset globalOffset) {
    final controller = Controller();
    final document = controller.document;
    if(document == null) return;

    final blockState = _findBlockState(document.paragraphs, globalOffset, SelectionExtentType.extent);
    if(blockState == null) return;
    final render = blockState.getRender();
    if(render == null) return;

    final localOffset = render.globalToLocal(globalOffset);
    var (wordStartPos, wordEndPos) = blockState.getWordPosRange(localOffset);
    final blockId = blockState.getBlockId();
    updateSelectionInBlock(blockId, TextSelection(baseOffset: wordStartPos, extentOffset: wordEndPos), true);
    // _showOrHideSelectionHandles();
  }

  int getStartPos() {
    var (_, startPos) = _getStartIndexAndPosFromLastMember();
    return startPos;
  }
  String getSelectedContent() {
    final controller = Controller();
    final paragraphs = controller.document?.paragraphs;
    if(paragraphs == null) return '';

    var (startBlockIndex, _) = _getStartIndexAndPosFromLastMember();
    var (endBlockIndex, _) = _getEndIndexAndPosFromLastMember();
    String result = '';
    if(startBlockIndex < 0) return result;
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
    final controller = Controller();
    final paragraphs = controller.document?.paragraphs;
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
    var blockState = paragraphs[blockIndex].getEditState();
    blockState?.setEditingBlockAndResetCursor();
  }

  bool isCollapsed() {
    return isInSingleBlock() && lastBaseBlockPos == lastExtentBlockPos;
  }
  bool isInSingleBlock() {
    return lastBaseBlockIndex == lastExtentBlockIndex;
  }

  // Setters
  void updateContext(BuildContext context) {
    _selectionHandleLayer.updateContext(context);
  }
  void updateBaseHandlePoint(Offset offset) {
    _selectionHandleLayer.updateBaseHandleOffset(offset);
  }
  void updateExtentHandlePoint(Offset offset) {
    _selectionHandleLayer.updateExtentHandleOffset(offset);
  }
  void updateHandlesPointByDelta(Offset delta) {
    _selectionHandleLayer.updateBaseHandleOffsetByDelta(delta);
    _selectionHandleLayer.updateExtentHandleOffsetByDelta(delta);
  }
  void setShouldShowSelectionHandle(bool _b) {
    MyLogger.info('setShouldShowSelectionHandle: $_b');
    _shouldShowSelectionHandle = _b;
  }

  void showPopupMenu({required Offset position, required LayerLink layerLink}) {
    CallbackRegistry.getFloatingViewManager()?.clearPopupMenu();
    final widget = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final popupMenu = PopupToolbar.basic(controller: Controller(), context: context, maxWidth: width);
        final container = Container(
          constraints: BoxConstraints(minWidth: width, maxWidth: width, maxHeight: 50),
          child: Container(
            alignment: Alignment.center,
            child: popupMenu,
          ),
        );
        final follower = CompositedTransformFollower(
          link: layerLink,
          child: container,
          offset: Offset(width / 2 -position.dx, 10),
          targetAnchor: Alignment.center,
          followerAnchor: Alignment.topCenter,
        );
        return follower;
      },
    );
    CallbackRegistry.getFloatingViewManager()?.addPopupMenu(widget);
  }

  void deleteSelectedContent({bool keepExtentBlock = false, int deltaPos = 0, bool refreshView=true}) {
    if(isCollapsed()) return;
    final controller = Controller();
    final paragraphs = controller.document?.paragraphs;
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
        // If isExtentEditing is true, that means this method is invoked from _updateAndSaveText() method.
        // So leave the extent block, because it will be handled in _updateAndSaveText() method.
        if(idx != lastExtentBlockIndex || !keepExtentBlock) {
          blockState?.deleteSelection(needRefreshEditingValue: false);
        }
      }
    }
    if(toBeRemove.isNotEmpty) {
      for(var blockId in toBeRemove) {
        controller.document?.removeParagraph(blockId);
      }
    }
    if(startBlockIndex != endBlockIndex) {
      final startBlockState = paragraphs[startBlockIndex].getEditState();
      startBlockState?.mergeParagraph(endBlockId);
    }
    if(lastBaseBlockIndex != lastExtentBlockIndex) {
      controller.setEditingBlockId(startBlockId);
      if(refreshView) {
        // If select from up to bottom, the the new extent position should consider the start position of base block.
        // Because start block and end block has merged.
        CallbackRegistry.refreshDoc(activeBlockId: startBlockId, position: startBlockPos + deltaPos);
      }
    }
    lastExtentBlockIndex = lastBaseBlockIndex = startBlockIndex;
    lastExtentBlockPos = lastBaseBlockPos = startBlockPos + deltaPos;
    if(refreshView) {
      _showOrHideSelectionHandles(null, null);
    }
  }

  void _refreshCursor() {
    if(lastExtentBlockIndex < 0) return;
    final controller = Controller();
    final paragraphs = controller.document?.paragraphs;
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
    if(render != null && render.attached) {
      render.markNeedsPaint();
    }
  }
  void _releaseCursor() {
    if(lastExtentBlockIndex < 0) return;
    final controller = Controller();
    final paragraphs = controller.document?.paragraphs;
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
    MindBlockImplRenderObject? baseRender, extentRender;
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
      final currentRender = node.getEditState()?.getRender();
      if(idx == baseBlockIndex) {
        showBaseLeader = true;
        if(startPos != baseBlockPos) { // Swap if base position is not at the start position
          basePos = endPos;
          extentPos = startPos;
        }
        baseRender = currentRender;
      }
      if(idx == extentBlockIndex) {
        showExtentLeader = true;
        isEditing = true;
        if(endPos != extentBlockPos) { // Swap if extent position is not at the end position
          basePos = endPos;
          extentPos = startPos;
        }
        extentRender = currentRender;
      }
      node.setTextSelection(
        TextSelection(baseOffset: basePos, extentOffset: extentPos),
        isEditing: isEditing,
        showBaseLeader: showBaseLeader,
        showExtentLeader: showExtentLeader
      );
      currentRender?.markNeedsPaint();
    }
    lastBaseBlockIndex = baseBlockIndex;
    lastBaseBlockPos = baseBlockPos;
    lastExtentBlockIndex = extentBlockIndex;
    lastExtentBlockPos = extentBlockPos;
    // CallbackRegistry.refreshTextEditingValue();
    resetCursor();

    // Update handles' offsets
    Offset? baseCursorOffset, extentCursorOffset;
    if(baseRender != null) {
      baseCursorOffset = baseRender.getCursorOffsetOfPos(lastBaseBlockPos);
    }
    if(extentRender != null) {
      extentCursorOffset = extentRender.getCursorOffsetOfPos(lastExtentBlockPos);
    }
    _showOrHideSelectionHandles(baseCursorOffset, extentCursorOffset);
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
  MindEditBlockState? _findBlockState(List<ParagraphDesc> paragraphs, Offset globalPosition, SelectionExtentType type) {
    ParagraphDesc? lastPara;
    var pairs = CallbackRegistry.getActiveBlockIndexRange();
    if(pairs == null) return null;

    var (start, end) = pairs;
    if(start == -1 || end == -1) return null;

    for(int idx = start; idx <= end; idx++) {
      final para = paragraphs[idx];
      final state = para.getEditState();
      if(state == null) continue;

      final render = state.getRender();
      if(render == null) continue;

      if(!render.attached) continue;

      // final topLeft = render.semanticBounds.topLeft;
      // final bottomRight = render.semanticBounds.bottomRight;
      // final box = Rect.fromPoints(render.localToGlobal(topLeft), render.localToGlobal(bottomRight));
      final box = render.getCurrentBox();
      if(box == null) continue;

      if(box.contains(globalPosition)) {
        return state; // Case 1
      }

      if(box.top > globalPosition.dy) {
        if(type == SelectionExtentType.base) {
          return state; // Case 2.1
        } else {
          return lastPara?.getEditState(); // Case 2.2
        }
      }
      lastPara = para;
    }
    return lastPara?.getEditState(); // Case 2.1 or 2.2
  }

  void _showOrHideSelectionHandles(Offset? baseCursorOffset, Offset? extentCursorOffset) {
    if(_shouldShowSelectionHandle) {
      if(isCollapsed()) {
        _selectionHandleLayer.showOrUpdateCursorHandle(extentCursorOffset);
      } else {
        _selectionHandleLayer.showOrUpdateTextSelectionHandles(baseCursorOffset, extentCursorOffset);
      }
    } else {
      if(!_selectionHandleLayer.isDragging()) {
        _selectionHandleLayer.hide();
      }
    }
  }

  int _getPosFromRender(MindBlockImplRenderObject render, Offset offset) {
    final localOffset = render.globalToLocal(offset);
    int pos = render.getPositionByOffset(localOffset);
    return pos;
  }

  int _getIndexOfBlock(String? blockId) {
    if(blockId == null) return -1;

    final controller = Controller();
    final paragraphs = controller.document?.paragraphs;
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
  static (int, int) _getStartIndexAndPos(int baseIndex, int basePos, int extentIndex, int extentPos) {
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

enum SelectionExtentType {
  base,
  extent,
  cursor,
}
