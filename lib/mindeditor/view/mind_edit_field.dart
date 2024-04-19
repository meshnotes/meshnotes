import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/key_control.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_log/my_log.dart';
import 'view_helper.dart' as helper;
import '../document/paragraph_desc.dart';

class MindEditField extends StatefulWidget {
  final Controller controller;
  final bool isReadOnly;
  final FocusNode focusNode;
  final Document document;

  const MindEditField({
    Key? key,
    required this.controller,
    this.isReadOnly = false,
    required this.focusNode,
    required this.document,
  }): super(key: key);

  @override
  State<StatefulWidget> createState() => MindEditFieldState();
}

class MindEditFieldState extends State<MindEditField> implements TextInputClient {
  UniqueKey uniqueKey = UniqueKey();
  FocusAttachment? _focusAttachment;
  TextInputConnection? _textInputConnection;
  TextEditingValue? _lastEditingValue;
  Rect? _currentSize;
  ScrollController controller = ScrollController();

  bool get _hasFocus => widget.focusNode.hasFocus;
  bool get _hasConnection => _textInputConnection != null && _textInputConnection!.attached;
  bool get _shouldCreateInputConnection => kIsWeb || !widget.isReadOnly;

  @override
  void initState() {
    super.initState();
    initDocAndControlBlock();
    CallbackRegistry.registerEditFieldState(this);
    _attachFocus();
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.info('MindEditFieldState: build block list');
    _updateContext(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final render = context.findRenderObject()! as RenderBox;
      _currentSize = render.localToGlobal(Offset.zero) & render.size;
    });
    _focusAttachment!.reparent();
    Widget listView = _buildBlockList();
    if(Controller.instance.isDebugMode) {
      listView = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey,
            width: 5,
          ),
        ),
        child: listView,
      );
    }
    var gesture = GestureDetector(
      child: listView,
      onTapDown: (TapDownDetails details) {
        MyLogger.debug('MindEditFieldState: on tap down, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onTapOrDoubleTap(details);
      },
      onPanStart: (DragStartDetails details) {
        MyLogger.info('MindEditFieldState: on pan start, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanStart(details);
      },
      onPanUpdate: (DragUpdateDetails details) {
        MyLogger.info('MindEditFieldState: on pan update, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanUpdate(details);
      },
      onPanDown: (DragDownDetails details) {
        MyLogger.info('MindEditFieldState: on pan down, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanDown(details);
      },
      onPanCancel: () {
        MyLogger.info('MindEditFieldState: on pan cancel, id=${widget.key}');
        // widget.controller.gestureHandler.onPanCancel(widget.texts.getBlockId());
      },
      onPanEnd: (DragEndDetails details) {
        MyLogger.info('MindEditFieldState: on pan end');
      },
    );
    var expanded = Expanded(
      child: gesture,
    );
    return expanded;
  }

  @override
  void didUpdateWidget(MindEditField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      _focusAttachment?.detach();
      _attachFocus();
    }
    if(!_shouldCreateInputConnection) {
      _closeConnectionIfNeeded();
    } else {
      if(oldWidget.isReadOnly && _hasFocus) {
        _openConnectionIfNeeded();
      }
    }
  }

  @override
  void dispose() {
    _closeConnectionIfNeeded();
    widget.focusNode.removeListener(_handleFocusChanged);
    _focusAttachment!.detach();
    widget.controller.selectionController.dispose();
    super.dispose();
  }

  Rect getCurrentSize() => _currentSize!;

  void scrollDown(double delta) {
    controller.jumpTo(controller.offset + delta);
  }

  void _attachFocus() {
    _focusAttachment = widget.focusNode.attach(
      context,
      onKeyEvent: _onFocusKey,
    );
    widget.focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    openOrCloseConnection();
    // _cursorCont.startOrStopCursorTimerIfNeeded(
    //     _hasFocus, widget.controller.selection);
    // _updateOrDisposeSelectionOverlayIfNeeded();
    if(_hasFocus) {
      // WidgetsBinding.instance!.addObserver(this);
      // _showCaretOnScreen();
    } else {
      // WidgetsBinding.instance!.removeObserver(this);
    }
    // updateKeepAlive();
  }

  // 按键会先在这里处理，如果返回ignored，再由系统处理
  KeyEventResult _onFocusKey(FocusNode node, KeyEvent _event) {
    MyLogger.debug('efantest: onFocusKey: event is $_event');
    if(_event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    KeyEvent evt = _event;
    final key = evt.logicalKey;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var shift = HardwareKeyboard.instance.isShiftPressed;
    var ctrl = HardwareKeyboard.instance.isControlPressed;
    var meta = HardwareKeyboard.instance.isMetaPressed;
    var result = KeyboardControl.handleKeyDown(key, alt, ctrl, meta, shift);
    return result? KeyEventResult.handled: KeyEventResult.ignored;
  }

  void requestKeyboard() {
    if(_hasFocus) {
      _openConnectionIfNeeded();
      // _showCaretOnScreen();
    } else {
      widget.focusNode.requestFocus();
    }
  }
  void hideKeyboard() {
    if(!_hasFocus) {
      return;
    }
    widget.focusNode.unfocus();
    Controller.instance.selectionController.releaseCursor();
    widget.controller.clearEditingBlock();
  }

  void openOrCloseConnection() {
    if(widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openConnectionIfNeeded();
    } else if(!widget.focusNode.hasFocus) {
      _closeConnectionIfNeeded();
    }
  }

  void _openConnectionIfNeeded() {
    if(!_shouldCreateInputConnection) {
      return;
    }
    _lastEditingValue = widget.controller.getCurrentTextEditingValue();
    if(!_hasConnection) {
      _textInputConnection = TextInput.attach(
        this,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          readOnly: widget.isReadOnly,
          inputAction: TextInputAction.newline,
          enableSuggestions: !widget.isReadOnly,
          keyboardAppearance: Brightness.light,
        ),
      );
      // _textInputConnection!.updateConfig(const TextInputConfiguration(inputAction: TextInputAction.done));

      // _sentRemoteValues.add(_lastKnownRemoteTextEditingValue);
    }
    _textInputConnection!.setEditingState(_lastEditingValue!);
    _textInputConnection!.show();
  }

  void _closeConnectionIfNeeded() {
    if(!_hasConnection) {
      return;
    }
    _textInputConnection!.close();
    _textInputConnection = null;
    _lastEditingValue = null;
  }

  void refreshTextEditingValue() {
    if(!_hasConnection) {
      return;
    }
    _lastEditingValue = widget.controller.getCurrentTextEditingValue();
    MyLogger.info('efantest: Refreshing editingValue to $_lastEditingValue');
    _textInputConnection!.setEditingState(_lastEditingValue!);
  }

  Widget _buildBlockList() {
    var builder = ListView.builder(
      controller: controller,
      itemCount: widget.document.paragraphs.length,
      itemBuilder: (context, index) {
        return _constructBlock(widget.document.paragraphs[index]);
      },
    );
    return builder;
  }

  Widget _constructBlock(ParagraphDesc para, {bool readOnly = false}) {
    Widget blockItem = _buildBlockFromDesc(para, readOnly);
    if(Controller.instance.isDebugMode) {
      blockItem = Container(
        child: blockItem,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blueGrey, width: 1),
        ),
      );
    }
    Widget containerWithPadding = Container(
      padding: const EdgeInsets.fromLTRB(0.0, 5.0, 0.0, 5.0),
      child: blockItem,
    );
    return containerWithPadding;
  }

  Widget _buildBlockFromDesc(ParagraphDesc paragraph, bool readOnly) {
    var blockView = MindEditBlock(
      texts: paragraph,
      controller: widget.controller,
      key: ValueKey(paragraph.getBlockId()),
      readOnly: readOnly,
    );
    return blockView;
  }

  List<Widget> getReadOnlyBlocks() {
    var result = <Widget>[];
    for(var para in widget.document.paragraphs) {
      var item = _constructBlock(para, readOnly: true);
      result.add(item);
    }
    return result;
  }

  /// Compose a new TextEditingValue from old TextEditingValue, and re-use updateEditingValue() method
  void pasteText(String text) {
    // 1. Get old editing value
    TextEditingValue oldEditingValue = getLastEditingValue()?? const TextEditingValue(text: '');
    String oldText = oldEditingValue.text;
    int oldTextLength = oldText.length;

    // 2. Compose new editing value from oldEditingValue and pasted text
    var selection = oldEditingValue.selection;
    String prefixText = '', suffixText = '';
    if(selection.start > 0) {
      prefixText = oldText.substring(0, selection.start);
    }
    if(selection.end >= 0 && selection.end < oldTextLength) {
      suffixText = oldText.substring(selection.end);
    }
    TextEditingValue newEditingValue = TextEditingValue(
      text: prefixText + text + suffixText,
      selection: TextSelection.collapsed(offset: prefixText.length + text.length),
    );

    _textInputConnection?.setEditingState(newEditingValue);
    updateEditingValue(newEditingValue);
  }

  @override
  void connectionClosed() {
    if(!_hasConnection) {
      return;
    }
    _textInputConnection!.connectionClosedReceived();
    _textInputConnection = null;
    // _lastKnownRemoteTextEditingValue = null;
    // _sentRemoteValues.clear();
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    MyLogger.debug('efantest: currentTextEditingValue called');
    return _lastEditingValue;
  }

  @override
  void performAction(TextInputAction action) {
    MyLogger.debug('efantest: performAction: action=$action');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    MyLogger.debug('efantest: performPrivateCommand');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    MyLogger.debug('efantest: showAutocorrectionPromptRect');
  }

  TextEditingValue? getLastEditingValue() {
    return _lastEditingValue;
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    MyLogger.info('updateEditingValue: updating editing value: $value, $_lastEditingValue');
    // Do nothing if the editing value is same as last time
    if(_lastEditingValue == value) {
      return;
    }
    // Just update value if only composing changed(caused by input method)
    var sameText = _lastEditingValue!.text == value.text;
    if(sameText && _lastEditingValue!.selection == value.selection) {
      _lastEditingValue = value;
      return;
    }
    if(value.text.length > Controller.instance.setting.blockMaxCharacterLength) {
      // CallbackRegistry.unregisterCurrentSnackBar();
      CallbackRegistry.showSnackBar(
        SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('Text exceed limit of ${Controller.instance.setting.blockMaxCharacterLength} characters'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2000),
        )
      );
      refreshTextEditingValue();
      return;
    }
    final oldEditingValue = _lastEditingValue!;
    _lastEditingValue = value;
    _updateAndSaveText(oldEditingValue, value, sameText);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    MyLogger.debug('efantest: updateFloatingCursor');
  }

  @override
  void insertTextPlaceholder(Size size) {
    MyLogger.debug('efantest: insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    MyLogger.debug('efantest: removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    MyLogger.debug('efantest: showToolbar');
  }

  void initDocAndControlBlock() {
    widget.document.clearEditingBlock();
    widget.document.clearTextSelection();
  }
  void refreshDoc({String? activeBlockId, int position = 0}) {
    setState(() {
      initDocAndControlBlock();
      if(activeBlockId != null) { // If activeId is not null, make the cursor appear on the block with activeId
        widget.controller.selectionController.updateSelectionInBlock(activeBlockId, TextSelection(baseOffset: position, extentOffset: position));
      }
    });
  }
  void refreshDocWithoutBlockState(String blockId, int position) {
    setState(() {
      initDocAndControlBlock();
      widget.controller.selectionController.updateSelectionWithoutBlockState(blockId, TextSelection(baseOffset: position, extentOffset: position));
    });
  }

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    // TODO: implement didChangeInputControl
    MyLogger.info('efantest didChangeInputControl() called');
  }

  @override
  void performSelector(String selectorName) {
    // TODO: implement performSelector
    MyLogger.info('efantest performSelector() called');
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // TODO: implement insertContent
    MyLogger.info('efantest insertContent() called');
  }

  void _updateAndSaveText(TextEditingValue oldValue, TextEditingValue newValue, bool sameText) {
    MyLogger.verbose('MindEditFieldState: Save $newValue to $oldValue with parameter $sameText');
    var controller = widget.controller;
    var currentBlock = controller.getEditingBlockState()!;
    var block = currentBlock.widget.texts;
    final _render = currentBlock.getRender()!;
    // If text is same, only need to modify cursor and selection
    if(sameText) {
      MyLogger.warn('_updateAndSaveText: same Text');
      // block.setTextSelection(newValue.selection);
      // _render.markNeedsPaint();
      return;
    }

    // How to update texts given oldValue and newValue:
    // 1. Find the first different character from left hand side, remember left same count as leftCount
    // 2. Find the first different character from right hand side, remember right same count as rightCount
    // 3. Characters from leftCount to (length-rightCount) in the oldValue are to be deleted(as deleteFrom and deleteTo)
    // 4. Characters from leftCount to (length-rightCount) in the newValue are to be inserted(as insertStr)
    //
    // Shown as the following diagram
    //           leftCount=5    rightCount=2
    //                 |         |
    //                 v         v
    // old string: Hello_xyz_bit_mn
    // new string: Hello123456789mn
    //                 ^         ^
    //                 |         |
    //         leftCount=5    rightCount=2

    var oldText = oldValue.text;
    var newText = newValue.text;
    // Find the same part in oldValue and newValue
    var leftCount = helper.findLeftDifferent(oldText, newText, newValue.selection.extentOffset - 1);
    // Find the same part in newValue. But never exceed newValue.selection.extentOffset, because this position is newly edited
    var rightCount = helper.findRightDifferent(oldText, newText, newValue.selection.extentOffset);
    MyLogger.verbose('_updateAndSaveText: oldText=($oldText), newText=($newText)');
    MyLogger.verbose('_updateAndSaveText: leftCount=$leftCount, rightCount=$rightCount');
    // Find the positions deleteFrom and deleteTo, and find the insertStr
    var deleteFrom = leftCount;
    var deleteTo = oldText.length - rightCount;
    MyLogger.verbose('_updateAndSaveText: deleteFrom=$deleteFrom');
    var insertFrom = leftCount;
    var insertTo = newText.length - rightCount;
    var insertStr = (insertTo > insertFrom)? newText.substring(insertFrom, insertTo): '';
    MyLogger.verbose('_updateAndSaveText: insertFrom=$insertFrom, insertTo=$insertTo, insertStr=$insertStr');

    // Split insertStr to handle every line separately
    insertStr = insertStr.replaceAll('\r', '');
    var insertStrWithoutNewline = insertStr.split('\n');
    if(insertStrWithoutNewline.isEmpty) return;

    // If the string is inserted exactly between two TextSpan, the affinity decides the string is in left TextSpan or in the right one:
    // 1. affinity is upstream, in the left TextSpan
    // 2. affinity is downstream, in the right TextSpan
    final affinity = newValue.selection.affinity;

    // For the first line, replace the editing block directly
    final firstLine = insertStrWithoutNewline[0];
    final lineCount = insertStrWithoutNewline.length;
    currentBlock.replaceText(deleteFrom, deleteTo, firstLine, affinity);

    final selectionController = widget.controller.selectionController;
    if(lineCount <= 1) {
      // If there is no '\n' in the inserted string, just clear previously selected content
      if(selectionController.isInSingleBlock()) {
        selectionController.updateSelectionInBlock(block.getBlockId(), newValue.selection);
      } else {
        selectionController.deleteSelectedContent(keepExtentBlock: true, deltaPos: firstLine.length);
      }
    } else {
      // If there are '\n' in the inserted string, delete all selected contents with different parameter
      if(selectionController.isInSingleBlock()) {
        int newExtentOffset = deleteFrom + firstLine.length;
        selectionController.updateSelectionInBlock(
          block.getBlockId(),
          newValue.selection.copyWith(baseOffset: newExtentOffset, extentOffset: newExtentOffset),
        );
      } else {
        selectionController.deleteSelectedContent(keepExtentBlock: true, deltaPos: firstLine.length);
      }
      // Insert last line and spawn a nwe line
      final lastLine = insertStrWithoutNewline[lineCount - 1];
      var newBlockState = controller.getEditingBlockState()!;
      int currentCursorPosition = selectionController.lastExtentBlockPos;
      newBlockState.replaceText(currentCursorPosition, currentCursorPosition, lastLine, affinity);
      String newBlockId = newBlockState.spawnNewLineAtOffset(currentCursorPosition);
      // Insert line 1~n-1
      if(lineCount >= 3) {
        newBlockState.insertBlocksWithTexts(insertStrWithoutNewline.sublist(1, lineCount - 1));
      }
      // Locate the cursor in the last line of inserted string.
      // We don't have the MindEditBlockState at this time, so could not use refreshDoc directly, which depends on MindEditBlockState
      refreshDocWithoutBlockState(newBlockId, lastLine.length);
    }

    selectionController.resetCursor();
    _render.updateParagraph();
    _render.markNeedsLayout();
  }

  void _updateContext(BuildContext context) {
    widget.controller.selectionController.updateContext(context);
    widget.controller.pluginManager.updateContext(context);
  }
}