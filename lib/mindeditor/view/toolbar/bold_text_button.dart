import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/text_selection_style_switch_button.dart';
import 'package:flutter/material.dart';
import '../../document/paragraph_desc.dart';
import 'appearance_setting.dart';

class BoldTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const BoldTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextSelectionStyleSwitchButton(
      icon: Icon(Icons.format_bold, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Bold',
      buttonKey: 'bold',
      showOrNot: (TextSpansStyle? style) {
        return (style != null && style.isAllBold);
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        var isBold = blockState?.triggerSelectedBold();
        CallbackRegistry.requestFocus();
        return isBold?? false;
      },
    );
  }
}