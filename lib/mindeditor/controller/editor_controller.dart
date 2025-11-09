import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:my_log/my_log.dart';
import 'package:flutter/services.dart';
import '../../util/util.dart';

class EditorController {
  static void selectAll() {
    final selectionController = Controller().selectionController;
    selectionController.selectAll();
  }
  
  static String getSelectedContent() {
    final selectionController = Controller().selectionController;
    var content = selectionController.getSelectedContent();
    return content;
  }

  static void deleteSelectedContent() {
    final selectionController = Controller().selectionController;
    selectionController.deleteSelectedContent();
  }
  static Future<void> copySelectedContentToClipboard() async {
    var content = getSelectedContent();
    copyTextToClipboard(content);
  }

  static Future<void> copyTextToClipboard(String text) async {
    await ClipboardUtil.writeToClipboard(text);
    checkIfReadyToPaste();
  }

  static cutToClipboard() async {
    String content = getSelectedContent();
    await ClipboardUtil.writeToClipboard(content);
    deleteSelectedContent();
    checkIfReadyToPaste();
  }

  static pasteToBlock() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if(clipboardData != null) {
        MyLogger.debug('pasteToBlock: get text from clipboard: ${clipboardData.text}');
        CallbackRegistry.pasteText(clipboardData.text!);
    }
  }

  static void checkIfReadyToPaste() {
    Clipboard.getData(Clipboard.kTextPlain).then((clipboardData) {
      if (clipboardData == null) {
        return; // Clipboard API is not supported on this platform.
      }
      CallbackRegistry.triggerClipboardDataEvent(clipboardData.text!);
    }).onError((e, s) {
      MyLogger.err('checkIfReadyToPaste: error=$e, stackTrace=$s');
    });
  }
}