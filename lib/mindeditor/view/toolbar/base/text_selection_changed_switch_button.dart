import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';

/// This Button's icon will be changed according to the current selection.
class TextSelectionChangedButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final IconData iconData;
  final String tip;
  final String buttonKey;
  final bool Function(TextSelection?) isAvailableTester;
  final Function() onPressed;

  const TextSelectionChangedButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.iconData,
    required this.tip,
    required this.buttonKey,
    required this.isAvailableTester,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TextSelectionChangedButtonState();
}

class _TextSelectionChangedButtonState extends State<TextSelectionChangedButton> {
  bool isAvailable = false;

  @override
  void initState() {
    super.initState();
    MyLogger.debug('_TextSelectionChangedButtonState: building selection_changed button key=${widget.buttonKey}');
    CallbackRegistry.registerSelectionChangedWatcher(widget.buttonKey, (TextSelection? selection) {
      _setAvailable(widget.isAvailableTester(selection));
    });
  }
  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterSelectionChangedWatcher(widget.buttonKey);
  }

  @override
  Widget build(BuildContext context) {
    return ToolbarButton(
      icon: Icon(widget.iconData, size: widget.appearance.iconSize, color: isAvailable? null: widget.appearance.disabledColor),
      appearance: widget.appearance,
      controller: widget.controller,
      tip: widget.tip,
      isAvailable: isAvailable,
      onPressed: () {
        widget.onPressed();
      },
    );
  }

  void _setAvailable(bool value) {
    MyLogger.info('TextSelectionChangedButton: _setActive($value)');
    if(isAvailable == value) {
      return;
    }
    setState(() {
      isAvailable = value;
    });
  }
}

class ClipboardChangedButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final IconData iconData;
  final String tip;
  final String buttonKey;
  final bool Function(String) showOrNot;
  final Function() onPressed;

  const ClipboardChangedButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.iconData,
    required this.tip,
    required this.buttonKey,
    required this.showOrNot,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ClipboardChangedButtonState();
}

class _ClipboardChangedButtonState extends State<ClipboardChangedButton> {
  bool isAvailable = false;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerClipboardDataWatcher(widget.buttonKey, (data) {
      _setAvailable(widget.showOrNot(data));
    });
  }
  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterClipboardDataWatcher(widget.buttonKey);
  }

  @override
  Widget build(BuildContext context) {
    return ToolbarButton(
      icon: Icon(widget.iconData, size: widget.appearance.iconSize, color: isAvailable? null: widget.appearance.disabledColor),
      appearance: widget.appearance,
      controller: widget.controller,
      tip: widget.tip,
      isAvailable: isAvailable,
      onPressed: () {
        widget.onPressed();
      },
    );
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