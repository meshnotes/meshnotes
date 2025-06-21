import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:my_log/my_log.dart';

typedef ActionFunction = void Function();

class WidgetTemplate {
  static Widget buildDefaultButton(BuildContext context, IconData icon, String label, ActionFunction? action) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onPrimary;
    final backgroundColor = colorScheme.primary;
    final borderColor = colorScheme.secondary;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        margin: const EdgeInsets.all(4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor,),
            Text(label, style: TextStyle(color: textColor,),),
          ],
        ),
      ),
      onPressed: action,
    );
  }

  static Widget buildSmallIconButton(BuildContext context, IconData icon, String label, ActionFunction? action) {
    final colorScheme = Theme.of(context).colorScheme;
    final textSize = Theme.of(context).textTheme.bodyLarge!.fontSize!;
    MyLogger.info('textSize: $textSize');
    final textColor = colorScheme.onPrimary;
    final backgroundColor = colorScheme.primary;
    // final borderColor = colorScheme.secondary;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.all(Radius.circular(4.0)),
          // border: Border.all(color: borderColor, width: 1.0),
        ),
        margin: const EdgeInsets.all(2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: textSize,),
            const SizedBox(width: 8.0,),
            Text(label, style: TextStyle(color: textColor, fontSize: textSize),),
          ],
        ),
      ),
      onPressed: action,
    );
  }

  static Widget buildSmallBorderlessButton(BuildContext context, IconData icon, String label, ActionFunction? action) {
    final textSize = Theme.of(context).textTheme.bodyLarge!.fontSize!;
    Color textColor = action != null? Colors.grey[600]!: Colors.grey[200]!;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12.0),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(4.0)),
        ),
        margin: const EdgeInsets.all(2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: textSize,),
            const SizedBox(width: 8.0,),
            Text(label, style: TextStyle(color: textColor, fontSize: textSize)),
          ],
        ),
      ),
      onPressed: action,
    );
  }
  static Widget buildNormalButton(BuildContext context, IconData icon, String label, ActionFunction? action) {
    final textSize = Theme.of(context).textTheme.bodyLarge!.fontSize!;
    Color textColor = Colors.grey;
    if(action == null) {
      textColor = textColor.withOpacity(0.5);
    }
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
            Icon(icon, color: textColor, size: textSize,),
            Text(label, style: TextStyle(color: textColor, fontSize: textSize)),
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
      height: 48.0,
      child: CupertinoTextField(
        style: const TextStyle(fontSize: Constants.styleSettingItemFontSize),
        placeholder: placeHolder,
        controller: controller,
      ),
    );
  }

  static Widget buildKeyboardResizableContainer(Widget child) {
    final layoutBuilder = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        var metrics = MediaQuery.of(context);
        var width = metrics.size.width;
        var height = metrics.size.height;
        final padding = EdgeInsets.fromLTRB(
          metrics.viewInsets.left + metrics.padding.left,
          metrics.viewInsets.top + metrics.padding.top,
          metrics.viewInsets.right + metrics.padding.right,
          metrics.viewInsets.bottom + metrics.padding.bottom,
        );
        width = min(width, constraints.maxWidth);
        height = min(height, constraints.maxHeight);
        width -= padding.horizontal;
        height -= padding.vertical;
        constraints = BoxConstraints(
          maxWidth: width,
          maxHeight: height,
        );
        CallbackRegistry.getFloatingViewManager()?.updatePopupMenuSize(width, height);

        return SizedBox(
          width: width,
          height: height,
          child: child,
        );
      },
    );
    return layoutBuilder;
  }

  static AppBar buildSimpleAppBar(String title) {
    return AppBar(
      title: Center(child: Text(title)),
      backgroundColor: Colors.white,
    );
  }
}