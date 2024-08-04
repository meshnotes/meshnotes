import 'dart:async';
import 'package:flutter/material.dart';

class EditCursor {
  Function refreshFunc;
  bool show = true;
  Timer? _cursorTimer;
  static const duration = Duration(milliseconds: 600);

  EditCursor({
    required this.refreshFunc,
  }) {
    _init();
  }

  void _init() {
    show = true;
    _cursorTimer = Timer(duration, _onDisappear);
  }

  void _onDisappear() {
    show = false;
    refreshFunc();
    _cursorTimer = Timer(duration, _onShow);
  }
  void _onShow() {
    show = true;
    refreshFunc();
    _cursorTimer = Timer(duration, _onDisappear);
  }

  void stopCursor() {
    _cursorTimer?.cancel();
  }

  void resetCursor() {
    _cursorTimer?.cancel();
    _init();
  }

  void paint(Canvas canvas, Rect cursorRect, Offset offset) {
    if(!show) {
      return;
    }
    var painter = Paint()..color = Colors.black..style = PaintingStyle.fill;
    var effectiveRect = cursorRect.shift(offset);
    canvas.drawRect(effectiveRect, painter);
  }
}