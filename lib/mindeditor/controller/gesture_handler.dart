import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';

class GestureHandler {
  Controller controller;

  GestureHandler({
    required this.controller,
  });

  void onTapDown(TapDownDetails details, String blockId) {
    MyLogger.debug('efantest: onTapDown');
    var offset = details.localPosition;
    final block = controller.getBlockState(blockId)!;
    int pos = block.getRender()!.getPositionByOffset(offset);
    block.requestCursorAtPosition(pos);
  }

  void onPanStart(DragStartDetails details, String blockId) {
    MyLogger.debug('efantest: onPanStart');
    var offset = details.localPosition;
    final block = controller.getBlockState(blockId)!;
    int pos = block.getRender()!.getPositionByOffset(offset);
    block.requestCursorAtPosition(pos);
  }

  void onPanUpdate(DragUpdateDetails details, String blockId) {
    final offset = details.localPosition;
    final block = controller.getBlockState(blockId)!;
    final render = block.getRender()!;
    int pos = render.getPositionByOffset(offset);
    final node = controller.getBlockDesc(blockId)!;
    var newTextSelection = node.getTextSelection(extentOffset: pos);
    if(newTextSelection == null) {
      MyLogger.warn('Unbelievable!!! onPanUpdate: node.getTextSelection returns null!');
    } else {
      node.setTextSelection(newTextSelection);
      CallbackRegistry.refreshTextEditingValue();
      render.markNeedsPaint();
    }
  }

  void onPanDown(DragDownDetails details, String blockId) {
    MyLogger.info('efantest onPanDown');
    var offset = details.localPosition;
    final block = controller.getBlockState(blockId)!;
    int pos = block.getRender()!.getPositionByOffset(offset);
    block.requestCursorAtPosition(pos);
  }

  void onPanCancel(String blockId) {
    var textSelection = controller.getBlockDesc(blockId)!.getTextSelection();
    if(textSelection != null && textSelection.isCollapsed) {
      final block = controller.getBlockState(blockId)!;
      block.requestCursorAtPosition(textSelection.extentOffset);
      block.getRender()!.markNeedsPaint();
    }
  }
}