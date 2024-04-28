import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:flutter/services.dart';
import '../document/paragraph_desc.dart';
import 'callback_registry.dart';
import 'selection_controller.dart';

const _leftKey   = LogicalKeyboardKey.arrowLeft;
const _rightKey  = LogicalKeyboardKey.arrowRight;
const _upKey     = LogicalKeyboardKey.arrowUp;
const _downKey   = LogicalKeyboardKey.arrowDown;
const _backspaceKey = LogicalKeyboardKey.backspace;
const _deleteKey    = LogicalKeyboardKey.delete;
const _newLineKey   = LogicalKeyboardKey.enter;
const _cancelKey    = LogicalKeyboardKey.escape;

class FunctionKeys {
  bool altPressed;
  bool ctrlPressed;
  bool metaPressed;
  bool shiftPressed;

  FunctionKeys(bool alt, bool ctrl, bool meta, bool shift):
    altPressed = alt,
    ctrlPressed = ctrl,
    metaPressed = meta,
    shiftPressed = shift
  ;

  bool nothing() {
    return !(altPressed || ctrlPressed || metaPressed || shiftPressed);
  }
}
class KeyboardControl {
  static final _moveKeys = <LogicalKeyboardKey>{
    _rightKey,
    _leftKey,
    _upKey,
    _downKey,
  };
  static final _delKeys = <LogicalKeyboardKey> {
    _backspaceKey, _deleteKey,
  };

  static bool handleKeyDown(LogicalKeyboardKey _key, bool alt, bool ctrl, bool meta, bool shift) {
    var funcKeys = FunctionKeys(alt, ctrl, meta, shift);
    if(_moveKeys.contains(_key)) {
      return _handleMoveKeys(_key, funcKeys);
    }
    if(_delKeys.contains(_key)) {
      return _handleDelKeys(_key, funcKeys);
    }
    if(_newLineKey == _key) {
      return _handleNewLine(_key, funcKeys);
    }
    if(_cancelKey == _key) {
      MyLogger.info('ESC pressed');
      return false;
    }
    return false;
  }

  static bool _handleMoveKeys(LogicalKeyboardKey _key, FunctionKeys funcKeys) {
    CallbackRegistry.activeCursorClear();
    if(_key == _leftKey) {
      _moveCursorLeft(funcKeys);
    } else if(_key == _rightKey) {
      _moveCursorRight(funcKeys);
    } else if(_key == _upKey) {
      _moveCursorUp(funcKeys);
    } else if(_key == _downKey) {
      _moveCursorDown(funcKeys);
    }
    return true;
  }

  static bool _handleDelKeys(LogicalKeyboardKey _key, FunctionKeys funcKeys) {
    final selectionController = Controller.instance.selectionController;
    if(!selectionController.isCollapsed()) {
      selectionController.deleteSelectedContent();
      return true;
    }
    var editingState = Controller.instance.getEditingBlockState();
    if(editingState == null) {
      return false;
    }
    if(_key == _backspaceKey) {
      MyLogger.debug('_handleDelKeys: try to delete previous character');
      editingState.deletePreviousCharacter();
    } else if(_key == _deleteKey) {
      MyLogger.debug('_handleDelKeys: try to delete current character');
      editingState.deleteCurrentCharacter();
    }
    return true;
  }

  static bool _handleNewLine(LogicalKeyboardKey _key, FunctionKeys funcKeys) {
    MyLogger.info('_handleNewLine: spawn new line');
    if(!Controller.instance.selectionController.isCollapsed()) {
      Controller.instance.selectionController.deleteSelectedContent();
    }
    var editingState = Controller.instance.getEditingBlockState();
    if(editingState == null) {
      return false;
    }
    editingState.spawnNewLine();
    return true;
  }

  static void _moveCursorLeft(FunctionKeys funcKeys) {
    final selectionController = Controller.instance.selectionController;
    // If currently in selection state, and SHIFT key is not pressed, cancel selection and move to left side of selection
    if(!selectionController.isCollapsed() && funcKeys.nothing()) {
      selectionController.collapseToStart();
      return;
    }

    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;
    // Find the left position, it may at the end of previous block
    var (newBlockIndex, newPos) = _findPreviousBlockIdAndPos(selectionController, paragraphs);
    if(newBlockIndex < 0 || newPos < 0) return; // Invalid return values

    if(!funcKeys.shiftPressed) {
      selectionController.collapseTo(newBlockIndex, newPos);
    } else {
      selectionController.updateSelectionByIndexAndPos(newBlockIndex, newPos);
    }
  }
  static void _moveCursorRight(FunctionKeys funcKeys) {
    final selectionController = Controller.instance.selectionController;
    // If currently in selection state, and SHIFT key is not pressed, cancel selection and move to right side of selection
    if(!selectionController.isCollapsed() && funcKeys.nothing()) {
      selectionController.collapseToEnd();
      return;
    }

    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;
    // Find the right position, it may at the beginning of next block
    var (newBlockIndex, newPos) = _findNextBlockIdAndPos(selectionController, paragraphs);
    if(newBlockIndex < 0 || newPos < 0) return;

    if(!funcKeys.shiftPressed) {
      selectionController.collapseTo(newBlockIndex, newPos);
    } else {
      selectionController.updateSelectionByIndexAndPos(newBlockIndex, newPos);
    }
  }
  static void _moveCursorUp(FunctionKeys funcKeys) {
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;
    final selectionController = Controller.instance.selectionController;
    // Find the position at the previous line
    var (newBlockIndex, newPos) = _findBlockIdAndPosAtPreviousLine(selectionController, paragraphs);
    if(newBlockIndex < 0 || newPos < 0) return;

    if(!funcKeys.shiftPressed) {
      selectionController.collapseTo(newBlockIndex, newPos);
    } else {
      selectionController.updateSelectionByIndexAndPos(newBlockIndex, newPos);
    }
  }
  static void _moveCursorDown(FunctionKeys funcKeys) {
    final paragraphs = Controller.instance.document?.paragraphs;
    if(paragraphs == null) return;
    final selectionController = Controller.instance.selectionController;
    // Find the position at the next line
    var (newBlockIndex, newPos) = _findBlockIdAndPosAtNextLine(selectionController, paragraphs);
    if(newBlockIndex < 0 || newPos < 0) return;

    if(!funcKeys.shiftPressed) {
      selectionController.collapseTo(newBlockIndex, newPos);
    } else {
      selectionController.updateSelectionByIndexAndPos(newBlockIndex, newPos);
    }
  }

  static (int, int) _findPreviousBlockIdAndPos(SelectionController selectionController, List<ParagraphDesc> paragraphs) {
    int blockIndex = selectionController.lastExtentBlockIndex;
    int pos = selectionController.lastExtentBlockPos;
    if(pos > 0) {
      pos--;
    } else {
      if(blockIndex > 0) {
        blockIndex--;
        pos = paragraphs[blockIndex].getTotalLength();
      }
    }
    return (blockIndex, pos);
  }
  static (int, int) _findNextBlockIdAndPos(SelectionController selectionController, List<ParagraphDesc> paragraphs) {
    int blockIndex = selectionController.lastExtentBlockIndex;
    int pos = selectionController.lastExtentBlockPos;
    int totalLength = paragraphs[blockIndex].getTotalLength();
    if(pos < totalLength) {
      pos++;
    } else {
      if(blockIndex < paragraphs.length - 1) {
        blockIndex++;
        pos = 0;
      }
    }
    return (blockIndex, pos);
  }
  /// Find the blockIndex and pos of previous line.
  /// If it is not at the same block, calculate the corresponding block index and pos of previous block.
  /// If it is already at the first block, locate at the start position of first block.
  static (int, int) _findBlockIdAndPosAtPreviousLine(SelectionController selectionController, List<ParagraphDesc> paragraphs) {
    int blockIndex = selectionController.lastExtentBlockIndex;
    int pos = selectionController.lastExtentBlockPos;
    var blockState = paragraphs[blockIndex].getEditState()!;
    var render = blockState.getRender()!;
    var offset = render.getOffsetOfNthCharacter(pos);
    var lineHeight = render.fontSize;
    var offsetOfPreviousLine = Offset(offset.dx, offset.dy - lineHeight);
    // Previous line is in the same block
    if(render.paragraph.size.contains(offsetOfPreviousLine)) {
      int newPos = render.getPositionByOffset(offsetOfPreviousLine);
      return (blockIndex, newPos);
    }
    // Not in the same block, but still has previous block, so locate to the last line of previous block, and try to keep dx unchanged
    if(blockIndex > 0) {
      int newBlockIndex = blockIndex - 1;
      var newBlockState = paragraphs[newBlockIndex].getEditState()!;
      var newRender = newBlockState.getRender()!;
      var globalOffset = render.localToGlobal(offsetOfPreviousLine);
      var newOffset = newRender.globalToLocal(globalOffset);
      int newPos = newRender.getPositionByOffset(newOffset);
      return (newBlockIndex, newPos);
    }
    // Not in the same block, and it is already the first block, locate to the start position of current block
    return (0, 0);
  }
  /// Find the blockIndex and pos of next line.
  /// If it is not at the same block, calculate the corresponding block index and pos of new block.
  /// If it is already at the last block, locate at the end position of last block.
  static (int, int) _findBlockIdAndPosAtNextLine(SelectionController selectionController, List<ParagraphDesc> paragraphs) {
    int blockIndex = selectionController.lastExtentBlockIndex;
    int pos = selectionController.lastExtentBlockPos;
    var blockState = paragraphs[blockIndex].getEditState()!;
    var render = blockState.getRender()!;
    var offset = render.getOffsetOfNthCharacter(pos);
    var lineHeight = render.fontSize;
    var offsetOfNextLine = Offset(offset.dx, offset.dy + lineHeight);
    // Previous line is in the same block
    if(render.paragraph.size.contains(offsetOfNextLine)) {
      int newPos = render.getPositionByOffset(offsetOfNextLine);
      return (blockIndex, newPos);
    }
    // Not in the same block, but still has next block, so locate to the first line of next block, and try to keep dx unchanged
    if(blockIndex < paragraphs.length - 1) {
      int newBlockIndex = blockIndex + 1;
      var newBlockState = paragraphs[newBlockIndex].getEditState()!;
      var newRender = newBlockState.getRender()!;
      var globalOffset = render.localToGlobal(offsetOfNextLine);
      var newOffset = newRender.globalToLocal(globalOffset);
      int newPos = newRender.getPositionByOffset(newOffset);
      return (newBlockIndex, newPos);
    }
    // Not in the same block, and it is already the last block, locate to the end position of current block
    return (blockIndex, paragraphs[blockIndex].getTotalLength());
  }
}