import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:my_log/my_log.dart';

import '../controller/callback_registry.dart';
import '../controller/controller.dart';

class SelectionController {
  LayerLink? _layerLinkOfStartHandle;
  LayerLink? _layerLinkOfEndHandle;
  BuildContext? _context;
  OverlayEntry? _handleOfStart;
  OverlayEntry? _handleOfEnd;
  bool _shouldShowSelectionHandle = false;

  void dispose() {
    hideTextSelectionHandles();
    _context = null;
    _shouldShowSelectionHandle = false;
    _layerLinkOfStartHandle = null;
    _layerLinkOfEndHandle = null;
  }

  LayerLink? getLayerLinkOfStartHandle() => _layerLinkOfStartHandle;
  LayerLink? getLayerLinkOfEndHandle() => _layerLinkOfEndHandle;

  void showTextSelectionHandles(Offset position) {
    if(!_shouldShowSelectionHandle) {
      return;
    }
    if(_context == null || _handleOfStart != null || _handleOfEnd != null) { // No context or already displayed handles
      return;
    }
    MyLogger.info('SelectionController: add selection overlay handle');
    double _handleSize = 10;
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
  }

  OverlayEntry _buildStartHandle(double _handleSize) {
    return _buildHandle(_handleSize, _layerLinkOfStartHandle!, Offset(-_handleSize / 2, -_handleSize));
  }
  OverlayEntry _buildEndHandle(double _handleSize) {
    return _buildHandle(_handleSize, _layerLinkOfEndHandle!, Offset(-_handleSize / 2, 0));
  }
  OverlayEntry _buildHandle(double _handleSize, LayerLink _link, Offset offset) {
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
        MyLogger.info('selection handle: drag update');
        var _controller = Controller.instance;
        var blockId = _controller.getEditingBlockId();
        if(blockId == null) {
          return;
        }
        var blockState = _controller.getEditingBlockState();
        if(blockState == null) {
          return;
        }
        var render = blockState.getRender();
        var globalOffset = details.globalPosition;
        var localOffset = render!.globalToLocal(globalOffset);
        updateSelectionByOffset(blockId, localOffset);

      },
      onPanEnd: (DragEndDetails details) {
        MyLogger.info('selection handle: drag end');
      },
      onPanCancel: () {
        MyLogger.info('selection handle: drag cancel');
      },
      child: container,
    );
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

  void updateSelectionByOffset(String blockId, Offset offset) {
    final block = Controller.instance.getBlockState(blockId)!;
    final render = block.getRender()!;
    int pos = render.getPositionByOffset(offset);
    final node = Controller.instance.getBlockDesc(blockId)!;
    var newTextSelection = node.getTextSelection(extentOffset: pos);
    if(newTextSelection == null) {
      MyLogger.warn('Unbelievable!!! onPanUpdate: node.getTextSelection returns null!');
    } else {
      node.setTextSelection(newTextSelection);
      CallbackRegistry.refreshTextEditingValue();
      render.markNeedsPaint();
      Controller.instance.selectionController.showTextSelectionHandles(offset);
    }
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