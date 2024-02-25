import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import 'appearance_setting.dart';

class ColoringTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const ColoringTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    var wrap = Wrap(
      children: [
        Icon(Icons.format_color_text, size: appearance.iconSize),
        Icon(Icons.expand_more, size: appearance.iconSize, color: Colors.grey,),
      ],
    );
    return ToolbarButton(
      icon: wrap,
      width: appearance.iconSize * 2,
      appearance: appearance,
      controller: controller,
      tip: 'Text color',
      onPressed: () {
        MyLogger.debug('efantest: text color pressed');
      },
    );
  }
}