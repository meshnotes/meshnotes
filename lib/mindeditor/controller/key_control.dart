import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:flutter/services.dart';

const _leftKey   = LogicalKeyboardKey.arrowLeft;
const _rightKey  = LogicalKeyboardKey.arrowRight;
const _upKey     = LogicalKeyboardKey.arrowUp;
const _downKey   = LogicalKeyboardKey.arrowDown;
const _backspaceKey = LogicalKeyboardKey.backspace;
const _deleteKey    = LogicalKeyboardKey.delete;
const _newLineKey   = LogicalKeyboardKey.enter;

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
    return false;
  }

  static bool _handleMoveKeys(LogicalKeyboardKey _key, FunctionKeys funcKeys) {
    var editingState = Controller.instance.getEditingBlockState();
    if(editingState == null) {
      return false;
    }
    if(_key == _leftKey) {
      editingState.moveCursorLeft(funcKeys);
    } else if(_key == _rightKey) {
      editingState.moveCursorRight(funcKeys);
    } else if(_key == _upKey) {
      editingState.moveCursorUp(funcKeys);
    } else if(_key == _downKey) {
      editingState.moveCursorDown(funcKeys);
    }
    return true;
  }

  static bool _handleDelKeys(LogicalKeyboardKey _key, FunctionKeys funcKeys) {
    var editingState = Controller.instance.getEditingBlockState();
    if(editingState == null) {
      return false;
    }
    var block = editingState.widget.texts;
    if(block.getTextSelection() == null) {
      MyLogger.warn('Unbelievable!!! _handleDelKeys(): getTextSelection returns null!');
      return false;
    }
    if(block.isCollapsed() == false) {
      editingState.deleteSelection();
      return true;
    }
    if(_key == _backspaceKey) {
      editingState.deletePreviousCharacter();
    } else if(_key == _deleteKey) {
      editingState.deleteCurrentCharacter();
    }
    return true;
  }

  static bool _handleNewLine(LogicalKeyboardKey _key, FunctionKeys funcKeys) {
    var editingState = Controller.instance.getEditingBlockState();
    if(editingState == null) {
      return false;
    }
    editingState.spawnNewLine();
    return true;
  }
}