import 'package:flutter/material.dart';

class FloatingViewManager {
  OverlayEntry? tipsEntry;
  double dragStart = 0;

  void showBlockTips(BuildContext context, String content) {
    OverlayEntry tipsWidget = OverlayEntry(builder: (context) {
      var scrollable = Scrollbar(
        child: SingleChildScrollView(
          child: Text(content, style: Theme.of(context).textTheme.bodyMedium,),
        ),
      );
      var container = Container(
        padding: const EdgeInsets.all(8.0),
        child: scrollable,
      );
      var list = ListView(
        shrinkWrap: true,
        children: [
          container,
        ],
      );
      var box = Container(
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(16.0),
        ),
        constraints: const BoxConstraints(
          maxHeight: 150,
          minHeight: 0,
        ),
        width: 200,
        // height: 300,
        child: list,
      );
      var gesture = GestureDetector(
        onHorizontalDragStart: (DragStartDetails details) {
          dragStart = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          double delta = details.globalPosition.dx - dragStart;
          if(delta > 30.0) {
            dragStart = 0.0;
            closeBlockTips();
          }
        },
        child: box,
      );
      return Container(
        padding: const EdgeInsets.all(8.0),
        alignment: Alignment.centerRight,
        child: gesture,
      );
    });
    tipsEntry = tipsWidget;
    Overlay.of(context).insert(tipsWidget);
  }

  void closeBlockTips() {
    tipsEntry?.remove();
    tipsEntry = null;
  }
}