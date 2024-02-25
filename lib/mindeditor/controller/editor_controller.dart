import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:my_log/my_log.dart';
import 'package:super_clipboard/super_clipboard.dart';

class EditorController {
  static String getSelectedContent() {
    final controller = Controller.instance;
    var blockState = controller.getEditingBlockState();
    var content = blockState?.getSelectedContent();
    return content?? '';
  }

  static void deleteSelectedContent() {
    final controller = Controller.instance;
    var blockState = controller.getEditingBlockState();
    blockState?.deleteSelection();
  }
  static Future<void> copyToClipboard() async {
    var content = getSelectedContent();
    await _writeToClipboard(content);
    checkIfReadyToPaste();
  }

  static cutToClipboard() async {
    String content = getSelectedContent();
    await _writeToClipboard(content);
    deleteSelectedContent();
    checkIfReadyToPaste();
  }

  static pasteToBlock() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return; // Clipboard API is not supported on this platform.
    }
    final reader = await clipboard.read();
    if(reader.canProvide(Formats.plainText)) {
      reader.readValue(Formats.plainText).then((text) {
        if(text != null) {
          MyLogger.debug('pasteToBlock: get text from clipboard: $text');
          CallbackRegistry.pasteText(text);
        }
      });
    }
  }

  static Future<void> _writeToClipboard(String content) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }
    final item = DataWriterItem();
    item.add(Formats.plainText(content));
    await clipboard.write([item]);
  }

  static void checkIfReadyToPaste() {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return; // Clipboard API is not supported on this platform.
    }
    clipboard.read().then((reader) => CallbackRegistry.triggerClipboardDataEvent(reader));
  }
}