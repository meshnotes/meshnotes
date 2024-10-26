import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';

class BlockFormatButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final Widget? iconWidget;
  final IconData? iconData;
  final String tip;
  final String buttonKey;
  final bool Function(String? type, String? listing, int? level)? activeOrNot;
  final bool Function(String? type, String? listing, int? level)? availableOrNot;
  final void Function() onPressed;

  const BlockFormatButton({
    Key? key,
    required this.controller,
    required this.appearance,
    this.iconWidget,
    this.iconData,
    required this.tip,
    this.activeOrNot,
    this.availableOrNot,
    required this.onPressed,
    required this.buttonKey,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _BlockFormatButtonState();
}

class _BlockFormatButtonState extends State<BlockFormatButton> {
  bool isOn = false;
  bool isAvailable = true;
  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerEditingBlockFormatWatcher(widget.buttonKey, (String? type, String? listing, int? level) {
      if(widget.activeOrNot != null) {
        _setOn(widget.activeOrNot!.call(type, listing, level));
      }
      if(widget.availableOrNot != null) {
        _setAvailable(widget.availableOrNot!.call(type, listing, level));
      }
    });
  }
  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterEditingBlockFormatWatcher(widget.buttonKey);
  }

  @override
  Widget build(BuildContext context) {
    // Prefer iconWidget to iconData
    return ToolbarButton(
      icon: widget.iconWidget?? Icon(widget.iconData, size: widget.appearance.iconSize, color: isAvailable? null: widget.appearance.disabledColor),
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
  void _setAvailable(bool value) {
    if(isAvailable == value) {
      return;
    }
    setState(() {
      isAvailable = value;
    });
  }
}