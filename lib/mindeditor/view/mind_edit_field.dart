import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/key_control.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_log/my_log.dart';
import '../document/text_desc.dart';
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
    // _lastEditingValue = widget.controller.getCurrentTextEditingValue();

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

    // If there's any text in composing, it should be keep in any block
    TextEditingValue? newEditingValue;
    if(_lastEditingValue != null && _lastEditingValue!.composing.isValid) {
      // _textInputConnection!.close();
      // _textInputConnection = TextInput.attach(
      //   this,
      //   TextInputConfiguration(
      //     inputType: TextInputType.multiline,
      //     readOnly: widget.isReadOnly,
      //     inputAction: TextInputAction.newline,
      //     enableSuggestions: !widget.isReadOnly,
      //     keyboardAppearance: Brightness.light,
      //   ),
      // );
      newEditingValue = _lastEditingValue!;
    } else {
      newEditingValue = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      );
    }
    MyLogger.info('_openConnectionIfNeeded: current text editing: $newEditingValue, _hasConnection=$_hasConnection');
    _textInputConnection!.setEditingState(newEditingValue);
    _lastEditingValue = newEditingValue;
    widget.controller.selectionController.leadingPositionBeforeInput = widget.controller.selectionController.lastExtentBlockPos;
    _textInputConnection!.show();
  }

  void _closeConnectionIfNeeded() {
    if(!_hasConnection) {
      return;
    }
    MyLogger.info('_closeConnectionIfNeeded: now close _textInputConnection');
    _textInputConnection!.close();
    _textInputConnection = null;
    _lastEditingValue = null;
  }

  void refreshTextEditingValue() {
    if(!_hasConnection) {
      return;
    }
    _lastEditingValue = widget.controller.getCurrentTextEditingValue();
    MyLogger.info('refreshTextEditingValue: Refreshing editingValue to $_lastEditingValue');
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
    MyLogger.info('connectionClosed');
    _textInputConnection!.connectionClosedReceived();
    _textInputConnection = null;
    // _lastKnownRemoteTextEditingValue = null;
    // _sentRemoteValues.clear();
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    MyLogger.info('TextInputClient.currentTextEditingValue called');
    return _lastEditingValue;
  }

  @override
  void performAction(TextInputAction action) {
    MyLogger.info('TextInputClient.performAction: action=$action');
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    MyLogger.info('TextInputClient.performPrivateCommand');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    MyLogger.info('TextInputClient.showAutocorrectionPromptRect');
  }

  TextEditingValue? getLastEditingValue() {
    return _lastEditingValue;
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    MyLogger.info('updateEditingValue: updating editing value: $value, $_lastEditingValue');
    // Do nothing if the editing value is same as last time
    if(_lastEditingValue == value) {
      MyLogger.warn('updateEditingValue: Totally the same');
      return;
    }
    // Just update value if only composing changed(caused by input method)
    var sameText = _lastEditingValue!.text == value.text;
    if(sameText && _lastEditingValue!.selection == value.selection) {
      MyLogger.warn('updateEditingValue: Only composing different');
      _resetEditingValue(value);
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
    _updateAndSaveText(oldEditingValue, value, sameText);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    MyLogger.debug('TextInputClient: updateFloatingCursor');
  }

  @override
  void insertTextPlaceholder(Size size) {
    MyLogger.debug('TextInputClient: insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    MyLogger.debug('TextInputClient: removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    MyLogger.debug('TextInputClient: showToolbar');
  }

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    // TODO: implement didChangeInputControl
    MyLogger.info('TextInputClient didChangeInputControl() called');
  }

  @override
  void performSelector(String selectorName) {
    // TODO: implement performSelector
    MyLogger.info('TextInputClient performSelector() called');
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // TODO: implement insertContent
    MyLogger.info('TextInputClient insertContent() called');
  }

  void initDocAndControlBlock() {
    widget.document.clearEditingBlock();
    widget.document.clearTextSelection();
  }
  void refreshDoc({String? activeBlockId, int position = 0}) {
    setState(() {
      initDocAndControlBlock();
      if(activeBlockId != null) { // If activeId is not null, make the cursor appear on the block with activeId
        widget.controller.selectionController.collapseInBlock(activeBlockId, position, true);
      }
    });
  }
  void refreshDocWithoutBlockState(String blockId, int position) {
    setState(() {
      initDocAndControlBlock();
      widget.controller.selectionController.updateSelectionWithoutBlockState(blockId, TextSelection(baseOffset: position, extentOffset: position));
    });
  }

  void _updateAndSaveText(TextEditingValue oldValue, TextEditingValue newValue, bool sameText) {
    MyLogger.info('MindEditFieldState: Save $newValue to $oldValue with parameter $sameText');
    var controller = widget.controller;
    var currentBlock = controller.getEditingBlockState()!;
    var block = currentBlock.widget.texts;
    final _render = currentBlock.getRender()!;
    final selectionController = widget.controller.selectionController;
    // If text is same, only need to modify cursor and selection
    if(sameText && selectionController.isCollapsed()) {
      MyLogger.info('_updateAndSaveText: same Text, only modify cursor and selection');
      selectionController.updateSelectionByTextSelection(block.getBlockId(), newValue.selection, false);
      _resetEditingValue(newValue);
      // block.setTextSelection(newValue.selection);
      // _render.markNeedsPaint();
      return;
    }

    //TODO update: rightCount should always be ZERO
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
    MyLogger.info('_updateAndSaveText: deleteFrom=$deleteFrom, deleteTo=$deleteTo');
    var insertFrom = leftCount;
    var insertTo = newText.length - rightCount;
    var insertStr = (insertTo > insertFrom)? newText.substring(insertFrom, insertTo): '';
    MyLogger.info('_updateAndSaveText: insertFrom=$insertFrom, insertTo=$insertTo, insertStr=$insertStr');

    // Split insertStr to handle every line separately
    insertStr = insertStr.replaceAll('\r', '');
    var insertStrWithoutNewline = insertStr.split('\n');
    if(insertStrWithoutNewline.isEmpty) return;

    // If the string is inserted exactly between two TextSpan, the affinity decides the string is in left TextSpan or in the right one:
    // 1. affinity is upstream, in the left TextSpan
    // 2. affinity is downstream, in the right TextSpan
    final affinity = newValue.selection.affinity;

    // Determine if the selection is in the same block, and the line count of new text. Save these flags, will be used in the following code
    final inSelection = !selectionController.isCollapsed();
    final selectionInSingleBlock = selectionController.isInSingleBlock();
    final lineCount = insertStrWithoutNewline.length;

    // 1. If in selection, delete the selected content
    // 2. Insert new text line by line
    //   2.1 Insert last line at the current position of editing block
    //   2.2 If there are at least 2 lines, spawn a new line, and insert first line
    //   2.3 If there are more than 2 lines, insert other lines at the end of first line
    // The reason for using such a complex procedure is that the last line contains *COMPOSING* by IME,
    // which require using MindEditBlockState
    if(inSelection) { // Step 1
      selectionController.deleteSelectedContent(refreshDoc: false);
    }

    final firstLineBlockState = widget.controller.getEditingBlockState()!;
    String lastLineBlockId = firstLineBlockState.getBlockId(); //TODO should change the name
    final leadingPosition = selectionController.leadingPositionBeforeInput;
    final firstLine = insertStrWithoutNewline[0];
    int lastLineLength = firstLine.length; //TODO should change the name
    MyLogger.info('_updateAndSaveText: leadingPosition=$leadingPosition');
    firstLineBlockState.replaceText(leadingPosition + deleteFrom, leadingPosition + deleteTo, firstLine, affinity);
    if(lineCount == 1) {
      MyLogger.info('_updateAndSaveText: collapse in block: ${firstLineBlockState.getBlockId()}, pos=${leadingPosition + deleteFrom + firstLine.length}');
      selectionController.collapseInBlock(firstLineBlockState.getBlockId(), leadingPosition + deleteFrom + firstLine.length, false);
    }
    if(lineCount >= 2) {
      final lastLine = insertStrWithoutNewline[lineCount - 1];
      lastLineLength = lastLine.length;
      firstLineBlockState.replaceText(leadingPosition + firstLine.length, leadingPosition + firstLine.length, lastLine, affinity);
      lastLineBlockId = firstLineBlockState.spawnNewLineAtOffset(leadingPosition + firstLine.length);
      firstLineBlockState.insertBlocksWithTexts(insertStrWithoutNewline.sublist(1, lineCount - 1));
      selectionController.leadingPositionBeforeInput = 0;
    }
    _lastEditingValue = newValue;
    if(lineCount >= 2 || !selectionInSingleBlock) {
      refreshDocWithoutBlockState(lastLineBlockId, lastLineLength);
    }
    //
    //
    //
    //
    // // For the first line, replace the editing block directly
    // final firstLine = insertStrWithoutNewline[0];
    // currentBlock.replaceText(_leadingPositionBeforeComposing + deleteFrom, _leadingPositionBeforeComposing + deleteTo, firstLine, affinity);
    //
    // if(lineCount <= 1) {
    //   // If there is no '\n' in the inserted string, just clear previously selected content
    //   if(selectionController.isInSingleBlock()) {
    //     selectionController.updateSelectionByTextSelection(block.getBlockId(), _leadingPositionBeforeComposing, newValue.selection, false);
    //   } else {
    //     selectionController.deleteSelectedContent(keepExtentBlock: true, deltaPos: firstLine.length);
    //     _leadingPositionBeforeComposing = selectionController.getStartPos();
    //   }
    // } else {
    //   // If there are '\n' in the inserted string, delete all selected contents with different parameter
    //   if(selectionController.isInSingleBlock()) {
    //     int newExtentOffset = deleteFrom + firstLine.length;
    //     selectionController.updateSelectionByTextSelection(
    //       block.getBlockId(),
    //       newValue.selection.copyWith(baseOffset: newExtentOffset, extentOffset: newExtentOffset),
    //       false,
    //     );
    //   } else {
    //     selectionController.deleteSelectedContent(keepExtentBlock: true, deltaPos: firstLine.length, refreshDoc: false);
    //     _leadingPositionBeforeComposing = selectionController.getStartPos();
    //   }
    //   // Insert last line and spawn a nwe line
    //   final lastLine = insertStrWithoutNewline[lineCount - 1];
    //   var newBlockState = controller.getEditingBlockState()!;
    //   int currentCursorPosition = selectionController.lastExtentBlockPos;
    //   newBlockState.replaceText(currentCursorPosition, currentCursorPosition, lastLine, affinity);
    //   String newBlockId = newBlockState.spawnNewLineAtOffset(currentCursorPosition);
    //   // Insert line 1~n-1
    //   if(lineCount >= 3) {
    //     newBlockState.insertBlocksWithTexts(insertStrWithoutNewline.sublist(1, lineCount - 1));
    //   }
    //   // Locate the cursor in the last line of inserted string.
    //   // We don't have the MindEditBlockState at this time, so could not use refreshDoc directly, which depends on MindEditBlockState
    //   refreshDocWithoutBlockState(newBlockId, lastLine.length);
    // }

    selectionController.resetCursor();
    _render.updateParagraph();
    _render.markNeedsLayout();
  }

  void _resetEditingValue(TextEditingValue newValue) {
    if(!newValue.isComposingRangeValid) {
      widget.controller.selectionController.leadingPositionBeforeInput += newValue.text.length;
      newValue = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      );
      _textInputConnection!.setEditingState(newValue);
      MyLogger.info('_resetEditingValue: cut composing and reset leading position=${widget.controller.selectionController.leadingPositionBeforeInput}');
    }
    _lastEditingValue = newValue;
  }

  void _updateContext(BuildContext context) {
    widget.controller.selectionController.updateContext(context);
    widget.controller.pluginManager.updateContext(context);
  }
}