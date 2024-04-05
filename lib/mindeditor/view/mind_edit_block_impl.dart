import 'package:flutter/rendering.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../document/paragraph_desc.dart';
import '../document/text_desc.dart';
import '../setting/constants.dart';
import 'edit_cursor.dart';
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
  EditCursor? editCursor;
  Rect? currentCursorRect;
  double fontSize;
  Rect? currentBox;

  MindBlockImplRenderObject({
    Key? key,
    required this.texts,
    required this.controller,
    required this.block,
    required this.fontSize,
    this.readOnly = false,
  }) {
    paragraph = _buildParagraph(texts, fontSize);
    placeHolder = _buildPlaceHolder(texts.isTitle()? '输入标题': '输入文字', fontSize);
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

  @override
  void performLayout() {
    paragraph.layout(constraints, parentUsesSize: true);
    placeHolder.layout(constraints, parentUsesSize: true);
    var _para = texts.getPlainText().isEmpty? placeHolder: paragraph;
    size = Size(constraints.maxWidth, _para.computeMinIntrinsicHeight(constraints.maxWidth));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final _firstPoint = localToGlobal(Offset.zero);
    final _lastPoint = localToGlobal(Offset(size.width, size.height));
    currentBox = Rect.fromPoints(_firstPoint, _lastPoint);
    List<Rect>? boxes;
    final canvas = context.canvas;
    final hasCursor = texts.hasCursor();
    var textSelection = texts.getTextSelection();
    if(textSelection != null) {
      var currentTextPos = TextPosition(offset: textSelection.extentOffset);
      final _lineHeight = paragraph.getPreferredHeight();
      MyLogger.verbose('efantest: lineHeight=$_lineHeight');
      // currentCursorRect用于计算上一行、下一行的位置，所以必须更新
      currentCursorRect = _calculateCursorRectByPosition(currentTextPos, height: _lineHeight);
      if(!textSelection.isCollapsed) {
        boxes = _drawSelectionBoxes(canvas, offset, textSelection, _lineHeight);
      }

      if(!readOnly && hasCursor) {
        _drawCursor(canvas, offset, _lineHeight);
        _drawComposing(canvas, offset, _lineHeight); // 如果处于输入法状态中，在输入中的文字下方画线
      }
    }
    // 如果没有文字，则当鼠标悬停时、或光标定位在此block时，要显示place holder。如果是标题，则不管鼠标和光标都显示place holder
    if(!readOnly && texts.getPlainText().isEmpty && (block.isMouseEntered() || hasCursor || texts.isTitle())) {
      placeHolder.paint(context, offset);
    } else {
      paragraph.paint(context, offset);
    }
    if(boxes != null && boxes.isNotEmpty) {
      // _drawLeaderLayer(context, boxes, offset);
    }
  }
  void _drawCursor(Canvas canvas, Offset offset, double height) {
    // 如果editCursor不存在，新建之
    editCursor ??= EditCursor(timeoutFunc: markNeedsPaint);
    editCursor!.paint(canvas, currentCursorRect!, offset);
  }
  List<Rect> _drawSelectionBoxes(Canvas canvas, Offset offset, TextSelection textSelection, double height) {
    var boxes = paragraph.getBoxesForSelection(textSelection);
    List<Rect> result = [];
    if(boxes.isNotEmpty) {
      final paint = Paint()
        ..color = Colors.blue[100]!; //.withOpacity(0.5);
      for (final box in boxes) {
        Rect rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
        canvas.drawRect(rect.shift(offset), paint);
        result.add(rect);
      }
    }
    return result;
  }
  void _drawComposing(Canvas canvas, Offset offset, double height) {
    final editingValue = CallbackRegistry.getLastEditingValue();
    if(editingValue == null || !editingValue.composing.isValid) {
      return;
    }
    final composing = editingValue.composing;
    final paint = Paint()..color = Colors.black..style = PaintingStyle.stroke;
    Offset startPos = _convertOffsetFromPosition(TextPosition(offset: composing.start));
    Offset endPos = _convertOffsetFromPosition(TextPosition(offset: composing.end));
    Offset from = startPos.translate(0, height) + offset;
    Offset to = endPos.translate(0, height) + offset;
    canvas.drawLine(from, to, paint);
  }
  void _drawLeaderLayer(PaintingContext context, List<Rect> boxes, Offset offset) {
    // Add start handle layer, which is linked with CompositedTransformFollower by linkOfStartHandle
    var linkOfStartHandle = controller.selectionController.getLayerLinkOfStartHandle();
    if(linkOfStartHandle == null) {
      return;
    }
    var startPoint = Offset(boxes.first.left, boxes.first.top);
    context.pushLayer(
      LeaderLayer(link: linkOfStartHandle, offset: startPoint + offset),
      super.paint,
      Offset.zero,
    );
    // Add end handle layer, which is linked with CompositedTransformFollower by linkOfEndHandle
    var linkOfEndHandle = controller.selectionController.getLayerLinkOfEndHandle();
    if(linkOfEndHandle == null) {
      return;
    }
    var endPoint = Offset(boxes.last.right, boxes.last.bottom);
    context.pushLayer(
      LeaderLayer(link: linkOfEndHandle, offset: endPoint + offset),
      super.paint,
      Offset.zero,
    );
  }

  @override
  void dispose() {
    editCursor?.stopCursor();
    editCursor = null;
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  // 光标相关
  // position表示文字位置
  void activeCursor(int position) {
    editCursor?.stopCursor();
    editCursor = EditCursor(timeoutFunc: markNeedsPaint);
    currentCursorRect = _calculateCursorRectByPosition(TextPosition(offset: position));
    markNeedsPaint();
  }
  void releaseCursor() {
    if(editCursor != null) {
      editCursor!.stopCursor();
      editCursor = null;
      markNeedsPaint();
    }
  }
  void resetCursor() {
    if(editCursor != null) {
      editCursor!.resetCursor();
      markNeedsPaint();
    }
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

  Offset _convertOffsetFromPosition(TextPosition pos) {
    var canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
    var offset = paragraph.getOffsetForCaret(pos, canvasRect);
    return offset;
  }

  Offset getOffsetOfNthCharacter(int num) {
    var textPosition = TextPosition(offset: num);
    return _calcOffsetOfTextPosition(textPosition);
  }
  Offset _calcOffsetOfTextPosition(TextPosition pos) {
    var offset = _convertOffsetFromPosition(pos);
    return Offset(offset.dx, offset.dy + fontSize / 2); // 稍微偏下一点，不然会定位到上一行的位置
  }

  int getTextPositionOfPreviousLine() {
    var offset = Offset(currentCursorRect!.left, currentCursorRect!.top - fontSize / 2);
    if(!paragraph.size.contains(offset)) {
      return -1;
    }
    var pos = paragraph.getPositionForOffset(offset);
    MyLogger.debug('efantest: new pos=$pos for offset($offset)');
    return pos.offset;
  }
  int getTextPositionOfNextLine() {
    var offset = Offset(currentCursorRect!.left, currentCursorRect!.bottom + fontSize / 2);
    if(!paragraph.size.contains(offset)) {
      return -1;
    }
    var pos = paragraph.getPositionForOffset(offset);
    return pos.offset;
  }

  void redraw() {
    updateParagraph();
    markNeedsLayout();
    markNeedsPaint();
  }
}
