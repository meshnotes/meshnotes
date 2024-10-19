import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/editor_controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/text_selection_changed_switch_button.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'base/appearance_setting.dart';

class CopyButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const CopyButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextSelectionChangedButton(
      icon: Icon(Icons.copy_outlined, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Copy',
      buttonKey: 'copy',
      trigger: (TextSelection? selection) {
        return (selection != null && !selection.isCollapsed);
      },
      onPressed: () async {
        await EditorController.copySelectedContentToClipboard();
        CallbackRegistry.requestFocus();
      },
    );
  }
}

class CutButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const CutButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextSelectionChangedButton(
      icon: Icon(Icons.cut_outlined, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Cut',
      buttonKey: 'cut',
      trigger: (TextSelection? selection) {
        return (selection != null && !selection.isCollapsed);
      },
      onPressed: () async {
        await EditorController.cutToClipboard();
        CallbackRegistry.requestFocus();
      },
    );
  }
}

class PasteButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const PasteButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipboardChangedButton(
      icon: Icon(Icons.paste_outlined, size: appearance.iconSize,),
      appearance: appearance,
      controller: controller,
      tip: 'Paste',
      buttonKey: 'paste',
      showOrNot: (ClipboardReader reader) {
        return reader.canProvide(Formats.plainText) || reader.canProvide(Formats.png) || reader.canProvide(Formats.jpeg);
      },
      onPressed: () {
        EditorController.pasteToBlock();
      },
    );
  }
}