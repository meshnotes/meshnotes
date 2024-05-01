import 'package:flutter/gestures.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import 'controller.dart';

class GestureHandler {
  int _lastTapDownTime = 0;
  Offset? _lastClickOffset;
  static const int _doubleTapInterval = 300;
  static const double _maxOffsetDelta = 10.0;
  Controller controller;

  GestureHandler({
    required this.controller,
  });

  void onTapOrDoubleTap(TapDownDetails details) {
    int now = Util.getTimeStamp();
    var globalOffset = details.globalPosition;
    if(_lastClickOffset != null && (_lastClickOffset! - globalOffset).distance < _maxOffsetDelta && now - _lastTapDownTime < _doubleTapInterval) {
      _onDoubleTapDown(details);
      _lastClickOffset = null;
      _lastTapDownTime = 0;
    } else {
      _onTapDown(details);
      _lastClickOffset = globalOffset;
      _lastTapDownTime = now;
    }
  }

  void _onTapDown(TapDownDetails details) {
    final globalOffset = details.globalPosition;
    MyLogger.debug('onTapDown, offset=$globalOffset');
    // Should close IME to clear the composing texts
    CallbackRegistry.rudelyCloseIME();
    controller.selectionController.requestCursorAtGlobalOffset(globalOffset);
  }

  void onPanStart(DragStartDetails details) {
    _setShouldShowHandles(details.kind);

    final globalOffset = details.globalPosition;
    MyLogger.debug('onPanStart, offset=$globalOffset');
    // Should close IME to clear the composing texts
    CallbackRegistry.rudelyCloseIME();
    controller.selectionController.updateSelectionByOffset(globalOffset);
  }

  void onPanUpdate(DragUpdateDetails details) {
    final globalOffset = details.globalPosition;
    MyLogger.debug('onPanUpdate, offset=$globalOffset');
    controller.selectionController.updateSelectionByOffset(globalOffset);
  }

  void onPanDown(DragDownDetails details) {
    var globalOffset = details.globalPosition;
    MyLogger.debug('onPanDown: offset=$globalOffset');
    // Should close IME to clear the composing texts
    CallbackRegistry.rudelyCloseIME();
    controller.selectionController.requestCursorAtGlobalOffset(globalOffset);
  }

  void onPanCancel(String blockId) {
    // var textSelection = controller.getBlockDesc(blockId)!.getTextSelection();
    // if(textSelection != null && textSelection.isCollapsed) {
    //   final block = controller.getBlockState(blockId)!;
    //   block.requestCursorAtPosition(textSelection.extentOffset);
    //   block.getRender()!.markNeedsPaint();
    // }
  }

  void onLongPressDown(LongPressDownDetails details, String blockId) {
    _setShouldShowHandles(details.kind);
  }

  void onLongPressStart(LongPressStartDetails details, String blockId) {
    _onSelectWord(details.globalPosition);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _setShouldShowHandles(details.kind);
    // Should close IME to clear the composing texts
    CallbackRegistry.rudelyCloseIME();
    _onSelectWord(details.globalPosition);
  }

  void _setShouldShowHandles(PointerDeviceKind? kind) {
    bool _shouldShowSelectionHandle = kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;
    controller.selectionController.setShouldShowSelectionHandle(_shouldShowSelectionHandle);
  }

  void _onSelectWord(Offset offset) {
    controller.selectionController.updateSelectionByPosRange(offset);
  }
}