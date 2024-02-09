import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/key_control.dart';
import 'package:mesh_note/mindeditor/view/view_helper.dart' as helper;
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
    MyLogger.info('efantest: new MindEditBlock for block(id=${texts.getBlockId()})');
  }

  final ParagraphDesc texts;
  final Controller controller;
  final bool readOnly;
  final bool ignoreLevel;

  @override
  State<StatefulWidget> createState() => MindEditBlockState();
}

// 代理MindEditBlockImpl的按键操作
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
      MyLogger.info('efantest: initializing MindEditBlockState for block(id=${widget.texts.getBlockId()})');
      widget.controller.setBlockStateToTreeNode(widget.texts.getBlockId(), this);
    }
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.info('efantest: build MindEditBlockState for block(id=${widget.texts.getBlockId()})');
    if(!widget.readOnly) {
      var myId = widget.texts.getBlockId();
      if(widget.texts.getTextSelection() != null) {
        MyLogger.debug('efantest: editing position is not null: ${widget.texts.getPlainText()}');
        // 如果在initState阶段发现editingPosition不为空，则此block必须负责自己的激活
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
              child: Icon(Icons.circle, size: Constants.bulletedSize), //Text('A'),//Text('•'),
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
      onTapDown: (TapDownDetails details) {
        MyLogger.debug('efantest: on tap down, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onTapDown(details, widget.texts.getBlockId());
      },
      onPanStart: (DragStartDetails details) {
        MyLogger.debug('efantest: on pan start, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanStart(details, widget.texts.getBlockId());
      },
      onPanUpdate: (DragUpdateDetails details) {
        MyLogger.debug('efantest: on pan update, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanUpdate(details, widget.texts.getBlockId());
      },
      onPanDown: (DragDownDetails details) {
        MyLogger.debug('efantest: on pan down, id=${widget.key}, local_offset=${details.localPosition}, global_offset=${details.globalPosition}');
        widget.controller.gestureHandler.onPanDown(details, widget.texts.getBlockId());
      },
      onPanCancel: () {
        MyLogger.debug('efantest: on pan cancel, id=${widget.key}');
        widget.controller.gestureHandler.onPanCancel(widget.texts.getBlockId());
      },
      onPanEnd: (DragEndDetails details) {
        MyLogger.debug('efantest: on pan end');
      },
      onLongPressStart: (LongPressStartDetails details) {
        var blockId = widget.texts.getBlockId();
        MyLogger.info('Long press start on block($blockId)');
        widget.controller.gestureHandler.onLongPressStart(details, blockId);
      },
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
    // 只有在桌面端，并且不是readOnly模式，才显示抓手
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
    // 只有在桌面端，并且不是标题行时，才显示block左侧的handler
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

  void requestCursorAtPosition(int position) {
    var myId = widget.texts.getBlockId();
    var oldEditingBlockId = widget.controller.getEditingBlockId();

    // 更新编辑中的block Id
    widget.controller.setEditingBlockId(myId);

    // 更新当前选区的位置，这个必须在更新完block ID之后，因为需要判断当前ID来决定是否要发送事件
    var block = widget.texts;
    block.newTextSelection(position);

    // 如果切换了block，先隐藏光标，再在新block显示，并且更新TextEditingValue
    if(oldEditingBlockId != null && oldEditingBlockId != myId) {
      MyLogger.verbose('efantest: oldEditingBlockId=$oldEditingBlockId, myId=$myId');
      var lastBlock = widget.controller.getBlockState(oldEditingBlockId);
      lastBlock?.releaseCursor();
    }
    // 如果光标就在本block，只需要重置定时器。否则启动光标闪烁
    if(oldEditingBlockId == myId) {
      _render!.resetCursor();
    } else {
      _render!.activeCursor(position);
    }

    // 如果需要的话，唤起键盘
    CallbackRegistry.requestKeyboard();
  }
  void requestCursorAtOffset(Offset offset) {
    int totalPosition = _render!.getPositionByOffset(offset);
    requestCursorAtPosition(totalPosition);
  }

  void updateCursorToLastCharacter() {
    var length = widget.texts.getTotalLength();
    requestCursorAtPosition(length);
  }
  void updateCursorToFirstCharacter() {
    requestCursorAtPosition(0);
  }
  void updateCursorToLastLineByDx(double dx) {
    var lastPosition = widget.texts.getTotalLength();
    _updateCursorToDxAndDyOfNthCharacter(dx, lastPosition);
  }
  void updateCursorToFirstLineByDx(double dx) {
    _updateCursorToDxAndDyOfNthCharacter(dx, 0);
  }
  void _updateCursorToDxAndDyOfNthCharacter(double dx, int n) {
    var offset = _render!.getOffsetOfNthCharacter(n);
    requestCursorAtOffset(Offset(dx, offset.dy));
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

  TextEditingValue getCurrentTextEditingValue() {
    final block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! getCurrentTextEditingValue(): getTextSelection returns null!');
      return const TextEditingValue(text: '');
    }
    MyLogger.debug('efantest: getCurrentTextEditingValue: nodeId=${block.getBlockId()}, text=${block.getPlainText()}, selection=$selection');
    var composing = TextRange.empty;
    var _lastValue = CallbackRegistry.getLastEditingValue();
    if(Controller.instance.environment.isDesktop() && (_lastValue != null && _lastValue.composing.isValid)) {
      final start = _lastValue.composing.start;
      final end = _lastValue.composing.end;
      final len = end - start;
      composing = TextRange(start: selection.baseOffset, end: selection.baseOffset + len);
      MyLogger.debug('efantest: text len=${block.getPlainText().length}, selection=$selection, composing=$composing');
    }
    return TextEditingValue(
      text: block.getPlainText(),
      selection: selection,
      composing: composing,
    );
  }

  void updateAndSaveText(TextEditingValue oldValue, TextEditingValue newValue, bool sameText) {
    MyLogger.verbose('efantest: Save $newValue to $oldValue with parameter $sameText');
    var block = widget.texts;
    if(block.getTextSelection() == null) {
      MyLogger.debug('Unbelievable!!! updateAndSaveText(): getTextSelection returns null!');
      return;
    }
    // 如果文本相同，只需要修改光标和选区
    if(sameText) {
      MyLogger.warn('efantest: same Text');
      block.setTextSelection(newValue.selection);
      _render!.markNeedsPaint();
      return;
    }

    // 文本不同，需要更新文本。更新的方法是：
    // 1）从左开始找到第一个不同的位置leftCount
    // 2）从右开始找到第一个不同的位置rightCount
    // 3）原字符串中的leftCount到length - rightCount，是被删除的部分
    // 4）新字符串中的leftCount到length - rightCount，是要添加的部分
    // 5）新增部分的样式，跟随左边的TextSpan还是右边的TextSpan，由TextSelection.affinity决定
    // 5.1）对于upstream，跟随左边
    // 5.2）对于downstream,跟随右边

    var oldText = oldValue.text;
    var newText = newValue.text;
    // 对于左半部分，oldValue和newValue都是一样的
    var leftCount = helper.findLeftDifferent(oldText, newText, newValue.selection.extentOffset - 1);
    // 对于右半部分，当到达newValue.selection.extentOffset时，无论如何都要停，因为这个位置一定是新编辑的
    var rightCount = helper.findRightDifferent(oldText, newText, newValue.selection.extentOffset);
    MyLogger.verbose('efantest: oldText=($oldText), newText=($newText)');
    MyLogger.verbose('efantest: leftCount=$leftCount, rightCount=$rightCount');
    // 找到左部分的最后一个TextSpan
    var deleteFrom = leftCount;
    var deleteTo = oldText.length - rightCount;
    var deleteCount = deleteTo - deleteFrom;
    MyLogger.verbose('efantest: deleteFrom=$deleteFrom, deleteCount=$deleteCount');
    var insertFrom = leftCount;
    var insertTo = newText.length - rightCount;
    MyLogger.verbose('efantest: insertFrom=$insertFrom, insertTo=$insertTo');
    // 需要插入的新字符串
    var insertStr = (insertTo > insertFrom)? newText.substring(insertFrom, insertTo): "";
    MyLogger.verbose('efantest: insertStr=$insertStr');
    var texts = widget.texts.getTextsClone();
    int idx;
    for(idx = 0; idx < texts.length; idx++) {
      if(texts[idx].text.length >= deleteFrom) { // 找到要删除的TextSpan
        break;
      }
      deleteFrom -= texts[idx].text.length;
    }
    MyLogger.verbose('efantest: idx=$idx, deleteFrom=$deleteFrom');
    var leftIdx = idx;
    // 从texts[idx].text的第deleteFrom个字符开始，一直删除deleteCount个字符
    while(deleteCount > 0) {
      var len = texts[idx].text.length;
      var remaining = len - deleteFrom;
      MyLogger.verbose('efantest: len=$len, remaining=$remaining');
      if(deleteCount > remaining) {
        texts[idx].text = texts[idx].text.substring(0, deleteFrom);
        MyLogger.verbose('efantest: In 1, deleteFrom=$deleteFrom, new text=${texts[idx].text}');
        if(texts[idx].text.isEmpty) {
          texts.removeAt(idx); // TODO 这里如果把最后一个TextDesc删除掉，可能会有bug
          MyLogger.verbose('efantest: remove index $idx, remains=$texts, new length=${texts.length}');
        } else {
          idx++;
        }
        deleteCount -= remaining;
        deleteFrom = 0;
        MyLogger.verbose('efantest: Now deleteCount=$deleteCount, deleteFrom=$deleteFrom');
      } else {
        var leftPart = texts[idx].text.substring(0, deleteFrom);
        var rightPart = texts[idx].text.substring(deleteFrom + deleteCount);
        texts[idx].text = leftPart + rightPart;
        MyLogger.verbose('efantest: In 2, deleteFrom=$deleteFrom, new text=${texts[idx].text}');
        deleteCount = 0;
      }
    }

    if(insertStr.isNotEmpty && insertStr != '\n') {
      // 如果替换是在同一个text span下，直接在这里插入。否则需要根据TextAffinity来决定新字符串应该在哪个TextSpan
      if(leftIdx == idx) {
        var leftPart = texts[idx].text.substring(0, deleteFrom);
        var rightPart = texts[idx].text.substring(deleteFrom);
        texts[idx].text = leftPart + insertStr + rightPart;
        MyLogger.verbose('efantest: In the same text span, new text=${texts[idx].text}');
      } else {
        if(newValue.selection.affinity == TextAffinity.upstream) {
          texts[leftIdx].text = texts[leftIdx].text + insertStr;
          MyLogger.verbose(
              'efantest: affinity upstream, new text=${texts[leftIdx].text}');
        } else {
          texts[idx].text = insertStr + texts[idx].text;
          MyLogger.verbose(
              'efantest: affinity downstream, new text=${texts[idx].text}');
        }
      }
    }

    MyLogger.verbose('efantest: texts=$texts, texts.length=${texts.length}');
    widget.texts.updateTexts(texts); // 刷新文字，重新计算plainText，并保存到数据库
    block.setTextSelection(newValue.selection);
    _triggerBlockModified();

    if(insertStr == '\n') {
      MyLogger.verbose('efantest: spawnNewLine at $leftCount');
      spawnNewLineAtOffset(leftCount);
    }
    _render!.resetCursor();
    _render!.updateParagraph();
    _render!.markNeedsLayout();
    _updateNavigatorViewIfNeeded();
  }

  void releaseCursor() {
    // 先释放editingPosition，再调用releaseCursor()，因为releaseCursor()里面会调用markNeedPaint()
    var block = widget.texts;
    MyLogger.debug('efantest: releasing editingPosition of node(id=${block.getBlockId()})');
    block.clearTextSelection();
    _render?.releaseCursor();
  }

  void moveCursorLeft(FunctionKeys funcKeys) {
    var block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! moveCursorLeft(): getTextSelection returns null!');
      return;
    }
    // 如果当前在选择状态，且没有按下任何功能键，则取消选区并移到选区左侧
    if(!selection.isCollapsed) {
      if(funcKeys.nothing()) {
        requestCursorAtPosition(selection.start);
        return;
      }
    }

    // 尝试在本block内左移，如果失败，找到上一个block，并将光标置于最后一个字符
    var pos = selection.extentOffset;
    if(pos > 0) {
      var newPos = pos - 1;
      if(funcKeys.shiftPressed) { // shift pressed
        block.setTextSelection(selection.copyWith(extentOffset: newPos));
        CallbackRegistry.refreshTextEditingValue();
        // 停止光标闪烁
        _render!.releaseCursor();
        _render!.markNeedsPaint();
      } else {
        requestCursorAtPosition(newPos);
      }
    } else {
      var previousBlockState = widget.texts.getPrevious()?.getEditState();
      previousBlockState?.updateCursorToLastCharacter();
    }
  }
  void moveCursorRight(FunctionKeys funcKeys) {
    var block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! moveCursorRight(): getTextSelection returns null!');
      return;
    }
    // 如果当前在选择状态，且没有按下任何功能键，则取消选区并移到选区右侧
    if(!selection.isCollapsed) {
      if(funcKeys.nothing()) {
        requestCursorAtPosition(selection.end);
        return;
      }
    }

    // 尝试在本block内右移，如果失败，找到下一个block，并将光标置于首字符
    var totalLength = widget.texts.getTotalLength();
    var pos = selection.extentOffset;
    if(pos < totalLength) {
      var newPos = pos + 1;
      if(funcKeys.shiftPressed) {
        block.setTextSelection(selection.copyWith(extentOffset: newPos));
        CallbackRegistry.refreshTextEditingValue();
        // 停止光标闪烁
        _render!.releaseCursor();
        _render!.markNeedsPaint();
      } else {
        requestCursorAtPosition(newPos);
      }
    } else {
      var nextBlockState = widget.texts.getNext()?.getEditState();
      nextBlockState?.updateCursorToFirstCharacter();
    }
  }
  void moveCursorUp(FunctionKeys funcKeys) {
    var block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! moveCursorUp(): getTextSelection returns null!');
      return;
    }
    // 尝试在本block上移，如果失败，尝试移到上一个block的最后一行，如果没有上一个block,则移到本block首字符
    var newPos = _render!.getTextPositionOfPreviousLine();
    if(newPos >= 0) {
      if(funcKeys.shiftPressed) {
        block.setTextSelection(selection.copyWith(extentOffset: newPos));
        CallbackRegistry.refreshTextEditingValue();
        // 停止光标闪烁
        _render!.releaseCursor();
        _render!.markNeedsPaint();
      } else {
        requestCursorAtPosition(newPos);
      }
    } else {
      var previousBlockState = widget.texts.getPrevious()?.getEditState();
      if(previousBlockState == null) {
        updateCursorToFirstCharacter();
      } else {
        var n = selection.extentOffset;
        var offset = _render!.getOffsetOfNthCharacter(n);
        previousBlockState.updateCursorToLastLineByDx(offset.dx);
      }
    }
  }
  void moveCursorDown(FunctionKeys funcKeys) {
    var block = widget.texts;
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! moveCursorDown(): getTextSelection returns null!');
      return;
    }
    var totalLength = widget.texts.getTotalLength();
    // 尝试在本block下移，如果失败，尝试移到下一个block的第一行，如果没有下一个block,则移到本block末尾字符
    var newPos = _render!.getTextPositionOfNextLine();
    if(newPos >= 0 && newPos <= totalLength) {
      if(funcKeys.shiftPressed) {
        block.setTextSelection(selection.copyWith(extentOffset: newPos));
        CallbackRegistry.refreshTextEditingValue();
        // 停止光标闪烁
        _render!.releaseCursor();
        _render!.markNeedsPaint();
      } else {
        requestCursorAtPosition(newPos);
      }
    } else {
      var nextBlockState = widget.texts.getNext()?.getEditState();
      if(nextBlockState == null) {
        updateCursorToLastCharacter();
      } else {
        var n = selection.extentOffset;
        var offset = _render!.getOffsetOfNthCharacter(n);
        nextBlockState.updateCursorToFirstLineByDx(offset.dx);
      }
    }
  }

  void deletePreviousCharacter() {
    final block = widget.texts;
    // 尝试在本block删除，如果已经是第一个字符，则合并到前一个block
    var selection = block.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! deletePreviousCharacter(): getTextSelection returns null!');
      return;
    }
    var currentTextPos = selection.extentOffset;
    if(currentTextPos > 0) { // 可以在本block完成删除
      // 找到上一个字符所在的TextDesc块，再将其删除
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
      requestCursorAtPosition(selection.extentOffset - 1);
      _render!.updateParagraph();
      _render!.markNeedsLayout();
      CallbackRegistry.refreshTextEditingValue();
    } else { // 需要合并到上一个block
      var previousBlock = widget.texts.getPrevious();
      if(previousBlock == null) { // 已经是第一个block，什么都不做
        return;
      } else {
        var previousBlockState = previousBlock.getEditState();
        // 记下上一block的文本长度，光标要定位在这里
        var length = previousBlock.getTotalLength();
        previousBlockState!.mergeParagraph(widget.texts.getBlockId());
        CallbackRegistry.refreshDoc(activeBlockId: previousBlock.getBlockId(), position: length);
      }
    }
    _updateNavigatorViewIfNeeded();
    _triggerBlockModified();
  }
  void deleteCurrentCharacter() {
    // 尝试在本block删除，如果已经是最后一个字符，则将下一个block合并进来
    var selection = widget.texts.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! deleteCurrentCharacter(): getTextSelection returns null!');
      return;
    }
    var currentTextPos = selection.extentOffset;
    if(currentTextPos < widget.texts.getTotalLength()) {
      // 找到当前字符所在的TextDesc，并删除
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
      if(nextBlockId == null) { // 已经是最后一个block，什么都不做
        return;
      } else {
        mergeParagraph(nextBlockId);
        CallbackRegistry.refreshDoc(activeBlockId: widget.texts.getBlockId(), position: currentTextPos);
      }
    }
    _updateNavigatorViewIfNeeded();
    _triggerBlockModified();
  }
  void deleteSelection() {
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
    CallbackRegistry.refreshTextEditingValue();

    _updateNavigatorViewIfNeeded();
    _triggerBlockModified();
  }

  void mergeParagraph(String nextBlockId) {
    var doc = widget.controller.document!;
    var myParagraph = doc.getParagraph(widget.texts.getBlockId())!;
    int lastPosition = myParagraph.getTotalLength();
    var nextParagraph = doc.getParagraph(nextBlockId)!;
    myParagraph.appendNonEmptyTexts(nextParagraph.getTextsClone());
    doc.removeParagraph(nextBlockId);

    requestCursorAtPosition(lastPosition);
    _render!.redraw();
    _triggerBlockModified();
  }

  bool triggerSelectedBold() {
    if(widget.texts.isTitle()) { // title不能设置粗体
      return false;
    }
    return _triggerSelectedTextSpanStyle(TextDesc.boldKey);
  }
  bool triggerSelectedItaly() {
    if(widget.texts.isTitle()) { // title不能设置斜体
      return false;
    }
    return _triggerSelectedTextSpanStyle(TextDesc.italicKey);
  }
  bool triggerSelectedUnderline() {
    if(widget.texts.isTitle()) { // title不能设置下划线
      return false;
    }
    return _triggerSelectedTextSpanStyle(TextDesc.underlineKey);
  }
  String getBlockType() {
    return widget.texts.getType();
  }
  bool setBlockType(String type) {
    if(widget.texts.isTitle()) { // title不能设置block类型
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
    if(widget.texts.isTitle()) { // title不有设置listing
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

  // 实现步骤
  // 1. 找出有效的选择范围
  // 2. 调用triggerSelectedTextSpanStyle触发风格改变
  // 3. 刷新显示
  bool _triggerSelectedTextSpanStyle(String propertyName) {
    final block = widget.texts;
    // 1. 找出有效的选择范围
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

    // 2. 改变风格
    bool ret = block.triggerSelectedTextSpanStyle(selectionStart, selectionEnd, propertyName);

    // 3. 刷新
    _render!.updateParagraph();
    _render!.markNeedsLayout();

    _triggerBlockModified();
    return ret;
  }

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
    if(idx < clonedTexts.length && offset < clonedTexts[idx].text.length) { // 当前TextDesc需要分割
      var oldText = clonedTexts[idx].text;
      remaining = clonedTexts[idx].clone();
      remaining.text = oldText.substring(offset);
      clonedTexts[idx].text = oldText.substring(0, offset); // 注意当offset为0的时候，这里会留下一个空的字符串，需要在后面删除
    }
    if(idx < clonedTexts.length - 1) { // 当前TextDesc后面还有TextDesc
      result = [];
      var newList = clonedTexts.sublist(idx + 1);
      for(var item in newList) {
        clonedTexts.remove(item);
        result.add(item);
      }
    }
    if(idx > 0 && idx < clonedTexts.length && clonedTexts[idx].text.isEmpty) {
      // 删除前面留下的空字符串，但如果这是仅存的TextDesc，就不能删除
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
    MyLogger.debug('efantest: spawnNewLine');
    var selection = widget.texts.getTextSelection();
    if(selection == null) {
      MyLogger.warn('Unbelievable!!! spawnNewLine(): getTextSelection returns null!');
      return;
    }
    // 找到当前光标所在的TextDesc下标idx，以及在该TextDesc下的偏移offset
    var offset = selection.extentOffset;

    spawnNewLineAtOffset(offset);
  }
  void spawnNewLineAtOffset(int offset) {
    // 将TextSpan切分，然后生成新的ParagraphDesc
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
    MyLogger.info('efantest: currentSize=$currentSize, totalSize=$totalSize');
    if(totalSize != null && totalSize.bottom - currentSize.bottom <= 5 + Controller.instance.setting.blockNormalLineHeight + 5 + 10) {
      MyLogger.info('efantest: need scroll');
      CallbackRegistry.scrollDown(5 + Controller.instance.setting.blockNormalLineHeight + 5 + 10);
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