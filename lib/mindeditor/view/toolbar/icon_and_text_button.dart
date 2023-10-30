import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import 'appearance_setting.dart';

class IconAndTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const IconAndTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    var wrap = Wrap(
      children: [
        Icon(Icons.comment_outlined, size: appearance.iconSize),
        const Text(
          'Comment'
        ),
      ],
    );
    return ToolbarButton(
      icon: wrap,
      width: appearance.iconSize * 2,
      appearance: appearance,
      controller: controller,
      tip: 'Comment',
      onPressed: () {
        MyLogger.debug('efantest: comment pressed');
        CallbackRegistry.hideKeyboard();
      },
    );
  }
}