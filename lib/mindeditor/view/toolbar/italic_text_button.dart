import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/text_selection_style_switch_button.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'base/appearance_setting.dart';

class ItalicTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const ItalicTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextSelectionStyleSwitchButton(
      icon: Icon(Icons.format_italic, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Italicize',
      buttonKey: 'italic',
      showOrNot: (TextSpansStyle? style) {
        return (style != null && style.isAllItalic);
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        var isItalic = blockState?.triggerSelectedItaly();
        CallbackRegistry.requestFocus();
        return isItalic?? false;
      },
    );
  }

}
