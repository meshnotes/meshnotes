import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

typedef ActionFunction = void Function();

class WidgetTemplate {
  static Widget buildDefaultButton(IconData icon, String label, ActionFunction? action) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.blueGrey[100],
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          border: Border.all(color: Colors.blueGrey[200]!, width: 1.0),
        ),
        margin: const EdgeInsets.all(4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            Text(label),
          ],
        ),
      ),
      onPressed: action,
    );
  }

  static Widget buildNormalButton(IconData icon, String label, ActionFunction? action) {
    Color textColor = action != null? Colors.grey[600]!: Colors.grey[200]!;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          border: Border.all(color: textColor, width: 1.0),
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        ),
        margin: const EdgeInsets.all(4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor,),
            Text(label, style: TextStyle(color: textColor,)),
          ],
        ),
      ),
      onPressed: action,
    );
  }

  static Widget buildInsignificantButton(IconData icon, String label, ActionFunction? action, {MainAxisAlignment alignment = MainAxisAlignment.center}) {
    return CupertinoButton(
      child: Row(
        mainAxisAlignment: alignment,
        children: [
          Icon(icon, color: Colors.grey[600],),
          Text(label, style: TextStyle(fontSize: 14.0, color: Colors.grey[600]),),
        ],
      ),
      onPressed: action,
    );
  }

  static Widget buildNormalInputField(String placeHolder, TextEditingController controller) {
    return Container(
      margin: const EdgeInsets.all(4.0),
      child: CupertinoTextField(
        padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 16.0),
        placeholder: placeHolder,
        controller: controller,
      ),
    );
  }

  static Widget buildKeyboardResizableContainer(Widget child) {
    final layoutBuilder = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        var metrics = MediaQuery.of(context);
        final width = metrics.size.width;
        final height = metrics.size.height;
        final padding = EdgeInsets.fromLTRB(
          metrics.viewInsets.left + metrics.padding.left,
          metrics.viewInsets.top + metrics.padding.top,
          metrics.viewInsets.right + metrics.padding.right,
          metrics.viewInsets.bottom + metrics.padding.bottom,
        );

        return Container(
          width: width,
          height: height,
          padding: padding,
          child: child,
        );
      },
    );
    return layoutBuilder;
  }
}