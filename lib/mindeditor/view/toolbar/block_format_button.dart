import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../../controller/callback_registry.dart';

class BlockFormatButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final Widget icon;
  final String tip;
  final String buttonKey;
  final bool Function(String? type, String? listing, int? level) showOrNot;
  final void Function() onPressed;

  const BlockFormatButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tip,
    required this.showOrNot,
    required this.onPressed,
    required this.buttonKey,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _BlockFormatButtonState();
}

class _BlockFormatButtonState extends State<BlockFormatButton> {
  bool isOn = false;

  @override
  void initState() {
    super.initState();
    MyLogger.debug('efantest: building block format button: ${widget.buttonKey}');
    CallbackRegistry.registerEditingBlockFormatWatcher(widget.buttonKey, (String? type, String? listing, int? level) {
      _setOn(widget.showOrNot(type, listing, level));
    });
  }
  @override
  void dispose() {
    super.dispose();
    MyLogger.debug('efantest: destroying block format button: ${widget.buttonKey}');
    CallbackRegistry.unregisterEditingBlockFormatWatcher(widget.buttonKey);
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
        widget.onPressed();
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