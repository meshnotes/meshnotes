import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'base/appearance_setting.dart';

class IconAndTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final String text;
  final String tip;
  final IconData? iconData;
  final Function onPressed;
  const IconAndTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.text,
    required this.tip,
    this.iconData,
    required this.onPressed,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    if(iconData != null) {
      children.add(Icon(iconData, size: appearance.iconSize));
    }
    children.add(Text(text));
    var wrap = Wrap(children: children,);
    return ToolbarButton(
      icon: wrap,
      width: appearance.iconSize * 2,
      appearance: appearance,
      controller: controller,
      tip: tip,
      onPressed: () {
        onPressed();
      },
    );
  }
}