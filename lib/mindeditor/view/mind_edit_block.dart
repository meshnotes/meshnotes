import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../document/paragraph_desc.dart';
import '../document/text_desc.dart';
import '../setting/constants.dart';
import 'mind_edit_block_impl.dart';

class MindEditBlock extends StatefulWidget {
  MindEditBlock({
    Key? key,
    required this.texts,
    required this.controller,
    this.readOnly = false,
    this.ignoreLevel = false,
  }): super(key: key) {
    MyLogger.info('MindEditBlock: create new block(id=${texts.getBlockId()})');
  }

  final ParagraphDesc texts;
  final Controller controller;
  final bool readOnly;
  final bool ignoreLevel;

  @override
  State<StatefulWidget> createState() => MindEditBlockState();
}

class MindEditBlockState extends State<MindEditBlock> {
  bool _mouseEntered = false;
  MindBlockImplRenderObject? _render;
  Widget? _leading;

  void setRender(MindBlockImplRenderObject r) {
    _render = r;
  }
  MindBlockImplRenderObject? getRender() {
    return _render;
  }

  @override
  void initState() {
    super.initState();
    if(!widget.readOnly) {
      MyLogger.info('MindEditBlockState: initializing MindEditBlockState for block(id=${getBlockId()})');
      widget.controller.setBlockStateToTreeNode(getBlockId(), this);
    }
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.info('MindEditBlockState: build MindEditBlockState for block(id=${getBlockId()})');
    if(!widget.readOnly) {
      var myId = getBlockId();
      // If this block has cursor, current editing block id should be set, and the IME should be active
      if(widget.texts.getTextSelection() != null && widget.texts.hasCursor()) {
        widget.controller.setEditingBlockId(myId);
        CallbackRegistry.requestKeyboard();
      }
    }
    var blockImpl = _buildBlockImpl();
    var handler = _buildHandler();
    var result = _buildAll(handler, blockImpl);
    return result;
  }

  Widget _buildBlockImpl() {
    var fontSize = widget.controller.setting.blockNormalFontSize;
    if(widget.texts.isTitle()) {
      fontSize = widget.controller.setting.blockTitleFontSize;
    } else {
      switch(widget.texts.getType()) {
        case Constants.blockTypeHeadline1:
          fontSize = widget.controller.setting.blockHeadline1FontSize;
          break;
        case Constants.blockTypeHeadline2:
          fontSize = widget.controller.setting.blockHeadline2FontSize;
          break;
        case Constants.blockTypeHeadline3:
          fontSize = widget.controller.setting.blockHeadline3FontSize;
          break;
      }
      switch(widget.texts.getListing()) {
        case Constants.blockListTypeBulleted:
          _leading = SizedBox(
            height: fontSize,
            width: Constants.tabWidth,
            child: const Align(
              alignment: Alignment.bottomCenter,
              child: Icon(Icons.circle, size: Constants.bulletedSize), //Text('•'),
            ),
          );
          break;
        case Constants.blockListTypeChecked:
          _leading = GestureDetector(
            child: SizedBox(
              height: fontSize,
              width: Constants.tabWidth,
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: Icon(Icons.check_box_outline_blank_rounded, size: Constants.tabWidth - 2,),
              ),
            ),
            onTap: () {
              var ok = setBlockListing(Constants.blockListTypeCheckedConfirm);
              if(ok) {
                CallbackRegistry.refreshDoc();
              }
            },
          );
          break;
        case Constants.blockListTypeCheckedConfirm:
          _leading = GestureDetector(
            child: SizedBox(
              height: fontSize,
              width: Constants.tabWidth,
              child: const Align(
                alignment: Alignment.center,
                child: Icon(Icons.check_box_rounded, size: Constants.tabWidth - 2,),
              ),
            ),
            onTap: () {
              var ok = setBlockListing(Constants.blockListTypeChecked);
              if(ok) {
                CallbackRegistry.refreshDoc();
              }
            },
          );
          break;
        case Constants.blockListTypeNone:
          _leading = null;
          break;
      }
    }
    var block = MindEditBlockImpl(
      texts: widget.texts,
      controller: widget.controller,
      block: this,
      fontSize: fontSize,
      readOnly: widget.readOnly,
    );
    var gesture = GestureDetector(
      child: block,
      // onLongPressDown: (LongPressDownDetails details) {
      //   var blockId = widget.texts.getBlockId();
      //   MyLogger.info('Long press down on block($blockId)');
      //   widget.controller.gestureHandler.onLongPressDown(details, blockId);
      // },
      // onLongPressStart: (LongPressStartDetails details) {
      //   var blockId = widget.texts.getBlockId();
      //   widget.controller.gestureHandler.onLongPressStart(details, blockId);
      // },
      // onLongPressCancel: () {
      //   MyLogger.info('long press cancel');
      // },
      // This will cause 300ms delay of onTapDown event
      // onDoubleTapDown: (TapDownDetails details) {
      //   var blockId = widget.texts.getBlockId();
      //   MyLogger.info('Double tap down on block($blockId)');
      //   widget.controller.gestureHandler.onDoubleTapDown(details, blockId);
      // },
    );
    Widget container = gesture;
    if(Controller.instance.isDebugMode) {
      container = Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12, width: 4),
        ),
        child: gesture,
      );
    }
    var editMouseRegion = MouseRegion(
      child: container,
      cursor: SystemMouseCursors.text,
    );
    var expanded = Expanded(
      child: widget.readOnly? block: editMouseRegion,
    );
    return expanded;
  }

  Widget? _buildHandler() {
    // Display block handler only on desktop environment and non-readonly mode
    if(Controller.instance.environment.isDesktop() && !widget.readOnly) {
      return BlockHandler(
        show: _mouseEntered,
        controller: widget.controller,
      );
    }
    return null;
  }

  Widget _buildAll(Widget? handler, Widget block) {
    var items = <Widget>[block];
    if(_leading != null) {
      items.insert(0, _leading!);
    }
    if(handler != null) {
      items.insert(0, handler);
      var row = Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      );
      if(widget.texts.isTitle()) {
        return row;
      }
      // Hide or display block handler only on non-title block
      var blockMouseRegion = MouseRegion(
        child: row,
        onHover: (PointerHoverEvent event) {
          _showHandler();
        },
        onExit: (PointerExitEvent event) {
          _hideHandler();
        },
      );
      return blockMouseRegion;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items,
    );
  }

  void setEditingBlockAndResetCursor({bool requestKeyboard=true}) {
    var myId = widget.texts.getBlockId();
    // Update editing block id
    widget.controller.setEditingBlockId(myId);

    widget.controller.selectionController.resetCursor();

    // Show keyboard and update TextEditingValue only when user request position actively(by clicking or moving cursor)
    if(requestKeyboard) {
      CallbackRegistry.requestKeyboard();
    }
  }

  void _showHandler() {
    if(_mouseEntered) {
      return;
    }
    setState((){
      _mouseEntered = true;
    });
  }
  void _hideHandler() {
    if(!_mouseEntered) {
      return;
    }
    setState(() {
      _mouseEntered = false;
    });
  }
  bool isMouseEntered() => _mouseEntered;

  void replaceText(int deleteFrom, int deleteTo, String insertStr, TextAffinity affinity) {
    int deleteCount = deleteTo - deleteFrom;
    var texts = widget.texts.getTextsClone();
    int idx;
    for(idx = 0; idx < texts.length; idx++) {
      if(texts[idx].text.length >= deleteFrom) { // Find the TextSpan containing content to be deleted
        break;
      }
      deleteFrom -= texts[idx].text.length;
    }
    MyLogger.info('replaceText: idx=$idx, deleteFrom=$deleteFrom, deleteCount=$deleteCount');
    var leftIdx = idx;
    // Delete deleteCount texts from deleteFrom in texts[idx].text
    while(deleteCount > 0) {
      var len = texts[idx].text.length;
      var remaining = len - deleteFrom;
      MyLogger.verbose('replaceText: len=$len, remaining=$remaining');
      if(deleteCount > remaining) {
        texts[idx].text = texts[idx].text.substring(0, deleteFrom);
        MyLogger.verbose('replaceText: In 1, deleteFrom=$deleteFrom, new text=${texts[idx].text}');
        if(texts[idx].text.isEmpty) {
          texts.removeAt(idx); // TODO A bug may occur if the last TextDesc is deleted
          MyLogger.verbose('replaceText: remove index $idx, remains=$texts, new length=${texts.length}');
        } else {
          idx++;
        }
        deleteCount -= remaining;
        deleteFrom = 0;
        MyLogger.verbose('replaceText: Now deleteCount=$deleteCount, deleteFrom=$deleteFrom');
      } else {
        var leftPart = texts[idx].text.substring(0, deleteFrom);
        var rightPart = texts[idx].text.substring(deleteFrom + deleteCount);
        texts[idx].text = leftPart + rightPart;
        MyLogger.verbose('replaceText: In 2, deleteFrom=$deleteFrom, new text=${texts[idx].text}');
        deleteCount = 0;
      }
    }

    if(insertStr.isNotEmpty && insertStr != '\n') {
      // If the deleted text does not cross TextSpan, then insert the insertStr directly in this position.
      // Otherwise, use affinity to decide in which TextSpan the insertStr is inserted.
      if(leftIdx == idx) {
        var leftPart = texts[idx].text.substring(0, deleteFrom);
        var rightPart = texts[idx].text.substring(deleteFrom);
        texts[idx].text = leftPart + insertStr + rightPart;
        MyLogger.verbose('replaceText: In the same text span, new text=${texts[idx].text}');
      } else {
        if(affinity == TextAffinity.upstream) {
          texts[leftIdx].text = texts[leftIdx].text + insertStr;
          MyLogger.verbose('replaceText: affinity upstream, new text=${texts[leftIdx].text}');
        } else {
          texts[idx].text = insertStr + texts[idx].text;
          MyLogger.verbose('replaceText: affinity downstream, new text=${texts[idx].text}');
        }
      }
    }
    MyLogger.verbose('replaceText: texts=$texts, texts.length=${texts.length}');
    widget.texts.updateTexts(texts); // Update text, re-calculate plainText, and save to db
    _triggerBlockModified();
    _updateNavigatorViewIfNeeded();
  }

  void clearSelectionAndReleaseCursor() {
    // Just mark render as need paint
    var block = widget.texts;
    block.clearTextSelection();
    _render?.markNeedsPaint();
  }

  void deletePreviousCharacter() {
    /// Try to delete previous character in editing block, but if it is the start of a block, should merge with to previous block
    final block = widget.texts;
    final selectionController = widget.controller.selectionController;
    if(!selectionController.isCollapsed()) {
      MyLogger.warn('deletePreviousCharacter() should be called only when selection is collapsed!');
      return;
    }
    var currentTextPos = selectionController.lastExtentBlockPos;
    int blockIndex = _findBlockIndex(getBlockId());
    if(blockIndex < 0) {
      MyLogger.warn('deletePreviousCharacter: could not find the index of block(id=${getBlockId()})');
      return;
    }
    if(currentTextPos > 0) { // Could be operated in the current block
      // Find the TextDesc of previous character, and delete it
      var offset = currentTextPos - 1;
      var clonedTexts = block.getTextsClone();
      for(var t in clonedTexts) {
        if(offset < t.text.length) {
          var oldText = t.text;
          var newText = oldText.substring(0, offset) + oldText.substring(offset + 1);
          if(newText.isNotEmpty) {
            t.text = newText;
          } else {
            clonedTexts.remove(t);
          }
          block.updateTexts(clonedTexts);
          break;
        }
        offset -= t.text.length;
      }
      selectionController.collapseInBlock(getBlockId(), currentTextPos - 1, true);
      _render!.updateParagraph();
      _render!.markNeedsLayout();
      CallbackRegistry.refreshTextEditingValue();
    } else { // Should be merge into previous block
      var previousBlock = widget.texts.getPrevious();
      if(previousBlock == null) { // Do nothing if it is the first block
        return;
      } else {
        var previousBlockState = previousBlock.getEditState();
        // Get the text length of previous block, at which the cursor should be located
        var length = previousBlock.getTotalLength();
        previousBlockState!.mergeParagraph(widget.texts.getBlockId());
        CallbackRegistry.refreshDoc(activeBlockId: previousBlock.getBlockId(), position: length);
      }
    }
    _updateNavigatorViewIfNeeded();
    _triggerBlockModified();
  }
  void deleteCurrentCharacter() {
    // Try to delete character in editing block, but if it is the end of a block, should merge with next block
    var selection = widget.texts.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! deleteCurrentCharacter(): getTextSelection returns null!');
      return;
    }
    var currentTextPos = selection.extentOffset;
    if(currentTextPos < widget.texts.getTotalLength()) {
      // Find the TextDesc of current character, and delete it
      var offset = currentTextPos;
      var clonedTexts = widget.texts.getTextsClone();
      for(var t in clonedTexts) {
        if(offset < t.text.length) {
          var oldText = t.text;
          var newText = oldText.substring(0, offset) + oldText.substring(offset + 1);
          if(newText.isNotEmpty) {
            t.text = newText;
          } else {
            clonedTexts.remove(t);
          }
          widget.texts.updateTexts(clonedTexts);
          break;
        }
        offset -= t.text.length;
      }
      _render!.updateParagraph();
      _render!.markNeedsLayout();
      CallbackRegistry.refreshTextEditingValue();
    } else {
      var nextBlockId = widget.texts.getNext()?.getBlockId();
      if(nextBlockId == null) { // Do nothing if it is the last block
        return;
      } else {
        mergeParagraph(nextBlockId);
        CallbackRegistry.refreshDoc(activeBlockId: widget.texts.getBlockId(), position: currentTextPos);
      }
    }
    _updateNavigatorViewIfNeeded();
    _triggerBlockModified();
  }

  /// Return plain text of selected range
  String getSelectedContent() {
    const invalidResult = '';
    var block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! getSelectedContent(): getTextSelection returns null!');
      return invalidResult;
    }
    int selectionStart = selection.start;
    int selectionEnd = selection.end;
    if(selectionStart >= selectionEnd) {
      return invalidResult;
    }
    if(selectionStart < 0) {
      selectionStart = 0;
    }
    if(selectionEnd > widget.texts.getTotalLength()) {
      selectionEnd = widget.texts.getTotalLength();
    }
    return widget.texts.getPlainText().substring(selectionStart, selectionEnd);
  }

  /// Delete selected content, and update view
  void deleteSelection({bool needRefreshEditingValue=true}) {
    var block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! deleteSelection(): getTextSelection returns null!');
      return;
    }
    var selectionStart = selection.start;
    var selectionEnd = selection.end;
    if(selectionStart >= selectionEnd) {
      return;
    }
    if(selectionStart < 0) {
      selectionStart = 0;
    }
    if(selectionEnd > widget.texts.getTotalLength()) {
      selectionEnd = widget.texts.getTotalLength();
    }
    widget.texts.deleteRange(selectionStart, selectionEnd);

    block.newTextSelection(selectionStart);
    _render!.updateParagraph();
    _render!.markNeedsLayout();
    if(block.hasCursor() && needRefreshEditingValue) {
      CallbackRegistry.refreshTextEditingValue();
    }

    _updateNavigatorViewIfNeeded();
    _triggerBlockModified();
  }

  String getBlockId() => widget.texts.getBlockId();

  (int, int) getWordPosRange(Offset offset) {
    int pos = _render!.getPositionByOffset(offset);
    MyLogger.info('getWordPosRange: pos=$pos');
    var plainText = widget.texts.getPlainText();
    var currentChar = plainText.codeUnitAt(pos);
    if(_isAlphabet(currentChar)) { // Find English word
      return _findWord(plainText, pos);
    } else { // Return current position
      if(pos == 0) {
        return (0, 1);
      }
      return (pos - 1, pos);
    }
  }
  bool _isAlphabet(int c) {
    return (c >= 'a'.codeUnitAt(0) && c <= 'z'.codeUnitAt(0)) || (c >= 'A'.codeUnitAt(0) && c <= 'Z'.codeUnitAt(0) || c == '_'.codeUnitAt(0));
  }
  (int, int) _findWord(String plainText, int pos) {
    int t = pos;
    while(t >= 0) {
      var c = plainText.codeUnitAt(t);
      if(!_isAlphabet(c)) {
        break;
      }
      t--;
    }
    int start = t + 1;
    t = pos;
    while(t < plainText.length) {
      var c = plainText.codeUnitAt(t);
      if(!_isAlphabet(c)) {
        break;
      }
      t++;
    }
    int end = t;
    return (start, end);
  }
  int _findBlockIndex(String blockId) {
    final paragraphs = widget.texts.parent.paragraphs;
    for(int idx = 0; idx < paragraphs.length; idx++) {
      if(paragraphs[idx].getBlockId() == blockId) {
        return idx;
      }
    }
    return -1;
  }

  void mergeParagraph(String nextBlockId) {
    var doc = widget.controller.document!;
    var myParagraph = doc.getParagraph(widget.texts.getBlockId())!;
    // int lastPosition = myParagraph.getTotalLength();
    var nextParagraph = doc.getParagraph(nextBlockId)!;
    myParagraph.appendNonEmptyTexts(nextParagraph.getTextsClone());
    doc.removeParagraph(nextBlockId);

    // requestCursorAtPosition(lastPosition);
    _render!.redraw();
    _triggerBlockModified();
  }

  bool triggerSelectedBold() {
    if(widget.texts.isTitle()) { // Cannot set bold style in title block
      return false;
    }
    return _triggerSelectedTextSpanStyle(TextDesc.boldKey);
  }
  bool triggerSelectedItaly() {
    if(widget.texts.isTitle()) { // Cannot set italic style in title block
      return false;
    }
    return _triggerSelectedTextSpanStyle(TextDesc.italicKey);
  }
  bool triggerSelectedUnderline() {
    if(widget.texts.isTitle()) { // Cannot set underline style in title block
      return false;
    }
    return _triggerSelectedTextSpanStyle(TextDesc.underlineKey);
  }
  String getBlockType() {
    return widget.texts.getType();
  }
  bool setBlockType(String type) {
    if(widget.texts.isTitle()) { // Cannot set block type in title block
      return false;
    }
    return _setBlockType(type);
  }
  bool _setBlockType(String blockType) {
    var paragraph = widget.texts;
    bool result = paragraph.setBlockType(blockType);
    if(result) {
      _render!.updateParagraph();
      _render!.markNeedsLayout();
      widget.controller.triggerBlockFormatChanged(paragraph);
      _triggerBlockModified();
    }
    return result;
  }

  String getBlockListing() {
    return widget.texts.getListing();
  }
  bool setBlockListing(String l) {
    if(widget.texts.isTitle()) { // Cannot set listing type in title block
      return false;
    }
    return _setBlockListing(l);
  }
  bool _setBlockListing(String l) {
    var paragraph = widget.texts;
    bool result = paragraph.setBlockListing(l);
    if(result) {
      _render!.updateParagraph();
      _render!.markNeedsLayout();
      widget.controller.triggerBlockFormatChanged(paragraph);
      _triggerBlockModified();
    }
    return result;
  }

  /// Set span type of selected text
  /// 1. Find the selection range
  /// 2. Invoke triggerSelectedTextSpanStyle to change the style
  /// 3. Refresh rendering
  bool _triggerSelectedTextSpanStyle(String propertyName) {
    final block = widget.texts;
    // 1. Find the selection range
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! _triggerSelectedTextSpanStyle(): getTextSelection returns null!');
      return false;
    }
    var selectionStart = selection.start;
    var selectionEnd = selection.end;
    if(selectionStart >= selectionEnd) {
      return false;
    }
    if(selectionStart < 0) {
      selectionStart = 0;
    }
    if(selectionEnd > block.getTotalLength()) {
      selectionEnd = block.getTotalLength();
    }

    // 2. Invoke triggerSelectedTextSpanStyle to change the style
    bool ret = block.triggerSelectedTextSpanStyle(selectionStart, selectionEnd, propertyName);

    // 3. Refresh rendering
    _render!.updateParagraph();
    _render!.markNeedsLayout();

    _triggerBlockModified();
    return ret;
  }

  /// Invoke when a new line should be inserted at offset
  List<TextDesc> _cutCurrentPositionAndGetRemains(int offset) {
    var clonedTexts = widget.texts.getTextsClone();
    int idx;
    for(idx = 0; idx < clonedTexts.length; ++idx) {
      var t = clonedTexts[idx].text;
      if(offset < t.length) {
        break;
      }
      offset -= t.length;
    }

    TextDesc? remaining;
    List<TextDesc>? result;
    if(idx < clonedTexts.length && offset < clonedTexts[idx].text.length) { // Find the TextDesc that should be cut
      var oldText = clonedTexts[idx].text;
      remaining = clonedTexts[idx].clone();
      remaining.text = oldText.substring(offset);
      clonedTexts[idx].text = oldText.substring(0, offset); // HERE!! If offset is 0, there will be an empty text, should be deleted later
    }
    if(idx < clonedTexts.length - 1) { // If there are more TextDesc following, copy them to result
      result = [];
      var newList = clonedTexts.sublist(idx + 1);
      for(var item in newList) {
        clonedTexts.remove(item);
        result.add(item);
      }
    }
    if(idx > 0 && idx < clonedTexts.length && clonedTexts[idx].text.isEmpty) {
      // HERE!! The empty text is deleted here
      clonedTexts.removeAt(idx);
    }
    widget.texts.updateTexts(clonedTexts);
    _render!.updateParagraph();
    _render!.markNeedsLayout();

    if(result == null) {
      if(remaining == null) {
        result = [TextDesc()];
      } else {
        result = [remaining];
      }
    } else {
      if(remaining != null) {
        result.insert(0, remaining);
      }
    }
    return result;
  }
  
  void spawnNewLine() {
    MyLogger.debug('spawnNewLine() invoked');
    var selection = widget.texts.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! spawnNewLine(): getTextSelection returns null!');
      return;
    }
    var offset = selection.extentOffset;
    spawnNewLineAtOffset(offset);
    // Only need to refresh TextEditingValue, don't close TextInputClient, or the Android device will hide the IME and display it again
    CallbackRegistry.refreshTextEditingValue();
  }

  /// Insert a new block by splitting TextSpan, and generate new ParagraphDesc object.
  /// Scroll down to make sure the new line is currently visible
  /// Finally, return the new generated Block ID
  String spawnNewLineAtOffset(int offset) {
    var newTexts = _cutCurrentPositionAndGetRemains(offset);
    var currentBlockId = widget.texts.getBlockId();
    var doc = widget.controller.document!;
    var newItem = doc.insertNewParagraphAfterId(currentBlockId, ParagraphDesc(texts: newTexts, listing: _getCurrentListing(), level: _getCurrentLevel()));

    CallbackRegistry.refreshDoc(activeBlockId: newItem.getBlockId());
    _triggerBlockModified();

    // Scroll list if this block is on the bottom of view
    //TODO should scroll after drawing the new block
    var render = getRender()!;
    final blockOffset = render.localToGlobal(Offset.zero);
    final currentSize = Rect.fromLTWH(blockOffset.dx, blockOffset.dy, render.size.width, render.size.height);
    final totalSize = CallbackRegistry.getEditStateSize();
    MyLogger.info('spawnNewLineAtOffset: currentSize=$currentSize, totalSize=$totalSize');
    if(totalSize != null && totalSize.bottom - currentSize.bottom <= 5 + Controller.instance.setting.blockNormalLineHeight + 5 + 10) {
      MyLogger.info('spawnNewLineAtOffset: need scroll');
      CallbackRegistry.scrollDown(5 + Controller.instance.setting.blockNormalLineHeight + 5 + 10);
    }
    return newItem.getBlockId();
  }
  void insertBlocksWithTexts(List<String> texts) {
    List<ParagraphDesc> paragraphs = [];
    for(var line in texts) {
      var textDesc = TextDesc()..text = line;
      var para = ParagraphDesc(texts: [textDesc], listing: _getCurrentListing(), level: _getCurrentLevel());
      paragraphs.add(para);
    }
    if(paragraphs.isNotEmpty) {
      widget.controller.document!.insertNewParagraphsAfterId(widget.texts.getBlockId(), paragraphs);
    }
  }

  String _getCurrentListing() {
    return widget.texts.getListing();
  }

  int _getCurrentLevel() {
    return widget.texts.getLevel();
  }

  void _updateNavigatorViewIfNeeded() {
    if(widget.texts.isTitle()) {
      Controller.instance.refreshDocNavigator();
      CallbackRegistry.resetTitleBar(Controller.instance.document!.getTitlePath());
    }
  }

  void _triggerBlockModified() {
    Controller.instance.document?.setIdle();
  }
}

class BlockHandler extends StatefulWidget {
  final bool show;
  final Controller controller;

  const BlockHandler({
    Key? key,
    required this.show,
    required this.controller,
  }): super(key: key);

  @override
  _BlockHandlerState createState() => _BlockHandlerState();
}

class _BlockHandlerState extends State<BlockHandler> {
  Color backgroundColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    backgroundColor = widget.controller.setting.blockHandlerDefaultBackgroundColor;
  }

  @override
  Widget build(BuildContext context) {
    var icon = Icon(
      Icons.drag_indicator,
      size: widget.controller.setting.blockHandlerSize,
      color: widget.controller.setting.blockHandlerColor,
    );
    var container = Container(
      child: icon,
      alignment: Alignment.center,
    );
    var opacity = Opacity(
      opacity: widget.show? 1.0: 0.0,
      child: Container(
        child: container,
        alignment: Alignment.topLeft,
        color: backgroundColor,
        height: widget.controller.setting.blockNormalLineHeight,
      ),
    );
    var mouseRegion = MouseRegion(
      child: opacity,
      cursor: widget.controller.getHandCursor(),
      onHover: (_) {
        setState(() {
          backgroundColor = widget.controller.setting.blockHandlerHoverBackgroundColor;
        });
      },
      onExit: (_) {
        setState(() {
          backgroundColor = widget.controller.setting.blockHandlerDefaultBackgroundColor;
        });
      },
    );
    return mouseRegion;
  }
}