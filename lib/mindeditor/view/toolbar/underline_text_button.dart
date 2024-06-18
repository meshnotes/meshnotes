import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/text_selection_style_switch_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../../document/paragraph_desc.dart';
import 'appearance_setting.dart';

class UnderlineTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const UnderlineTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextSelectionStyleSwitchButton(
      icon: Icon(Icons.format_underline, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Underline',
      buttonKey: 'underline',
      showOrNot: (TextSpansStyle? style) {
        return (style != null && style.isAllUnderline);
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        var isUnderline = blockState?.triggerSelectedUnderline();
        CallbackRegistry.requestFocus();
        return isUnderline?? false;
      },
    );
  }
}
