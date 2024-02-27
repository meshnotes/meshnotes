import 'package:flutter/gestures.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import 'controller.dart';

class GestureHandler {
  int _lastTapDownTime = 0;
  String _lastBlockId = '';
  static const int _doubleTapInterval = 300;
  Controller controller;

  GestureHandler({
    required this.controller,
  });

  void onTapOrDoubleTap(TapDownDetails details, String blockId) {
    int now = Util.getTimeStamp();
    if(_lastBlockId == blockId && now - _lastTapDownTime < _doubleTapInterval) {
      _onDoubleTapDown(details, blockId);
      _lastTapDownTime = 0;
      _lastBlockId = '';
    } else {
      _onTapDown(details, blockId);
      _lastBlockId = blockId;
      _lastTapDownTime = now;
    }
  }

  void _onTapDown(TapDownDetails details, String blockId) {
    MyLogger.debug('efantest: onTapDown, blockId=$blockId');
    var offset = details.localPosition;
    final block = controller.getBlockState(blockId)!;
    int pos = block.getRender()!.getPositionByOffset(offset);
    block.requestCursorAtPosition(pos);
  }

  void onPanStart(DragStartDetails details, String blockId) {
    _setShouldShowHandles(details.kind);

    MyLogger.debug('efantest: onPanStart');
    var offset = details.localPosition;
    final block = controller.getBlockState(blockId)!;
    int pos = block.getRender()!.getPositionByOffset(offset);
    block.requestCursorAtPosition(pos);
  }

  void onPanUpdate(DragUpdateDetails details, String blockId) {
    final offset = details.localPosition;
    controller.selectionController.updateSelectionByOffset(blockId, offset);
  }

  void onPanDown(DragDownDetails details, String blockId) {
    // MyLogger.info('efantest onPanDown');
    // var offset = details.localPosition;
    // final block = controller.getBlockState(blockId)!;
    // int pos = block.getRender()!.getPositionByOffset(offset);
    // block.requestCursorAtPosition(pos);
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
    _onSelectWord(details.localPosition, blockId);
  }

  void _onDoubleTapDown(TapDownDetails details, String blockId) {
    _setShouldShowHandles(details.kind);

    _onSelectWord(details.localPosition, blockId);
  }

  void _setShouldShowHandles(PointerDeviceKind? kind) {
    bool _shouldShowSelectionHandle = kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;
    controller.selectionController.setShouldShowSelectionHandle(_shouldShowSelectionHandle);
  }

  void _onSelectWord(Offset offset, String blockId) {
    controller.selectionController.updateSelectionByPosRange(offset, blockId);
  }
}