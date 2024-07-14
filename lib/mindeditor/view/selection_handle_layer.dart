import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/view/floating_view.dart';
import 'package:my_log/my_log.dart';

import '../controller/controller.dart';
import '../controller/selection_controller.dart';

class SelectionHandleLayer {
  Widget? _handleOfStart;
  Widget? _handleOfEnd;
  _PositionedHandleState? _handleStateOfBase;
  _PositionedHandleState? _handleStateOfExtent;
  BuildContext? _context;
  Offset? _baseHandleOffset;
  Offset? _extentHandleOffset;
  static const _handleSize = 16.0;
  static const _handleDragSize = 32.0;
  bool _isDragging = false;

  bool isDragging() => _isDragging;

  void dispose() {
    //TODO should optimize here, _context should be cleared when dispose. But current implementation will cover the valid _context, because
    //TODO old MindEditFieldState.dispose() will invoked after new MindEditFieldState.initState()
    // _context = null;
    hideTextSelectionHandles();
    _baseHandleOffset = null;
    _extentHandleOffset = null;
  }

  void updateContext(BuildContext context) {
    _context = context;
  }
  void updateBaseHandleOffset(Offset? offset) {
    if(offset == null) return;
    _baseHandleOffset = offset + const Offset(-_handleDragSize / 2, 0);
    _handleStateOfBase?.updatePosition(_baseHandleOffset!);
  }
  void updateExtentHandleOffset(Offset? offset) {
    if(offset == null) return;
    _extentHandleOffset = offset + const Offset(-_handleDragSize / 2, 0);
    _handleStateOfExtent?.updatePosition(_extentHandleOffset!);
  }
  void updateBaseHandleOffsetByDelta(Offset delta) {
    _handleStateOfBase?.updatePositionByDelta(delta);
  }
  void updateExtentHandleOffsetByDelta(Offset delta) {
    _handleStateOfExtent?.updatePositionByDelta(delta);
  }
  void updateHandleStateOfBase(_PositionedHandleState state) {
    _handleStateOfBase = state;
  }
  void updateHandleStateOfExtent(_PositionedHandleState state) {
    _handleStateOfExtent = state;
  }
  Offset? convertGlobalOffsetToSelectionLayer(Offset global) {
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    return floatingViewManager?.convertGlobalOffsetToSelectionLayer(global);
  }

  void hide() {
    hideTextSelectionHandles();
  }
  void showTextSelectionHandles() {
    if(_context == null || _handleOfStart != null || _handleOfEnd != null) { // No context or already displayed handles
      return;
    }
    if(_baseHandleOffset == null || _extentHandleOffset == null) {
      return;
    }
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    if(floatingViewManager != null) {
      _handleOfStart = _buildStartHandle();
      _handleOfEnd = _buildEndHandle();
      floatingViewManager.addSelectionHandles(_handleOfStart!, _handleOfEnd!);
    }
  }

  void hideTextSelectionHandles() {
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    if(_handleOfStart != null && _handleOfEnd != null) {
      floatingViewManager?.removeSelectionHandles(_handleOfStart!, _handleOfEnd!);
    }
    _handleOfStart = null;
    _handleStateOfBase = null;
    _handleOfEnd = null;
    _handleStateOfExtent = null;
    _isDragging = false;
  }

  Widget _buildStartHandle() {
    return _buildHandle(SelectionExtentType.base);
  }
  Widget _buildEndHandle() {
    return _buildHandle(SelectionExtentType.extent);
  }
  Widget _buildHandle(SelectionExtentType type) {
    var paintContainer = Container(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _handleSize,
        height: _handleSize,
        child: CustomPaint(
          painter: _HandlePainter(),
        ),
      ),
    );
    var dragContainer = Container(
      width: _handleDragSize,
      height: _handleDragSize,
      alignment: Alignment.topCenter,
      child: paintContainer,
    );
    var gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (DragStartDetails details) {
        MyLogger.info('selection handle: drag start');
        _isDragging = true;
      },
      onPanUpdate: (DragUpdateDetails details) {
        MyLogger.debug('selection handle: drag update');
        // Handle circle has an offset from actual point of text line because it is at the bottom of cursor.
        var globalOffset = details.globalPosition + const Offset(0, -_handleSize);
        _isDragging = true;
        Controller.instance.selectionController.updateSelectionByOffset(globalOffset, type: type);
      },
      onPanEnd: (DragEndDetails details) {
        MyLogger.info('selection handle: drag end');
        _isDragging = false;
      },
      onPanCancel: () {
        MyLogger.info('selection handle: drag cancel');
        _isDragging = false;
      },
      child: dragContainer,
    );
    Offset offset;
    switch(type) {
      case SelectionExtentType.base:
        offset = _baseHandleOffset!;
        break;
      case SelectionExtentType.extent:
        offset = _extentHandleOffset!;
        break;
    }
    return PositionedHandle(
      initPosition: offset,
      child: gesture,
      type: type,
      parentLayer: this,
    );
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

class PositionedHandle extends StatefulWidget {
  final Widget child;
  final Offset initPosition;
  final SelectionExtentType type;
  final SelectionHandleLayer parentLayer;

  const PositionedHandle({
    super.key,
    required this.child,
    required this.initPosition,
    required this.type,
    required this.parentLayer,
  });

  @override
  State<StatefulWidget> createState() => _PositionedHandleState();
}

class _PositionedHandleState extends State<PositionedHandle> {
  late Offset position;

  @override
  void initState() {
    position = widget.parentLayer.convertGlobalOffsetToSelectionLayer(widget.initPosition)?? widget.initPosition;
    switch(widget.type) {
      case SelectionExtentType.base:
        widget.parentLayer.updateHandleStateOfBase(this);
        break;
      case SelectionExtentType.extent:
        widget.parentLayer.updateHandleStateOfExtent(this);
        break;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: widget.child,
    );
  }

  void updatePosition(Offset offset) {
    offset = widget.parentLayer.convertGlobalOffsetToSelectionLayer(offset)?? offset;
    if(offset == position) return;
    setState(() {
      position = offset;
    });
  }

  void updatePositionByDelta(Offset delta) {
    if(delta == Offset.zero) return;
    setState(() {
      position -= delta;
    });
  }
}