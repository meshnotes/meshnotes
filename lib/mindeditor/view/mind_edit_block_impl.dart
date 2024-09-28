import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../document/paragraph_desc.dart';
import '../document/text_desc.dart';
import '../setting/constants.dart';
import 'my_paragraph.dart';

class MindEditBlockImpl extends SingleChildRenderObjectWidget {
  final ParagraphDesc texts;
  final Controller controller;
  final MindEditBlockState block;
  final double fontSize;
  final bool readOnly;

  const MindEditBlockImpl({
    Key? key,
    required this.texts,
    required this.controller,
    required this.block,
    required this.fontSize,
    this.readOnly = false,
  }): super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return MindBlockImplRenderObject(
      texts: texts,
      controller: controller,
      block: block,
      fontSize: fontSize,
      readOnly: readOnly,
    );
  }

  @override
  void updateRenderObject(BuildContext context, MindBlockImplRenderObject renderObject) {
    renderObject
      ..setTexts(texts)
      ..setController(controller)
      ..setFontSize(fontSize)
      ..setReadOnly(readOnly);
  }
}

class MindBlockImplRenderObject extends RenderBox {
  bool readOnly;
  MindEditBlockState block;
  ParagraphDesc texts;
  late MyRenderParagraph paragraph;
  late MyRenderParagraph placeHolder;
  Controller controller;
  double fontSize;
  Rect? _currentBox;

  MindBlockImplRenderObject({
    Key? key,
    required this.texts,
    required this.controller,
    required this.block,
    required this.fontSize,
    this.readOnly = false,
  }) {
    paragraph = _buildParagraph(texts, fontSize);
    placeHolder = _buildPlaceHolder(texts.isTitle()? 'Write note title here': 'Write note text here', fontSize);
    block.setRender(this);
  }

  static MyRenderParagraph _buildParagraph(ParagraphDesc texts, double fontSize) {
    return MyRenderParagraph(
      _buildTextSpanAndCalcTotalLength(texts, fontSize),
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontSize: fontSize,
      ),
    );
  }
  static MyRenderParagraph _buildPlaceHolder(String holderText, double fontSize) {
    return MyRenderParagraph(
      TextSpan(
        text: holderText,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.black26,
        ),
      ),
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontSize: fontSize,
      ),
    );
  }

  updateParagraph() {
    paragraph.text = _buildTextSpanAndCalcTotalLength(texts, fontSize);
    paragraph.strutStyle = StrutStyle(
      fontSize: fontSize,
    );
  }

  void setTexts(ParagraphDesc _texts) {
    if(texts == _texts) {
      return;
    }
    texts = _texts;
    updateParagraph();
    markNeedsLayout();
  }
  void setController(Controller _controller) {
    if(controller == _controller) {
      return;
    }
    controller = _controller;
  }
  void setFontSize(double _fontSize) {
    if(fontSize == _fontSize) {
      return;
    }
    fontSize = _fontSize;
    updateParagraph();
    markNeedsLayout();
  }
  void setReadOnly(bool _b) {
    readOnly = _b;
    updateParagraph();
    markNeedsLayout();
  }

  static TextSpan _buildTextSpanAndCalcTotalLength(ParagraphDesc texts, double defaultFontSize) {
    if(texts.getType().startsWith(Constants.blockTypeHeadlinePrefix)) {
      return TextSpan(
        text: texts.getPlainText(),
        style: _getDefaultTextStyle(size: defaultFontSize),
      );
    } else {
      List<TextSpan> spans = [];
      for (var t in texts.getTextsClone()) {
        var sp = TextSpan(
          text: t.text,
          style: _buildTextStyle(t, defaultFontSize),
        );
        spans.add(sp);
      }
      return TextSpan(
        text: '',
        style: _getDefaultTextStyle(size: defaultFontSize),
        children: spans,
      );
    }
  }

  static TextStyle _getDefaultTextStyle({double? size}) {
    return TextStyle(
      fontSize: size,
      color: Colors.black,
    );
  }
  static TextStyle _buildTextStyle(TextDesc t, double defaultFontSize) {
    var color = _buildColor(t.color);
    TextDecoration? decoration;
    if(t.isUnderline) {
      decoration = TextDecoration.underline;
    }
    return TextStyle(
      fontSize: t.fontSize > 0? t.fontSize: defaultFontSize,
      color: color,
      fontWeight: t.isBold? FontWeight.bold: FontWeight.normal,
      fontStyle: t.isItalic? FontStyle.italic: FontStyle.normal,
      decoration: decoration,
    );
  }
  static Map<TextColor, Color> colorMap = {
    TextColor.blue: Colors.blue,
    TextColor.green: Colors.green,
    TextColor.grey: Colors.grey,
    TextColor.black: Colors.black,
    TextColor.red: Colors.red,
    TextColor.white: Colors.white,
  };
  static var defaultTextColor = Colors.black;

  static Color _buildColor(TextColor? c) {
    if(c == null) {
      return defaultTextColor;
    }
    if(colorMap.containsKey(c)) {
      return colorMap[c]!;
    }
    return defaultTextColor;
  }

  Rect? getCurrentBox() => _currentBox;
  void updateCurrentBox() {
    _currentBox = _getCurrentRenderGlobalRect();
  }
  void clearCurrentBox() {
    _currentBox = null;
  }

  @override
  void performLayout() {
    paragraph.layout(constraints, parentUsesSize: true);
    placeHolder.layout(constraints, parentUsesSize: true);
    var _para = texts.getPlainText().isEmpty? placeHolder: paragraph;
    size = Size(constraints.maxWidth, _para.computeMinIntrinsicHeight(constraints.maxWidth));
    MyLogger.debug('performLayout: blockId=${texts.getBlockId()}, idx=${texts.getBlockIndex()}');
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    updateCurrentBox();
    MyLogger.debug('paint: blockId=${texts.getBlockId()}, currentBox=$_currentBox, idx=${texts.getBlockIndex()}');
    final canvas = context.canvas;
    final hasCursor = texts.hasCursor();
    var textSelection = texts.getTextSelection();
    if(textSelection != null) {
      final _lineHeight = paragraph.getPreferredHeight();
      MyLogger.verbose('MindEditBlockImplRenderObject: lineHeight=$_lineHeight');
      var currentTextPos = TextPosition(offset: textSelection.extentOffset);
      // MyLogger.info('MindEditBlockImplRenderObject: currentTextPos=$currentTextPos, extent=${textSelection.extentOffset}');
      final currentCursorRect = _calculateCursorRectByPosition(currentTextPos, height: _lineHeight);
      MyLogger.debug('paint: index=${texts.getBlockIndex()}, currentCursorRect=$currentCursorRect');
      if(!textSelection.isCollapsed) {
        _drawSelectionBoxes(canvas, offset, textSelection, _lineHeight);
      }

      if(!readOnly && hasCursor) {
        _drawCursor(canvas, offset, currentCursorRect);
        _drawComposing(canvas, offset, _lineHeight); // Draw underline when input method is composing
      }
    }
    // When text is empty, and mouse hover, or cursor locating in this block, show the place holder
    // If this is title block, show place holder when title is empty
    // If the current note has no content, show place holder
    if(!readOnly && texts.getPlainText().isEmpty && (block.isMouseEntered() || hasCursor || texts.isTitle() || !(controller.document?.hasContent()?? false))) {
      placeHolder.paint(context, offset);
    } else {
      paragraph.paint(context, offset);
    }
  }
  Offset? getCursorOffsetOfPos(int pos) {
    final lineHeight = paragraph.getPreferredHeight();
    final rect = _calculateCursorRectByPosition(TextPosition(offset: pos), height: lineHeight);
    var localPoint = Offset(rect.left, rect.bottom);
    var globalPoint = localToGlobal(localPoint);
    return globalPoint;
  }

  void _drawCursor(Canvas canvas, Offset offset, Rect currentCursorRect) {
    final editCursor = Controller().selectionController.getCursor();
    editCursor.paint(canvas, currentCursorRect, offset);
  }
  void _drawSelectionBoxes(Canvas canvas, Offset offset, TextSelection textSelection, double height) {
    var boxes = paragraph.getBoxesForSelection(textSelection);
    if(boxes.isNotEmpty) {
      final paint = Paint()
        ..color = Colors.blue[100]!; //.withOpacity(0.5);
      for (final box in boxes) {
        Rect rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
        canvas.drawRect(rect.shift(offset), paint);
      }
    }
  }
  void _drawComposing(Canvas canvas, Offset offset, double height) {
    final editingValue = CallbackRegistry.getLastEditingValue();
    if(editingValue == null || !editingValue.composing.isValid) {
      return;
    }
    final composing = editingValue.composing;
    final leadingPos = Controller().selectionController.lastExtentBlockPos - editingValue.selection.extentOffset;
    final paint = Paint()..color = Colors.black..style = PaintingStyle.stroke;
    Offset startPos = _convertOffsetFromPosition(TextPosition(offset: composing.start + leadingPos));
    Offset endPos = _convertOffsetFromPosition(TextPosition(offset: composing.end + leadingPos));
    Offset from = startPos.translate(0, height) + offset;
    Offset to = endPos.translate(0, height) + offset;
    canvas.drawLine(from, to, paint);
  }

  Rect _getCurrentRenderGlobalRect() {
    final _firstPoint = localToGlobal(Offset.zero);
    final _lastPoint = localToGlobal(Offset(size.width, size.height));
    return Rect.fromPoints(_firstPoint, _lastPoint);
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  Rect _calculateCursorRectByPosition(TextPosition pos, {double? height}) {
    Offset newPos = _convertOffsetFromPosition(pos);
    var rect = Rect.fromLTWH(newPos.dx,newPos.dy, 1, height?? fontSize);
    return rect;
  }

  int getPositionByOffset(Offset offset) {
    var textPosition = paragraph.getPositionForOffset(offset);
    return textPosition.offset;
  }
  // void updateCursor(Offset offset) {
  //   debugPrint('efantest: update [$uniqueKey] cursor for id=${texts.id}');
  //   var currentTextPos = paragraph.getPositionForOffset(offset);
  //   var node = controller.getDocTreeNode(texts.id)!;
  //   node.editingPosition = EditingPosition()..totalPosition = currentTextPos.offset;
  //   _updateCursorByTextPos(currentTextPos);
  // }

  // void _calculateCursorByTextPos(TextPosition pos) {
  //   Offset newPos = _convertOffsetFromPosition(pos);
  //   var cursor = Rect.fromLTWH(newPos.dx,newPos.dy, 1, _fontHeight);
  //   if(editCursor != null) {
  //     editCursor!.cursorRect = cursor;
  //   } else {
  //     editCursor = EditCursor(
  //       cursorRect: cursor,
  //       timeoutFunc: markNeedsPaint,
  //     );
  //   }
  // }


  Offset getOffsetOfNthCharacter(int num) {
    var textPosition = TextPosition(offset: num);
    return _calcOffsetOfTextPosition(textPosition);
  }
  /// Only for calculating selection handles
  Offset getGlobalOffsetOfNthCharacterBottom(int num) {
    final textPosition = TextPosition(offset: num);
    final offset = _convertOffsetFromPosition(textPosition);
    final bottomOffset = Offset(offset.dx, offset.dy + fontSize);
    return localToGlobal(bottomOffset);
  }
  Offset _calcOffsetOfTextPosition(TextPosition pos) {
    var offset = _convertOffsetFromPosition(pos);
    return Offset(offset.dx, offset.dy + fontSize / 2); // A little lower than offset.dx, or it may be located at the upper line
  }
  Offset _convertOffsetFromPosition(TextPosition pos) {
    var canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
    var offset = paragraph.getOffsetForCaret(pos, canvasRect);
    return offset;
  }

  void redraw() {
    updateParagraph();
    markNeedsLayout();
    markNeedsPaint();
  }
}
