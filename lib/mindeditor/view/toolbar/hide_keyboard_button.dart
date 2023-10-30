import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';

class HideKeyboardButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const HideKeyboardButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return ToolbarButton(
      icon: Icon(Icons.keyboard_hide, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Hide keyboard',
      onPressed: () {
        MyLogger.debug('efantest: HideKeyboardButton pressed');
        CallbackRegistry.hideKeyboard();
      },
    );
  }
}