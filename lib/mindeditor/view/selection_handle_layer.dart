import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/selection_controller.dart';

class SelectionHandleLayer {
  Widget? _handleOfStart;
  Widget? _handleOfEnd;
  Widget? _handleOfCursor;
  Widget? _dragMagnifier;
  // Widget? _handleOfCursor;
  _PositionedHandleState? _handleStateOfBase;
  _PositionedHandleState? _handleStateOfExtent;
  _PositionedHandleState? _handleStateOfCursor;
  _DragMagnifierState? _dragMagnifierState;
  static const _handleSize = 16.0;
  static const _handleDragSize = 32.0;
  static const _magnifierSize = Size(112, 64);
  bool _isDragging = false;
  int _lastScrollTime = 0;
  Timer? _scrollTimer;
  Offset? _lastScrollGlobalOffset;

  bool isDragging() => _isDragging;

  void dispose() {
    //TODO should optimize here, _context should be cleared when dispose. But current implementation will cover the valid _context, because
    //TODO old MindEditFieldState.dispose() will invoked after new MindEditFieldState.initState()
    _hideTextSelectionHandles(clearLayout: false); // Don't clear layout here, because it will cause a setState() call
  }

  void updateBaseHandleOffset(Offset? offset) {
    if(offset == null) return;
    final deltaOffset = _convertToDragOffset(offset);
    _handleStateOfBase?.updatePosition(deltaOffset);
  }
  void updateExtentHandleOffset(Offset? offset) {
    if(offset == null) return;
    final deltaOffset = _convertToDragOffset(offset);
    _handleStateOfExtent?.updatePosition(deltaOffset);
  }
  void updateCursorHandleOffset(Offset? offset) {
    if(offset == null) return;
    final deltaOffset = _convertToDragOffset(offset);
    _handleStateOfCursor?.updatePosition(deltaOffset);
  }
  void updateBaseHandleOffsetByDelta(Offset delta) {
    _handleStateOfBase?.updatePositionByDelta(delta);
  }
  void updateExtentHandleOffsetByDelta(Offset delta) {
    _handleStateOfExtent?.updatePositionByDelta(delta);
  }
  void updateCursorHandleOffsetByDelta(Offset delta) {
    _handleStateOfCursor?.updatePositionByDelta(delta);
  }
  void updateHandleStateOfBase(_PositionedHandleState state) {
    _handleStateOfBase = state;
  }
  void updateHandleStateOfExtent(_PositionedHandleState state) {
    _handleStateOfExtent = state;
  }
  void updateHandleStateOfCursor(_PositionedHandleState state) {
    _handleStateOfCursor = state;
  }
  void updateDragMagnifierState(_DragMagnifierState state) {
    _dragMagnifierState = state;
  }
  Offset? convertGlobalOffsetToSelectionLayer(Offset global) {
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    return floatingViewManager?.convertGlobalOffsetToSelectionLayer(global);
  }
  Size? getSelectionLayerSize() {
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    return floatingViewManager?.getSelectionLayerSize();
  }

  void hide() {
    _hideTextSelectionHandles();
  }
  void showOrUpdateTextSelectionHandles(Offset? baseCursorOffset, Offset? extentCursorOffset) {
    if(baseCursorOffset == null || extentCursorOffset == null) {
      _hideTextSelectionHandles();
      return;
    }
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    if(_handleStateOfBase != null && _handleStateOfExtent != null) { // Already displayed handles
      updateBaseHandleOffset(baseCursorOffset);
      updateExtentHandleOffset(extentCursorOffset);
      // floatingViewManager?.clearPopupMenu();
      return;
    }
    if(_handleStateOfCursor != null) {
      _hideTextSelectionHandles();
    }
    if(floatingViewManager != null) {
      // floatingViewManager.clearPopupMenu();
      _handleOfStart = _buildStartHandle(_convertToDragOffset(baseCursorOffset));
      _handleOfEnd = _buildEndHandle(_convertToDragOffset(extentCursorOffset));
      floatingViewManager.addSelectionHandles(_handleOfStart!, _handleOfEnd!);
    }
  }
  void showOrUpdateCursorHandle(Offset? extentCursorOffset) {
    if(extentCursorOffset == null) {
      _hideTextSelectionHandles();
      return;
    }
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    if(_handleStateOfCursor != null) { // No context or already displayed handles
      updateCursorHandleOffset(extentCursorOffset);
      // floatingViewManager?.clearPopupMenu();
      return;
    }
    if(_handleStateOfBase != null || _handleStateOfExtent != null) {
      _hideTextSelectionHandles();
    }
    if(floatingViewManager != null) {
      // floatingViewManager.clearPopupMenu();
      _handleOfCursor = _buildCursorHandle(_convertToDragOffset(extentCursorOffset));
      floatingViewManager.addCursorHandle(_handleOfCursor!);
    }
  }

  void _hideTextSelectionHandles({bool clearLayout = true}) {
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    if(clearLayout) {
      floatingViewManager?.clearAllHandles();
    }
    _handleOfStart = null;
    _handleStateOfBase = null;
    _handleOfEnd = null;
    _handleStateOfExtent = null;
    _handleOfCursor = null;
    _handleStateOfCursor = null;
    _dragMagnifier = null;
    _dragMagnifierState = null;
    _isDragging = false;
  }

  Offset _convertToDragOffset(Offset offset) {
    final deltaOffset = offset + const Offset(-_handleDragSize / 2, 0);
    return deltaOffset;
  }

  Widget _buildStartHandle(Offset offset) {
    return _buildHandle(SelectionExtentType.base, offset);
  }
  Widget _buildEndHandle(Offset offset) {
    return _buildHandle(SelectionExtentType.extent, offset);
  }
  Widget _buildCursorHandle(Offset offset) {
    return _buildHandle(SelectionExtentType.cursor, offset);
  }

  Widget _buildHandle(SelectionExtentType type, Offset offset) {
    final controller = Controller();
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
      onPanDown: (DragDownDetails details) {
        _showOrUpdateDragMagnifier(details.globalPosition);
      },
      onPanStart: (DragStartDetails details) {
        MyLogger.info('selection handle: drag start');
        _isDragging = true;
        final selectionOffset = _convertToSelectionOffset(details.globalPosition);
        _showOrUpdateDragMagnifier(details.globalPosition);
        _lastScrollGlobalOffset = selectionOffset;
        _scrollTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          _tryToScroll(controller, _lastScrollGlobalOffset!, type);
        });
      },
      onPanUpdate: (DragUpdateDetails details) {
        MyLogger.info('selection handle: drag update');
        // Handle circle has an offset from actual point of text line because it is at the bottom of cursor.
        final selectionOffset = _convertToSelectionOffset(details.globalPosition);
        _isDragging = true;
        controller.selectionController.updateSelectionByOffset(selectionOffset, type: type);
        _showOrUpdateDragMagnifier(details.globalPosition);
        controller.selectionController.clearPopupMenu();
        // _tryToScroll(globalOffset);
        _lastScrollGlobalOffset = selectionOffset;
      },
      onPanEnd: (DragEndDetails details) {
        MyLogger.info('selection handle: drag end');
        _isDragging = false;
        _hideDragMagnifier();
        _scrollTimer?.cancel();
      },
      onPanCancel: () {
        MyLogger.info('selection handle: drag cancel');
        _isDragging = false;
        _hideDragMagnifier();
        _scrollTimer?.cancel();
      },
      onTapUp: (TapUpDetails details) {
        MyLogger.info('selection handle is tapped: ${details.globalPosition}');
        if(!_isDragging) {
          _hideDragMagnifier();
        }
        controller.selectionController.showPopupMenu(globalPosition: details.globalPosition);
      },
      onTapCancel: () {
        if(!_isDragging) {
          _hideDragMagnifier();
        }
      },
      child: dragContainer,
    );
    return PositionedHandle(
      key: UniqueKey(), //TODO Maybe better to use a global key
      initPosition: offset,
      child: gesture,
      type: type,
      parentLayer: this,
    );
  }

  Offset _convertToSelectionOffset(Offset offset) {
    return offset + const Offset(0, -_handleSize);
  }

  void _showOrUpdateDragMagnifier(Offset globalOffset) {
    if(!Controller().environment.isMobile()) return;

    if(_dragMagnifierState != null) {
      _dragMagnifierState?.updatePosition(globalOffset);
      return;
    }
    final floatingViewManager = CallbackRegistry.getFloatingViewManager();
    if(floatingViewManager == null) return;

    _dragMagnifier = _DragMagnifier(
      key: UniqueKey(),
      initPosition: globalOffset,
      parentLayer: this,
      magnifierSize: _magnifierSize,
    );
    floatingViewManager.addCursorHandle(_dragMagnifier!);
  }

  void _hideDragMagnifier() {
    if(_dragMagnifier == null) return;
    CallbackRegistry.getFloatingViewManager()?.removeSelectionLayerWidget(_dragMagnifier!);
    _dragMagnifier = null;
    _dragMagnifierState = null;
  }

  void _tryToScroll(Controller controller, Offset globalOffset, SelectionExtentType type) {
    final now = Util.getTimeStamp();
    if(now - _lastScrollTime < 100) return;

    final editableSize = CallbackRegistry.getEditStateSize();
    if(editableSize == null) return;

    const double boundDelta = 50;
    const double scrollDelta = 10;

    double upperBound = editableSize.top + boundDelta;
    double lowerBound = editableSize.bottom - boundDelta;
    final currentY = globalOffset.dy;
    if(currentY < upperBound || currentY > lowerBound) {
      if(currentY < upperBound) {
        CallbackRegistry.scrollUp(scrollDelta);
      } else if(currentY > lowerBound) {
        CallbackRegistry.scrollDown(scrollDelta);
      }
      controller.selectionController.updateSelectionByOffset(globalOffset, type: type);
      _lastScrollTime = now;
    }
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
      case SelectionExtentType.cursor:
        widget.parentLayer.updateHandleStateOfCursor(this);
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

class _DragMagnifier extends StatefulWidget {
  final Offset initPosition;
  final SelectionHandleLayer parentLayer;
  final Size magnifierSize;

  const _DragMagnifier({
    required super.key,
    required this.initPosition,
    required this.parentLayer,
    required this.magnifierSize,
  });

  @override
  State<StatefulWidget> createState() => _DragMagnifierState();
}

class _DragMagnifierState extends State<_DragMagnifier> {
  static const _magnifierFingerGap = 8.0;
  static const _edgePadding = 8.0;
  static const _focalPointRaise = 6.0;
  late Offset _globalPosition;

  @override
  void initState() {
    super.initState();
    _globalPosition = widget.initPosition;
    widget.parentLayer.updateDragMagnifierState(this);
  }

  @override
  Widget build(BuildContext context) {
    final localPosition = widget.parentLayer.convertGlobalOffsetToSelectionLayer(_globalPosition)?? _globalPosition;
    final layerSize = widget.parentLayer.getSelectionLayerSize();
    final maxLeft = layerSize == null? double.infinity: layerSize.width - widget.magnifierSize.width - _edgePadding;
    final maxTop = layerSize == null? double.infinity: layerSize.height - widget.magnifierSize.height - _edgePadding;
    final minTop = -widget.magnifierSize.height + _edgePadding;
    final leftOffset = _clampOffset(localPosition.dx - widget.magnifierSize.width / 2, _edgePadding, maxLeft);
    final topOffset = _clampOffset(localPosition.dy - widget.magnifierSize.height - _magnifierFingerGap, minTop, maxTop);
    final focalPointOffsetY = widget.magnifierSize.height / 2 + _magnifierFingerGap - _focalPointRaise;

    return Positioned(
      left: leftOffset,
      top: topOffset,
      child: IgnorePointer(
        child: RawMagnifier(
          size: widget.magnifierSize,
          magnificationScale: 1.5,
          focalPointOffset: Offset(0, focalPointOffsetY),
          clipBehavior: Clip.hardEdge,
          decoration: MagnifierDecoration(
            opacity: 1,
            shadows: const [
              BoxShadow(
                blurRadius: 10,
                color: Color(0x33000000),
                offset: Offset(0, 4),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(
                color: Color(0xAAFFFFFF),
                width: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void updatePosition(Offset globalPosition) {
    if(globalPosition == _globalPosition) return;
    setState(() {
      _globalPosition = globalPosition;
    });
  }

  double _clampOffset(double value, double minValue, double maxValue) {
    if(maxValue < minValue) return minValue;
    return min(max(value, minValue), maxValue);
  }
}
