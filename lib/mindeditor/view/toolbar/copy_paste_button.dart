import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/editor_controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/text_selection_changed_switch_button.dart';
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
      iconData: Icons.copy_outlined,
      appearance: appearance,
      controller: controller,
      tip: 'Copy',
      buttonKey: 'copy',
      isAvailableTester: (TextSelection? selection) {
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
      iconData: Icons.cut_outlined,
      appearance: appearance,
      controller: controller,
      tip: 'Cut',
      buttonKey: 'cut',
      isAvailableTester: (TextSelection? selection) {
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
      iconData: Icons.paste_outlined,
      appearance: appearance,
      controller: controller,
      tip: 'Paste',
      buttonKey: 'paste',
      showOrNot: (String data) {
        return data.isNotEmpty;
      },
      onPressed: () {
        EditorController.pasteToBlock();
      },
    );
  }
}