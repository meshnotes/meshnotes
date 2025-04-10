import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/key_control.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/view/floating_view.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';

import '../document/paragraph_desc.dart';
import 'view_helper.dart' as helper;

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
  late ScrollController _scrollController;
  String _initialTextValue = ''; // In iOS, use this prefix to detect backspace in soft keyboard
  static const String _iosInitialTextValue = '\u200b';
  bool _hideKeyboard = false; // Hide keyboard manually
  int _activeBlockFirstIndex = -1;
  int _activeBlockLastIndex = -1;
  double _currentScrollPixel = 0.0;
  late FloatingViewManager _floatingViewManager;
  final controller = Controller();

  bool get _hasFocus => widget.focusNode.hasFocus;
  bool get _hasConnection => _textInputConnection != null && _textInputConnection!.attached;
  bool get _shouldCreateInputConnection => kIsWeb || !(widget.isReadOnly || _hideKeyboard);

  @override
  void initState() {
    MyLogger.debug('MindEditFieldState: init state');
    super.initState();
    _floatingViewManager = FloatingViewManager();
    CallbackRegistry.registerFloatingViewManager(_floatingViewManager);
    if(widget.controller.environment.isIos()) {
      _initialTextValue = _iosInitialTextValue;
    }
    initDocAndControlBlock();
    CallbackRegistry.registerEditFieldState(this);
    _attachFocus();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      _onScroll();
    });
    _currentScrollPixel = 0;
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.info('MindEditFieldState: build block list, _hasFocus=$_hasFocus');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final render = context.findRenderObject()! as RenderBox;
      _currentSize = render.localToGlobal(Offset.zero) & render.size;
    });
    if(_hasFocus && !_hideKeyboard) {
      _focusAttachment!.reparent();
    }
    Widget editingLayer = _buildEditingLayer(context);
    var stack = Stack(
      children: [
        editingLayer,
        ..._floatingViewManager.getFloatingLayersForEditor(),
      ],
    );
    var expanded = Expanded(
      child: stack,
    );
    return expanded;
  }

  GestureDetector _buildEditingLayer(BuildContext context) {
    bool isMobile = controller.environment.isMobile();
    // Mobile has no scroll bar, so need padding to make it looks more comfortable
    final padding = isMobile? const EdgeInsets.fromLTRB(10.0, 0.0, 1.0, 0.0): const EdgeInsets.fromLTRB(10.0, 0.0, 0.0, 0.0);
    Widget listView = _buildBlockList();
    Widget container = Container(
      padding: padding,
      child: listView,
    );
    if(controller.isDebugMode) {
      container = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey,
            width: 5,
          ),
        ),
        child: container,
      );
    }

    var gesture = GestureDetector(
      child: container,
      onTapDown: (TapDownDetails details) {
        MyLogger.debug('MindEditFieldState: on tap down, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onTapOrDoubleTap(details);
      },
      onTap: () {
        MyLogger.debug('MindEditFieldState: on tap, id=${widget.key}');
        widget.controller.gestureHandler.onTap();
      },
      onTapCancel: () {
        MyLogger.debug('MindEditFieldState: on tap cancel, id=${widget.key}');
        widget.controller.gestureHandler.onTapCancel();
      },
      onPanStart: isMobile? null: (DragStartDetails details) {
        MyLogger.info('MindEditFieldState: on pan start, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');

        widget.controller.gestureHandler.onPanStart(details);
      },
      onPanUpdate: isMobile? null: (DragUpdateDetails details) {
        MyLogger.info('MindEditFieldState: on pan update, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanUpdate(details);
      },
      onPanDown: isMobile? null: (DragDownDetails details) {
        MyLogger.info('MindEditFieldState: on pan down, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanDown(details);
      },
      onPanCancel: isMobile? null: () {
        MyLogger.info('MindEditFieldState: on pan cancel, id=${widget.key}');
        // widget.controller.gestureHandler.onPanCancel(widget.texts.getBlockId());
      },
      onPanEnd: isMobile? null: (DragEndDetails details) {
        MyLogger.info('MindEditFieldState: on pan end');
      },
    );
    return gesture;
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
    _scrollController.dispose();
    super.dispose();
  }

  Rect getCurrentSize() {
    final render = context.findRenderObject()! as RenderBox;
    _currentSize = render.localToGlobal(Offset.zero) & render.size;
    return _currentSize!;
  }

  void scrollDown(double delta) {
    if(_scrollController.offset == 0 && delta < 0) return; // Avoid screen joggles whenuser drag the handle in the title line
    _scrollController.jumpTo(_scrollController.offset + delta);
  }

  void _attachFocus() {
    _focusAttachment = widget.focusNode.attach(
      context,
      onKeyEvent: _onFocusKey,
    );
    widget.focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    MyLogger.debug('_handleFocusChanged: focus changed: hasFocus=$_hasFocus');
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

  // If this function returns KeyEventResult.ignored, it will be handled by system
  KeyEventResult _onFocusKey(FocusNode node, KeyEvent _event) {
    MyLogger.debug('_onFocusKey: event is $_event');
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
    MyLogger.debug('requestKeyboard: before: has focus=$_hasFocus');
    if(_hasFocus) {
      _openConnectionIfNeeded();
      // _showCaretOnScreen();
    } else {
      MyLogger.debug('requestKeyboard: now request focus');
      _focusAttachment!.reparent();
      widget.focusNode.requestFocus();
    }
    controller.uiEventManager.triggerKeyboardStateOpen(true);
  }
  void hideKeyboard() {
    // if(!_hasFocus) {
    //   return;
    // }
    widget.focusNode.unfocus();
    _hideKeyboard = true;
    controller.uiEventManager.triggerKeyboardStateOpen(false);
    // controller.selectionController.releaseCursor();
    // widget.controller.clearEditingBlock();
  }
  void showKeyboard() {
    _hideKeyboard = false;
    requestKeyboard();
  }
  bool isKeyboardOpen() => !_hideKeyboard && _hasFocus;

  void openOrCloseConnection() {
    MyLogger.debug('openOrCloseConnection: widget.focusNode=${widget.focusNode.hasFocus}');
    if(!_hideKeyboard && _hasFocus && widget.focusNode.consumeKeyboardToken()) {
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

      MyLogger.info('_openConnectionIfNeeded: calling _resetEditingState');
      // _sentRemoteValues.add(_lastKnownRemoteTextEditingValue);
      _resetEditingState();
    } else {
      if(_lastEditingValue == null) {
        var newEditingValue = const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        );
        MyLogger.info('_openConnectionIfNeeded: current text editing: $newEditingValue');
        _lastEditingValue = newEditingValue;
      }
    }
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
    _resetEditingState();
    MyLogger.info('refreshTextEditingValue: Refreshing editingValue to $_lastEditingValue');
  }

  Widget _buildBlockList() {
    final blockCount = widget.document.paragraphs.length;
    // If more than 1000 blocks, use sliver ListView, otherwise use column
    if(blockCount > 1000) {
      return _buildBlockListView();
    }
    return _buildBlockListColumn();
  }
  Widget _buildBlockListView() {
    var builder = ListView.builder(
      controller: _scrollController,
      itemCount: widget.document.paragraphs.length + 1,
      itemBuilder: (context, index) {
        if(index < widget.document.paragraphs.length) {
          return _constructBlock(widget.document.paragraphs[index]);
        }
        return _buildBlockListPlaceholder(context);
      },
    );
    return builder;
  }
  Widget _buildBlockListColumn() {
    List<Widget> blockWidgets = [];
    for(var para in widget.document.paragraphs) {
      blockWidgets.add(_constructBlock(para));
    }
    final column = Column(
      children: [
        ...blockWidgets,
        _buildBlockListPlaceholder(context),
      ],
    );
    final scrollView = SingleChildScrollView(
      controller: _scrollController,
      child: column,
    );
    return scrollView;
  }
  Widget _buildBlockListPlaceholder(BuildContext context) {
    // Make the place holder large enough, so when the soft-keyboard is popped up, it can be scrolled to be not covered
    final size = MediaQuery.sizeOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: SizedBox(
        height: size.height * 0.9,
        width: size.width,
      ),
    );
  }

  Widget _constructBlock(ParagraphDesc para, {bool readOnly = false}) {
    Widget blockItem = _buildBlockFromDesc(para, readOnly);
    if(controller.isDebugMode) {
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

    // _textInputConnection?.setEditingState(newEditingValue);
    updateEditingValue(newEditingValue);
    rudelyCloseIME();
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
    // Hide selection handle when editing
    controller.selectionController.setShouldShowSelectionHandle(false);
    controller.eventTasksManager.triggerUserInputEvent();

    // Check following situations first:
    // 1. In iOS environment, using _initialTextValue to detect deletion in soft keyboard
    //   1.1. Check deletion
    //   1.2. Stripe _initialTextValue before later processing
    // 2. Check if the block text length exceeds maximum limitation

    // Step 1.1
    if(_initialTextValue.isNotEmpty && value.text.isEmpty) {
      MyLogger.info('updateEditingValue: detected backspace entered, isCollapsed=${widget.controller.selectionController.isCollapsed()}');
      _deleteSelectionOrCharacter();
      return;
    }
    // Step 1.2
    value = _stripeInitialText(value);
    MyLogger.info('updateEditingValue: updating editing value: new value=$value, old value=$_lastEditingValue');

    // Do nothing if the editing value is same as last time
    if(_lastEditingValue == value) {
      MyLogger.warn('updateEditingValue: Totally identical');
      return;
    }
    // Just update value if only composing changed(caused by input method)
    var sameText = _lastEditingValue!.text == value.text;
    if(sameText && _lastEditingValue!.selection == value.selection) {
      MyLogger.info('updateEditingValue: Only composing different');
      _updateLastEditingValue(value);
      controller.getEditingBlockState()?.getRender()?.markNeedsLayout(); // Immediate redraw the block to remove the composing underline
      return;
    }
    //TODO If has '\n', it's a multi-line text, need other way to check whether it exceeds the limit
    if(!value.text.contains('\n') && value.text.length > widget.controller.setting.blockMaxCharacterLength) {
      // CallbackRegistry.unregisterCurrentSnackBar();
      // CallbackRegistry.showSnackBar(
      //   SnackBar(
      //     backgroundColor: Colors.orangeAccent,
      //     content: Text('Text exceed limit of ${controller.setting.blockMaxCharacterLength} characters'),
      //     behavior: SnackBarBehavior.floating,
      //     duration: const Duration(milliseconds: 2000),
      //   )
      // );
      CallbackRegistry.showToast('Text exceed limit of ${controller.setting.blockMaxCharacterLength} characters');
      // refreshTextEditingValue();
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

  /// Close IME forcibly, used when User move cursor actively.
  /// Including mouse click, gesture tap, arrow key pressed, enter pressed, etc...
  void rudelyCloseIME() {
    _textInputConnection?.close();
    _lastEditingValue = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
  }
  void initDocAndControlBlock() {
    widget.document.clearEditingBlock();
    widget.document.clearTextSelection();
    _resetActiveBlockIndexes();
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

  (int, int) getActiveBlockIndexes() {
    return (_activeBlockFirstIndex, _activeBlockLastIndex);
  }

  void _updateAndSaveText(TextEditingValue oldValue, TextEditingValue newValue, bool sameText) {
    // MyLogger.info('MindEditFieldState: Save $newValue to $oldValue with parameter $sameText');
    var controller = widget.controller;
    var currentBlock = controller.getEditingBlockState()!;
    var block = currentBlock.widget.texts;
    final _render = currentBlock.getRender()!;
    final selectionController = widget.controller.selectionController;
    var leadingPosition = selectionController.lastExtentBlockPos - oldValue.selection.extentOffset;
    // If text is same, and the selection is collapsed, only need to modify cursor and selection
    if(sameText && selectionController.isCollapsed()) {
      MyLogger.info('_updateAndSaveText: same Text, only modify cursor and selection');
      selectionController.updateSelectionByIMESelection(block.getBlockId(), leadingPosition, newValue.selection);
      _updateLastEditingValue(newValue);
      _render.markNeedsPaint();
      return;
    }

    // How to update texts given oldValue and newValue:
    // 1. Find the first different character from left hand side, remember left same count as leftCommonCount
    // 2. Find the first different character from right hand side, remember right same count as rightCount
    // 3. Characters from leftCommonCount to (length-rightCount) in the oldValue are to be deleted(as deleteFrom and deleteTo)
    // 4. Characters from leftCommonCount to (length-rightCount) in the newValue are to be inserted(as insertStr)
    //
    // Shown as the following diagram
    //     leftCommonCount=5    rightCount=2
    //                 |         |
    //                 v         v
    // old string: Hello_xyz_bit_mn
    // new string: Hello123456789mn
    //                 ^         ^
    //                 |         |
    //    leftCommonCount=5    rightCount=2
    var oldText = oldValue.text;
    var newText = newValue.text;
    // Find the same part in oldValue and newValue
    var leftCommonCount = helper.findLeftDifferent(oldText, newText, newValue.selection.extentOffset - 1);
    // Find the same part in newValue. But never exceed newValue.selection.extentOffset, because this position is newly edited
    var rightCount = helper.findRightDifferent(oldText, newText, newValue.selection.extentOffset);
    MyLogger.verbose('_updateAndSaveText: oldText=($oldText), newText=($newText)');
    MyLogger.verbose('_updateAndSaveText: leftCommonCount=$leftCommonCount, rightCount=$rightCount');
    // Find the positions deleteFrom and deleteTo, and find the insertStr
    var changeFrom = leftCommonCount;
    var changeTo = oldText.length - rightCount;
    MyLogger.info('_updateAndSaveText: changeFrom=$changeFrom, changeTo=$changeTo');
    var insertFrom = leftCommonCount;
    var insertTo = newText.length - rightCount;
    var insertStr = (insertTo > insertFrom)? newText.substring(insertFrom, insertTo): '';
    MyLogger.info('_updateAndSaveText: insertFrom=$insertFrom, insertTo=$insertTo, insertStr=$insertStr');

    // Split insertStr to handle every line separately
    insertStr = insertStr.replaceAll('\r', '');
    var insertStrWithoutNewline = insertStr.split('\n');
    if(insertStrWithoutNewline.isEmpty) return; // Not possible

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
    //   2.1 Insert first line at the current position of editing block, update cursor position
    //   2.2 If there are at least 2 lines, spawn a new line, and insert last line after current cursor position
    //   2.3 If there are more than 2 lines, insert other lines at the end of first line
    // 3. If the structure of document has been changed, refresh it.

    // Step 1
    MyLogger.info('_updateAndSaveText: inSelection=$inSelection, old selection=${oldValue.selection}');
    // If oldValue's selection is not collapsed,
    // the deleted selection should be handled by replaceText method in the following code
    if(inSelection && oldValue.selection.isCollapsed) {
      MyLogger.info('_updateAndSaveText: delete selection');
      selectionController.deleteSelectedContent(refreshView: false);
      leadingPosition = selectionController.lastExtentBlockPos;
    }

    // Step 2.1
    final firstLineBlockState = widget.controller.getEditingBlockState()!;
    final firstLine = insertStrWithoutNewline[0];
    MyLogger.info('_updateAndSaveText: leadingPosition=$leadingPosition');
    firstLineBlockState.replaceText(leadingPosition + changeFrom, leadingPosition + changeTo, firstLine, affinity);
    int firstLineLength = leadingPosition + changeFrom + firstLine.length;
    int newExtentPosition = leadingPosition + newValue.selection.extentOffset;
    String lastLineBlockId = firstLineBlockState.getBlockId(); // Assume the first line is also the last line
    if(lineCount == 1) {
      MyLogger.info('_updateAndSaveText: collapse in block: ${firstLineBlockState.getBlockId()}, pos=$newExtentPosition');
      selectionController.collapseInBlock(firstLineBlockState.getBlockId(), newExtentPosition, false);
    }
    // Step 2.2
    if(lineCount >= 2) {
      final lastLine = insertStrWithoutNewline[lineCount - 1];
      firstLineBlockState.replaceText(firstLineLength, firstLineLength, lastLine, affinity);
      lastLineBlockId = firstLineBlockState.spawnNewLineAtOffset(firstLineLength);
      newExtentPosition = lastLine.length;
      // Step 2.3
      firstLineBlockState.appendBlocksWithTexts(insertStrWithoutNewline.sublist(1, lineCount - 1));
    }

    if(lineCount <= 1) {
      _updateLastEditingValue(newValue);
    } else {
      _resetEditingState();
    }
    // Step 3
    if(lineCount >= 2 || !selectionInSingleBlock) {
      refreshDocWithoutBlockState(lastLineBlockId, newExtentPosition);
    }

    selectionController.resetCursor();
    _render.updateParagraph();
    _render.markNeedsLayout();
  }

  void _resetEditingState() {
    var newEditingValue = _createTextEditingValue(_initialTextValue);
    _textInputConnection!.setEditingState(newEditingValue);
    _lastEditingValue = _createTextEditingValue('');
    MyLogger.info('_resetEditingState: newEditingValue=$newEditingValue');
  }
  TextEditingValue _createTextEditingValue(String text) {
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
  void _updateLastEditingValue(TextEditingValue newValue) {
    _lastEditingValue = newValue;
  }
  void _deleteSelectionOrCharacter() {
    if(!widget.controller.selectionController.isCollapsed()) {
      widget.controller.selectionController.deleteSelectedContent();
    } else {
      var editingState = widget.controller.getEditingBlockState();
      editingState?.deletePreviousCharacter();
    }
    _resetEditingState();
  }
  TextEditingValue _stripeInitialText(TextEditingValue value) {
    if(_initialTextValue.isNotEmpty && value.text.startsWith(_initialTextValue)) {
      MyLogger.info('_stripeInitialText: initialTextValue detected, original value=$value');
      var newText = value.text.substring(1); // stripe _initialTextValue

      var baseOffset = value.selection.baseOffset - 1 > 0? value.selection.baseOffset - 1: 0;
      var extentOffset = value.selection.extentOffset - 1 > 0? value.selection.extentOffset - 1: 0;
      var newSelection = TextSelection(baseOffset: baseOffset, extentOffset: extentOffset);

      var newComposing = TextRange.empty;
      if(value.composing.isValid) {
        var start = value.composing.start - 1 > 0? value.composing.start - 1: 0;
        var end = value.composing.end - 1 > 0? value.composing.end - 1: 0;
        newComposing = TextRange(start: start, end: end);
      }
      value = TextEditingValue(text: newText, selection: newSelection, composing: newComposing);
    }
    return value;
  }

  void _onScroll() {
    MyLogger.debug('_onScroll: height=${_currentSize?.height}, min=${_scrollController.position.pixels}, extent=${_scrollController.position.viewportDimension}');
    _updateHandles();
    Util.runInPostFrame(() { // Run in the post frame, to make sure the render object is updated
      _updateActiveBlocks();
    });
  }
  void _updateActiveBlocks() {
    var paras = widget.controller.document?.paragraphs;
    if(paras == null) return;

    int minIndex = -1, maxIndex = -1;
    for(int idx = 0; idx < paras.length; idx++) {
      final paragraph = paras[idx];
      var blockState = paragraph.getEditState();
      if(blockState == null || !blockState.mounted) continue;

      final renderObject = blockState.getRender();
      // final renderObject = blockState.context.findRenderObject() as MindBlockImplRenderObject;
      if(renderObject == null || !renderObject.attached) {
        MyLogger.debug('block[${paragraph.getBlockIndex()}] is not in the view');
        renderObject?.clearCurrentBox();
        continue;
      }

      final viewPort = RenderAbstractViewport.of(renderObject);
      final vpOffset = viewPort.getOffsetToReveal(renderObject, 0.0);
      final size = renderObject.semanticBounds.size;

      final widgetTop = vpOffset.offset;
      final widgetBottom = vpOffset.offset + size.height;
      final viewPortTop = _scrollController.position.pixels;
      final viewPortBottom = _scrollController.position.viewportDimension;

      if(_isOverlap(widgetTop, widgetBottom, viewPortTop, viewPortBottom)) {
        MyLogger.debug('block[${paragraph.getBlockIndex()}] is in the view');
        if(minIndex == -1) {
          maxIndex = minIndex = idx;
        } else {
          maxIndex = idx;
        }
        // WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        renderObject.updateCurrentBox();
        // });
      } else {
        MyLogger.debug('block[${paragraph.getBlockIndex()}] is not in the view');
        renderObject.clearCurrentBox();
      }
    }
    _activeBlockFirstIndex = minIndex;
    _activeBlockLastIndex = maxIndex;
  }
  bool _isOverlap(double top1, double bottom1, double top2, double bottom2) {
    if(bottom1 < top2 || bottom1 < top1) {
      return false;
    } else {
      return true;
    }
  }
  void _updateHandles() {
    var newPixel = _scrollController.position.pixels;
    double _pixelDelta = newPixel - _currentScrollPixel;
    _currentScrollPixel = newPixel;
    widget.controller.selectionController.updateHandlesPointByDelta(Offset(0.0, _pixelDelta));
  }
  void _resetActiveBlockIndexes() {
    _activeBlockFirstIndex = 0;
    _activeBlockLastIndex = widget.controller.document!.paragraphs.length - 1;
  }
}