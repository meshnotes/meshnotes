import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../../controller/callback_registry.dart';

class TextSelectionChangedButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final Widget icon;
  final String tip;
  final String buttonKey;
  final bool Function(TextSelection?) trigger;
  final Function() onPressed;

  const TextSelectionChangedButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tip,
    required this.buttonKey,
    required this.trigger,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TextSelectionChangedButtonState();
}

class _TextSelectionChangedButtonState extends State<TextSelectionChangedButton> {
  bool isOn = false;

  @override
  void initState() {
    super.initState();
    MyLogger.debug('efantest: building selection_changed button key=${widget.buttonKey}');
    CallbackRegistry.registerSelectionChangedWatcher(widget.buttonKey, (TextSelection? selection) {
      _setOn(widget.trigger(selection));
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

class ClipboardChangedButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final Widget icon;
  final String tip;
  final String buttonKey;
  final bool Function(ClipboardReader) showOrNot;
  final Function() onPressed;

  const ClipboardChangedButton({
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
  State<StatefulWidget> createState() => _ClipboardChangedButtonState();
}

class _ClipboardChangedButtonState extends State<ClipboardChangedButton> {
  bool isOn = false;

  @override
  void initState() {
    super.initState();
    MyLogger.debug('efantest: building clipboard_changed button key=${widget.buttonKey}');
    CallbackRegistry.registerClipboardDataWatcher(widget.buttonKey, (reader) {
      _setOn(widget.showOrNot(reader));
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