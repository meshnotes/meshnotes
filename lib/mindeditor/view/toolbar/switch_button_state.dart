import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';

class ToolbarSwitchButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final Widget icon;
  final String tip;
  final Function(Function(bool) _setOn) initCallback; // _setOn是给callback函数设置按钮按下状态的
  final Function() destroyCallback;
  final bool Function() onPressed; // 返回的bool是给_setOn用来设置按钮按下状态的

  const ToolbarSwitchButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tip,
    required this.initCallback,
    required this.destroyCallback,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ToolbarSwitchButtonState();
}

class _ToolbarSwitchButtonState extends State<ToolbarSwitchButton> {
  bool isOn = false;

  @override
  void initState() {
    super.initState();
    MyLogger.debug('efantest: building toolbar switch button');
    widget.initCallback(_setOn);
  }
  @override
  void dispose() {
    super.dispose();
    widget.destroyCallback();
  }

  @override
  Widget build(BuildContext context) {
    return ToolbarButton(
      icon: widget.icon,
      appearance: widget.appearance,
      controller: widget.controller,
      tip: widget.tip,
      isOn: isOn,
      onPressed: () {
        _setOn(widget.onPressed());
      },
    );
  }

  void _setOn(bool value) {
    if(isOn == value) {
      return;
    }
    setState(() {
      isOn = value;
    });
  }
}