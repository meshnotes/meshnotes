import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/net/status.dart';
import 'package:mesh_note/page/title_bar.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../document/paragraph_desc.dart';
import '../mind_editor.dart';
import '../view/floating_view.dart';
import '../view/mind_edit_field.dart';

class CallbackRegistry {
  static DocumentTitleBarState? _titleBarState;
  static MindEditorState? _editorState;
  static FloatingViewManager? _floatingViewManager;
  static MindEditFieldState? _editFieldState;
  static GlobalKey<State<ScaffoldMessenger>>? _messengerKey;
  static final Map<String, Function(TextSpansStyle?)> _selectionStyleWatcher = {};
  static final Map<String, Function(TextSelection?)> _selectionChangedWatcher = {};
  static final Map<String, Function(String)> _clipboardDataWatcher = {};
  static final Map<String, Function()> _documentChangedWatcher = {};
  static final Map<String, Function(String?, String?, int?)> _editingBlockFormatWatcher = {};
  static Function()? _screenShotHandler;
  static Function(NetworkStatus)? _networkStatusWatcher;
  static Function(String)? _showToastCallback;

  static void registerTitleBar(DocumentTitleBarState _s) {
    _titleBarState = _s;
  }
  static void unregisterTitleBar(DocumentTitleBarState _s) {
    if(_titleBarState == _s) _titleBarState = null;
  }
  static void resetTitleBar(List<String> titles) {
    _titleBarState?.setTitles(titles);
  }
  static void clearTitleBar() {
    _titleBarState?.clearTitles();
  }

  static void registerEditorState(MindEditorState _s) {
    _editorState = _s;
  }
  static void unregisterEditorState(MindEditorState _s) {
    if(_editorState == _s) _editorState = null;
  }
  static void openDocument(Document doc) {
    _editorState?.open(doc);
  }
  static void closeDocument() {
    _editorState?.close();
  }

  static registerFloatingViewManager(FloatingViewManager _f) => _floatingViewManager = _f;
  static FloatingViewManager? getFloatingViewManager() => _floatingViewManager;

  static void registerEditFieldState(MindEditFieldState _s) {
    _editFieldState = _s;
  }
  static void refreshTextEditingValue() {
    _editFieldState?.refreshTextEditingValue();
  }
  static void refreshDoc({String? activeBlockId, int position = 0}) {
    _editFieldState?.refreshDoc(activeBlockId: activeBlockId, position: position);
  }
  static TextEditingValue? getLastEditingValue() {
    return _editFieldState?.getLastEditingValue();
  }
  static void requestKeyboard() {
    _editFieldState?.requestKeyboard();
  }
  static void requestFocus() {
    _editFieldState?.widget.focusNode.requestFocus();
  }
  static void hideKeyboard() {
    _editFieldState?.hideKeyboard();
  }
  static void showKeyboard() {
    _editFieldState?.showKeyboard();
  }
  static List<Widget> getReadOnlyBlocks() {
    return _editFieldState?.getReadOnlyBlocks()?? [];
  }
  static Rect? getEditStateSize() {
    return _editFieldState?.getCurrentSize();
  }
  static void scrollUp(double delta) {
    _editFieldState?.scrollDown(-delta);
  }
  static void scrollDown(double delta) {
    _editFieldState?.scrollDown(delta);
  }
  static void pasteText(String text) {
    _editFieldState?.pasteText(text);
  }
  static void rudelyCloseIME() {
    _editFieldState?.rudelyCloseIME();
  }
  static (int, int)? getActiveBlockIndexRange() {
    return _editFieldState?.getActiveBlockIndexes();
  }

  static registerMessengerKey(GlobalKey<State<ScaffoldMessenger>> _k) {
    _messengerKey = _k;
  }
  static unregisterCurrentSnackBar(GlobalKey<State<ScaffoldMessenger>> _k) {
    if(_messengerKey == _k) {
      (_messengerKey?.currentState as ScaffoldMessengerState).removeCurrentSnackBar();
      _messengerKey = null;
    }
  }
  static showSnackBar(SnackBar snackBar) {
    (_messengerKey?.currentState as ScaffoldMessengerState).showSnackBar(snackBar);
  }

  static void registerSelectionStyleWatcher(String key, Function(TextSpansStyle?) watcher) {
    _selectionStyleWatcher[key] = watcher;
  }
  static void unregisterSelectionStyleWatcher(String key) {
    _selectionStyleWatcher.remove(key);
  }
  static void triggerSelectionStyleEvent(TextSpansStyle? textSpanStyle) {
    for(var item in _selectionStyleWatcher.values) {
      item(textSpanStyle);
    }
  }

  static void registerSelectionChangedWatcher(String key, Function(TextSelection?) watcher) {
    _selectionChangedWatcher[key] = watcher;
  }
  static void unregisterSelectionChangedWatcher(String key) {
    _selectionChangedWatcher.remove(key);
  }
  static void triggerSelectionChangedEvent(TextSelection? textSelection) {
    for(var item in _selectionChangedWatcher.values) {
      item(textSelection);
    }
  }

  static void registerClipboardDataWatcher(String key, Function(String) watcher) {
    _clipboardDataWatcher[key] = watcher;
  }
  static void unregisterClipboardDataWatcher(String key) {
    _clipboardDataWatcher.remove(key);
  }
  static void triggerClipboardDataEvent(String data) {
    for(var item in _clipboardDataWatcher.values) {
      item(data);
    }
  }

  static void registerDocumentChangedWatcher(String key, Function() watcher) {
    _documentChangedWatcher[key] = watcher;
  }
  static void unregisterDocumentChangedWatcher(String key) {
    _documentChangedWatcher.remove(key);
  }
  static void triggerDocumentChangedEvent() {
    for(var item in _documentChangedWatcher.values) {
      item();
    }
  }

  // 注册BlockFormat相关的监视器，当选定的Block发生改变时，会调用watcher(type, listing, level)
  static void registerEditingBlockFormatWatcher(String key, Function(String?, String?, int?) watcher) {
    _editingBlockFormatWatcher[key] = watcher;
  }
  static void unregisterEditingBlockFormatWatcher(String key) {
    _editingBlockFormatWatcher.remove(key);
  }
  static void triggerEditingBlockFormatEvent(String? blockType, String? listing, int? level) {
    for(var item in _editingBlockFormatWatcher.values) {
      // items in _editingBlockFormatWatcher may invoke setState(), so we need to invoke callbacks in post frame phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        item(blockType, listing, level);
      });
    }
  }

  static void registerNetworkStatusWatcher(Function(NetworkStatus) watcher) {
    _networkStatusWatcher = watcher;
  }
  static void unregisterNetworkStatusWatcher(Function(NetworkStatus) watcher) {
    if(_networkStatusWatcher == watcher) {
      _networkStatusWatcher = null;
    }
  }
  static void triggerNetworkStatusChanged(NetworkStatus _status) {
    _networkStatusWatcher?.call(_status);
  }

  static void registerScreenShotHandler(Function() _f) {
    _screenShotHandler = _f;
  }
  static void unregisterScreenShotHandler(Function() _f) {
    if(_screenShotHandler == _f) _screenShotHandler = null;
  }
  static void triggerScreenShot() {
    _screenShotHandler?.call();
  }

  // Followings are callbacks for show toast and dialog in global layers
  static void registerShowToast(void Function(String) showToastCallback) {
    _showToastCallback = showToastCallback;
  }
  static void showToast(String content) {
    MyLogger.info('showToast: $content, _showToastCallback=$_showToastCallback');
    _showToastCallback?.call(content);
  }
}