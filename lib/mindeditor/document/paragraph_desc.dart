import 'dart:async';
import 'dart:convert';
import 'package:flutter/rendering.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/mindeditor/document/text_desc.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:my_log/my_log.dart';
import '../../util/util.dart';
import '../controller/controller.dart';
import '../setting/constants.dart';
import '../../util/idgen.dart';
import 'document.dart';

enum _BlockType {
  title,
  text,
  headline1,
  headline2,
  headline3,
}
enum _BlockListing {
  none,
  bulleted,
  checked,
  checkedConfirm,
}

class _AffectedTextSpan {
  int firstIndex = -1;
  int lastIndex = -1;
  int startAtFirstSpan = -1;
  int endAtLastSpan = -1;
}

class TextSpansStyle {
  bool isAllBold = false;
  bool isAllItalic = false;
  bool isAllUnderline = false;
}

class ExtraInfo {
  String content;
  int updatedAt;

  ExtraInfo({
    required this.content,
    required this.updatedAt,
  });

  ExtraInfo.fromJson(Map<String, dynamic> map): content = map['content'], updatedAt = map['timestamp'];

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'timestamp': updatedAt,
    };
  }
}

class ParagraphDesc {
  late String _id;
  late List<TextDesc> _texts;
  Map<String, ExtraInfo> _extra;
  String hash = '';
  _BlockType _type = _BlockType.text;
  _BlockListing _listing = _BlockListing.none;
  int _level = Constants.blockLevelDefault;
  String? _plainText;
  Document? _parent;
  Document get parent => _parent!;
  ParagraphDesc? _previous, _next;
  TextSelection? _editingPosition;
  bool _hasCursor = false;
  bool _showBaseLeader = false;
  bool _showExtentLeader = false;
  MindEditBlockState? _state;
  int _lastUpdate = 0;
  Timer? _idleTimer;

  ParagraphDesc({
    List<TextDesc>? texts,
    String extra = '',
    String? id,
    String? type,
    String? listing,
    int? level,
    int? time,
  }): _extra = _parseExtra(extra) {
    if(texts == null || texts.isEmpty) {
      MyLogger.debug('Init by unexpected empty texts($texts), fix it to default TextDesc list');
      texts = [TextDesc()];
    }
    _updateTexts(texts);
    _id = id ?? IdGen.getUid();
    if(type != null) {
      _type = _parseBlockType(type);
    }
    if(listing != null) {
      _listing = _parseBlockListing(listing);
    }
    if(level != null) {
      _level = level;
    }
    if(time != null) {
      _lastUpdate = time;
    } else {
      _lastUpdate = Util.getTimeStamp();
    }
  }
  ParagraphDesc.fromStringList(
    String _id,
    String type,
    String raw,
    String listing,
    int level,
  ): _id = _id, _type = _parseBlockType(type), _listing = _parseBlockListing(listing), _level = level, _extra = _parseExtra('') {
    _parseTexts(raw);
  }
  ParagraphDesc.fromTitle(String text):
    _id = Constants.keyTitleId,
    _type = _BlockType.title,
    _listing = _BlockListing.none,
    _level = 0,
    _extra = _parseExtra('') {
    _parseTexts(text);
  }
  factory ParagraphDesc.buildFromJson({
    required String id,
    required String jsonStr,
    required int time,
    String extra = '',
  }) {
    BlockContent block = BlockContent.fromJson(jsonDecode(jsonStr));
    return ParagraphDesc(
      id: id,
      type: block.type,
      listing: block.listing,
      level: block.level,
      texts: block.text,
      extra: extra,
      time: time,
    );
  }

  bool hasContent() {
    return _plainText!.trim().isNotEmpty;
  }
  String getPlainText() {
    return _plainText!;
  }
  String getBlockId() => _id;

  int getBlockIndex() {
    for(int idx = 0; idx < parent.paragraphs.length; idx++) {
      if(getBlockId() == parent.paragraphs[idx].getBlockId()) {
        return idx;
      }
    }
    return -1;
  }

  String getType() {
    return _convertBlockType(_type);
  }

  String getListing() {
    return _convertBlockListing(_listing);
  }

  int getLevel() {
    return _level;
  }

  void setDocDesc(Document p) {
    _parent = p;
  }

  List<TextDesc> getTextsClone() {
    return [..._texts];
  }

  // 要保存入库必须调用updateTexts
  void updateTexts(List<TextDesc> _t) {
    _updateTexts(_t);
    _storeBlock();
    _tryToSendEvent();
  }

  void updateExtra(String key, ExtraInfo info) {
    _extra[key] = info;
    _storeExtra();
  }
  void clearExtra(String key) {
    if(_extra.containsKey(key)) {
      _extra.remove(key);
      _storeExtra();
    }
  }

  String getExtra() {
    String result = '';
    if(_extra.isNotEmpty) {
      for(var e in _extra.entries) {
        final value = e.value;
        if(result.isNotEmpty) {
          result += '\n';
        }
        result += value.content;
      }
    }
    return result;
  }

  String getSelectedPlainText() {
    var selection = getTextSelection();
    if(selection == null || selection.isCollapsed) return '';

    var startPos = selection.start;
    var endPos = selection.end;
    return getPlainText().substring(startPos, endPos);
  }
  void newTextSelection(int pos) {
    setTextSelection(TextSelection.collapsed(offset: pos));
  }
  TextSelection? getTextSelection({int? extentOffset, int? baseOffset}) {
    return _editingPosition?.copyWith(baseOffset: baseOffset, extentOffset: extentOffset);
  }
  void clearTextSelection() {
    _setTextSelection(null);
    _hasCursor = false;
    _showBaseLeader = false;
    _showExtentLeader = false;
  }
  void setTextSelection(TextSelection _t, {bool isEditing = true, bool showBaseLeader = false, bool showExtentLeader = false}) {
    _setTextSelection(_t);
    _hasCursor = isEditing;
    _showBaseLeader = showBaseLeader;
    _showExtentLeader = showExtentLeader;
    if(isEditing) {
      Controller.instance.setEditingBlockId(getBlockId());
    }
  }
  bool isCollapsed() {
    return _editingPosition != null && _editingPosition!.isCollapsed;
  }
  bool hasCursor() => _hasCursor;
  bool showBaseLeader() => _showBaseLeader;
  bool showExtentLeader() => _showExtentLeader;

  void setEditState(MindEditBlockState state) {
    _state = state;
  }
  void clearEditState() {
    _state = null;
  }
  MindEditBlockState? getEditState() {
    return _state;
  }

  void flushDb() {
    _storeBlock(); // Save immediately
  }

  void storeObject(int timestamp) {
    var block = getBlockContent();
    var hash = block.getHash();
    var oldObject = Controller.instance.dbHelper.getObject(hash);
    if(oldObject == null) {
      Controller.instance.dbHelper.storeObject(hash, jsonEncode(block), timestamp);
    }
  }

  void drop() {
    Controller.instance.dbHelper.dropDocBlock(parent.id, getBlockId());
  }

  BlockContent getBlockContent() {
    return _convertToBlockContent();
  }

  int getLastUpdated() {
    return _lastUpdate;
  }

  void appendNonEmptyTexts(List<TextDesc>? newTexts) {
    if(newTexts == null) {
      return;
    }
    for(var t in newTexts) {
      if(t.text.isNotEmpty) {
        _texts.add(t);
      }
    }
    updateTexts(_texts);
  }
  int getTotalLength() {
    return getPlainText().length;
  }

  bool isTitle() {
    return _type == _BlockType.title;
  }

  bool hasExtra() {
    return _extra.isNotEmpty;
  }

  void setPrevious(ParagraphDesc? p) {
    _previous = p;
  }
  void setNext(ParagraphDesc? p) {
    _next = p;
  }
  ParagraphDesc? getNext() {
    return _next;
  }
  ParagraphDesc? getPrevious() {
    return _previous;
  }

  void deleteRange(int selectionStart, int selectionEnd) {
    var clonedTexts = getTextsClone();
    var affected = _getAffectedTextSpans(clonedTexts, selectionStart, selectionEnd);
    var firstIndex = affected.firstIndex;
    var lastIndex = affected.lastIndex;
    if(affected.endAtLastSpan > 0) { // 最后一个TextDesc可能要分裂
      _splitTextDesc(clonedTexts, lastIndex, affected.endAtLastSpan);
    }
    if(affected.startAtFirstSpan > 0) { // 第一个TextDesc可能要分裂
      _splitTextDesc(clonedTexts, firstIndex, affected.startAtFirstSpan);
      firstIndex++;
      lastIndex++;
    }
    for(var idx = lastIndex; idx >= firstIndex; idx--) {
      clonedTexts.removeAt(idx);
    }

    updateTexts(clonedTexts);
  }

  // 1. 通过选择范围找出受影响的TextDesc
  // 2. 遍历TextDesc判断将property设置为true还是false（默认设置为true）
  // 3. 设置TextDesc的相应property值，如有必要，需要分裂一头一尾的span
  bool triggerSelectedTextSpanStyle(int selectionStart, int selectionEnd, String propertyName) {
    var clonedTexts = getTextsClone();

    // 2. 获取可能受影响的TextDesc
    var affectedTextSpans = _getAffectedTextSpans(clonedTexts, selectionStart, selectionEnd);

    int firstIndex = affectedTextSpans.firstIndex;
    int lastIndex = affectedTextSpans.lastIndex;
    // 3. 判断设置为true还是false
    // 以bold为例，只有所有选中的文字都是粗体时，才触发“取消加粗”，否则，只要有一个文字不是粗体，就触发加粗
    bool newValue = false;
    for(int idx = firstIndex; idx <= lastIndex; idx++) {
      if(clonedTexts[idx].isPropertyTrue(propertyName) == false) {
        newValue = true;
        break;
      }
    }
    // 4. 设置TextDesc
    // 4.1 判断是否需要分裂，从最后一个开始，因为这样对下标的影响比较小，当仅有一个TextDesc受影响时，也能处理
    if(affectedTextSpans.endAtLastSpan > 0) { // 最后一个TextDesc可能要分裂
      var oldValue = clonedTexts[lastIndex].isPropertyTrue(propertyName);
      if(oldValue != newValue) { // 真的需要分裂，新插入的leftPart是需要设置propertyName: value的，所以不需要改变下标
        _splitTextDesc(clonedTexts, lastIndex, affectedTextSpans.endAtLastSpan);
      }
    }
    if(affectedTextSpans.startAtFirstSpan > 0) { // 第一个TextDesc可能要分裂
      var oldValue = clonedTexts[firstIndex].isPropertyTrue(propertyName);
      if(oldValue != newValue) { // 真的需要分裂
        _splitTextDesc(clonedTexts, firstIndex, affectedTextSpans.startAtFirstSpan);
        firstIndex++;
        lastIndex++;
      }
    }
    // 4.2 设置TextDesc
    for(int idx = firstIndex; idx <= lastIndex; idx++) {
      clonedTexts[idx].setProperty(propertyName, newValue);
    }

    updateTexts(clonedTexts);
    return newValue;
  }

  TextSpansStyle getTextSpansStyle(int start, int end) {
    // 如果未选择文本，返回风格为空
    if(start == end) {
      return TextSpansStyle();
    }
    bool isAllBold = true;
    bool isAllItalic = true;
    bool isAllUnderline = true;
    var clonedTexts = getTextsClone();
    MyLogger.debug('getTextSpansStyle: start=$start, end=$end');
    var affected = _getAffectedTextSpans(clonedTexts, start, end);
    for(int idx = affected.firstIndex; idx <= affected.lastIndex; idx++) {
      var item = clonedTexts[idx];
      if(item.isBold == false) {
        isAllBold = false;
      }
      if(item.isItalic == false) {
        isAllItalic = false;
      }
      if(item.isUnderline == false) {
        isAllUnderline = false;
      }
    }
    return TextSpansStyle()
      ..isAllBold = isAllBold
      ..isAllItalic = isAllItalic
      ..isAllUnderline = isAllUnderline
    ;
  }

  bool setBlockType(String blockType) {
    var newType = _parseBlockType(blockType);
    _updateBlockType(newType);
    return true;
  }

  bool setBlockListing(String blockListing) {
    var newListing = _parseBlockListing(blockListing);
    _updateBlockListing(newListing);
    return true;
  }

  // If timer is still counting, stop it and save to database immediately
  void close() {
  }

  void _updateTexts(List<TextDesc> _t) {
    if(_t.isEmpty) {
      MyLogger.debug('Update by unexpected empty texts($_t), fix it to default TextDesc list');
      _t = [TextDesc()];
    }
    // 删除或合并多余的TextDesc
    _compactTexts(_t);

    _texts = _t;
    var newPlainText = '';
    for (var t in _t) {
      newPlainText += t.text;
    }
    _plainText = newPlainText;
  }

  void _setTextSelection(TextSelection? _t) {
    TextSelection? old = _editingPosition;
    _editingPosition = _t;
    // If TextSelection did not changed, or current node is not being editing(for example, focus node
    // jumped from current node to other node), don't trigger SelectionChanged event
    if(old == _t || this != parent.getEditingBlockDesc()) {
      return;
    }
    var block = parent.getBlockState(_id);
    _triggerSelectionChanged(block?.widget.texts, _editingPosition);
  }
  void _triggerSelectionChanged(ParagraphDesc? para, TextSelection? selection) {
    var controller = Controller.instance;
    if(para != null && selection != null) {
      var textSpanStyle = para.getTextSpansStyle(selection.start, selection.end);
      controller.triggerSelectionChanged(textSpanStyle);
      controller.triggerBlockFormatChanged(para);
    } else {
      controller.triggerSelectionChanged(null);
      controller.triggerBlockFormatChanged(null);
    }
  }

  // Save text to database immediately
  void _storeBlock() {
    var dbHelper = Controller.instance.dbHelper;
    if(isTitle()) {
      MyLogger.verbose('Save to title');
      parent.updateTitle(getPlainText());
    }
    MyLogger.verbose('Save to blocks: id=${getBlockId()}');
    var block = _convertToBlockContent();
    _lastUpdate = Util.getTimeStamp();
    dbHelper.storeDocBlock(parent.id, getBlockId(), jsonEncode(block), _lastUpdate);
    // dbHelper.updateDoc(parent.doc.id, Util.getTimeStamp());
    parent.setModified();
  }
  // Save extra to database
  void _storeExtra() {
    var dbHelper = Controller.instance.dbHelper;
    if(isTitle()) return;
    dbHelper.updateDocBlockExtra(parent.id, getBlockId(), jsonEncode(_extra));
  }

  BlockContent _convertToBlockContent() {
    var block = BlockContent(
      type: _convertBlockType(_type),
      listing: _convertBlockListing(_listing),
      level: _level,
      text: _texts,
    );
    return block;
  }

  void _parseTexts(String raw) {
    if(raw.isEmpty) {
      _updateTexts([TextDesc()]);
      return;
    }
    List<TextDesc> texts = [];
    if(isTitle()) { // 标题只是普通文本，其他块是json文本
      var textDesc = TextDesc()..text = raw;
      texts = [textDesc];
    } else {
      texts = _parseJson(raw);
    }
    MyLogger.verbose('efantest: _parseTexts result=$texts');
    _updateTexts(texts);
  }

  List<TextDesc> _parseJson(String raw) {
    List l = jsonDecode(raw);
    List<TextDesc> result = [];
    for(var span in l) {
      if(span is! Map) {
        continue;
      }
      var m = span as Map<String, dynamic>;
      var textDesc = TextDesc.fromJson(m);
      result.add(textDesc);
    }
    return result;
  }

  static Map<String, ExtraInfo> _parseExtra(String raw) {
    Map<String, ExtraInfo> result = {};
    if(raw.isNotEmpty) {
      Map<String, dynamic>? map;
      try {
        final _m = jsonDecode(raw);
        if (_m is! Map<String, dynamic>) return result;
        map = _m;
      } catch(e) {
        MyLogger.warn('_parseExtra: $e');
        return result;
      }
      for (var e in map.entries) {
        String key = e.key;
        dynamic value = e.value;
        try {
          ExtraInfo info = ExtraInfo.fromJson(value);
          result[key] = info;
        } catch(e) {
          MyLogger.warn('_parseExtra traversing map: $e');
        }
      }
    }
    return result;
  }

  void _updateBlockType(_BlockType newType) {
    if(newType != _type) {
      _type = newType;
      _storeBlock();
    }
  }
  static _BlockType _parseBlockType(String str) {
    switch(str) {
      case Constants.blockTypeTitleTag:
        return _BlockType.title;
      case Constants.blockTypeTextTag:
        return _BlockType.text;
      case Constants.blockTypeHeadline1:
        return _BlockType.headline1;
      case Constants.blockTypeHeadline2:
        return _BlockType.headline2;
      case Constants.blockTypeHeadline3:
        return _BlockType.headline3;
    }
    return _BlockType.text; // 匹配不到就用text
  }
  static String _convertBlockType(_BlockType type) {
    switch(type) {
      case _BlockType.title:
        return Constants.blockTypeTitleTag;
      case _BlockType.text:
        return Constants.blockTypeTextTag;
      case _BlockType.headline1:
        return Constants.blockTypeHeadline1;
      case _BlockType.headline2:
        return Constants.blockTypeHeadline2;
      case _BlockType.headline3:
        return Constants.blockTypeHeadline3;
    }
    // return Constants.blockTypeTextTag;
  }

  void _updateBlockListing(_BlockListing newListing) {
    if(newListing != _listing) {
      _listing = newListing;
      _storeBlock();
    }
  }
  static _BlockListing _parseBlockListing(String str) {
    switch(str) {
      case Constants.blockListTypeBulleted:
        return _BlockListing.bulleted;
      case Constants.blockListTypeChecked:
        return _BlockListing.checked;
      case Constants.blockListTypeCheckedConfirm:
        return _BlockListing.checkedConfirm;
      case Constants.blockListTypeNone:
        return _BlockListing.none;
    }
    return _BlockListing.none; // 匹配不到就用text
  }
  static String _convertBlockListing(_BlockListing listing) {
    switch(listing) {
      case _BlockListing.bulleted:
        return Constants.blockListTypeBulleted;
      case _BlockListing.checked:
        return Constants.blockListTypeChecked;
      case _BlockListing.checkedConfirm:
        return Constants.blockListTypeCheckedConfirm;
      case _BlockListing.none:
        return Constants.blockListTypeNone;
    }
  }

  _AffectedTextSpan _getAffectedTextSpans(List<TextDesc> all, int start, int end) {
    int offset = 0;
    var result = _AffectedTextSpan();
    for(int idx = 0; idx < all.length; idx++) {
      var t = all[idx];
      var len = t.text.length;
      if(offset + len <= start) { // 还未到开始设置的位置
        offset += len;
        continue;
      }
      if(offset >= end) { // 已经超出了要设置的位置
        break;
      }
      if(offset >= start && offset + len < end) { // 整个TextSpn都需要设置
        if(result.firstIndex == -1) {
          result.firstIndex = idx;
          result.lastIndex = idx;
        } else {
          result.lastIndex = idx;
        }
        offset += len;
        continue;
      }
      // 剩下的情况是需要设置一截
      if(offset < start && offset + len > start) {
        result.startAtFirstSpan = start - offset;
      }
      if(offset < end && offset + len > end) {
        result.endAtLastSpan = end - offset;
      }
      if(result.firstIndex == -1) {
        result.firstIndex = idx;
        result.lastIndex = idx;
      } else {
        result.lastIndex = idx;
      }
      offset += len;
    }

    if(result.endAtLastSpan == 0) { // 不可能是0,作为报警
      MyLogger.warn('affectedTextSpans.endAtLastSpan is 0!!!!!!!');
    }
    if(result.startAtFirstSpan == 0) { // 不可能是0，作为报警
      MyLogger.warn('affectedTextSpans.startAtFirstSpan is 0!!!!!!!');
    }
    return result;
  }
  void _splitTextDesc(List<TextDesc> spans, int spanIndex, int splitIndex) {
    var leftPart = spans[spanIndex].clone();
    var oldText = leftPart.text;
    leftPart.text = oldText.substring(0, splitIndex);
    spans[spanIndex].text = oldText.substring(splitIndex);
    spans.insert(spanIndex, leftPart);
  }
  // 0. _t至少包含一个元素
  // 1. 删除空TextDesc
  // 2. 合并相邻且风格相同的TextDesc
  void _compactTexts(List<TextDesc> _t) {
    var toRemove = <TextDesc>[];
    for(var item in _t) {
      if(item.text.isEmpty) {
        toRemove.add(item);
      }
    }
    for(var item in toRemove) {
      _t.remove(item);
    }
    if(_t.isEmpty) {
      _t.add(TextDesc());
    }
    int idx = 0;
    while(idx < _t.length - 1) {
      var current = _t[idx];
      var next = _t[idx + 1];
      if(current.sameStyleWith(next)) {
        current.text += next.text;
        _t.remove(next);
      } else {
        idx++;
      }
    }
  }
  void _tryToSendEvent() {
    if(isTitle()) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: Constants.timeoutOfInputIdle), () {
      Controller.instance.pluginManager.produceBlockContentChangedEvent(getBlockId(), getPlainText());
      _idleTimer = null;
    });
  }
}