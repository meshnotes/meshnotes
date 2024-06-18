import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';

import '../controller/controller.dart';
import '../controller/selection_controller.dart';

class SelectionHandleLayer {
  OverlayEntry? _handleOfStart;
  OverlayEntry? _handleOfEnd;
  _PositionedHandleState? _positionedOfBase;
  _PositionedHandleState? _positionedOfExtent;
  BuildContext? _context;
  Offset? _baseHandleOffset;
  Offset? _extentHandleOffset;
  static const _handleSize = 16.0;
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
    _baseHandleOffset = offset + const Offset(-_handleSize / 2, 0);
    _positionedOfBase?.updatePosition(_baseHandleOffset!);
  }
  void updateExtentHandleOffset(Offset? offset) {
    if(offset == null) return;
    _extentHandleOffset = offset + const Offset(-_handleSize / 2, 0);
    _positionedOfExtent?.updatePosition(_extentHandleOffset!);
  }
  void updatePositionedOfBase(_PositionedHandleState state) {
    _positionedOfBase = state;
  }
  void updatePositionedOfExtent(_PositionedHandleState state) {
    _positionedOfExtent = state;
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
    _handleOfStart = _buildStartHandle();
    _handleOfEnd = _buildEndHandle();
    Overlay.of(_context!).insert(_handleOfStart!);
    Overlay.of(_context!).insert(_handleOfEnd!);
  }

  void hideTextSelectionHandles() {
    _handleOfStart?.remove();
    _handleOfStart?.dispose();
    _handleOfStart = null;
    _positionedOfBase = null;
    _handleOfEnd?.remove();
    _handleOfEnd?.dispose();
    _handleOfEnd = null;
    _positionedOfExtent = null;
    _isDragging = false;
  }

  OverlayEntry _buildStartHandle() {
    return _buildHandle(SelectionExtentType.base);
  }
  OverlayEntry _buildEndHandle() {
    return _buildHandle(SelectionExtentType.extent);
  }
  OverlayEntry _buildHandle(SelectionExtentType type) {
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
      child: container,
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
    return OverlayEntry(
      builder: (BuildContext context) {
        var result = PositionedHandle(
          initPosition: offset,
          child: gesture,
          type: type,
          parentLayer: this,
        );
        return result;
      },
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
    position = widget.initPosition;
    switch(widget.type) {
      case SelectionExtentType.base:
        widget.parentLayer.updatePositionedOfBase(this);
        break;
      case SelectionExtentType.extent:
        widget.parentLayer.updatePositionedOfExtent(this);
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
    setState(() {
      position = offset;
    });
  }
}