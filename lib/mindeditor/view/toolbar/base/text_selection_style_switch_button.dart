import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../../../controller/callback_registry.dart';
import '../../../document/paragraph_desc.dart';

class TextSelectionStyleSwitchButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final Widget icon;
  final String tip;
  final String buttonKey;
  final bool Function(TextSpansStyle?) showOrNot;
  final bool Function() onPressed; // return value: - true: show button; - false: hide button

  const TextSelectionStyleSwitchButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tip,
    required this.buttonKey,
    required this.showOrNot,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TextSelectionStyleSwitchButtonState();
}

class _TextSelectionStyleSwitchButtonState extends State<TextSelectionStyleSwitchButton> {
  bool isOn = false;

  @override
  void initState() {
    super.initState();
    MyLogger.debug('efantest: building toolbar switch button key=${widget.buttonKey}');
    CallbackRegistry.registerSelectionStyleWatcher(widget.buttonKey, (TextSpansStyle? style) {
      _setOn(widget.showOrNot(style));
    });
  }
  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterSelectionStyleWatcher(widget.buttonKey);
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