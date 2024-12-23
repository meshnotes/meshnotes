import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import 'base/appearance_setting.dart';

class StrikeThroughTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const StrikeThroughTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return ToolbarButton(
      icon: Icon(Icons.strikethrough_s, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Strike-through',
      onPressed: () {
        MyLogger.debug('StrikeThroughTextButton: strike_throught pressed');
        CallbackRegistry.hideKeyboard();
      },
    );
  }
}