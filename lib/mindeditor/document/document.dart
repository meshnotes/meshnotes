import 'dart:convert';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';
import '../view/mind_edit_block.dart';
import '../../util/util.dart';
import '../controller/controller.dart';
import '../setting/constants.dart';
import 'dal/db_helper.dart';
import 'dal/doc_data_model.dart';
import 'paragraph_desc.dart';
import 'document_manager.dart';

class Document {
  List<ParagraphDesc> paragraphs;
  Map<String, ParagraphDesc> _mapOfParagraphs = {};
  String id;
  bool _hasModified = false;
  int _lastUpdate;
  String? _editingBlockId;
  DocumentManager? parent;
  final DbHelper? _db;
  final controller = Controller();

  Document({
    required this.id,
    this.parent,
    required List<ParagraphDesc> paras,
    required int time,
    DbHelper? db,
  }): paragraphs = paras, _lastUpdate = time, _db = db {
    ParagraphDesc? previous;
    for(var p in paragraphs) {
      p.setDocument(this);
      p.setPrevious(previous);
      previous?.setNext(p);
      previous = p;
      _mapOfParagraphs[p.getBlockId()] = p;
    }
  }

  factory Document.loadByNode(DbHelper db, DocDataModel docNode, DocumentManager parent) {
    List<ParagraphDesc> paragraphs = [];
    // Load content
    var blocks = _loadBlocks(db, docNode.docId);
    paragraphs.addAll(blocks);

    Document doc = Document(
      id: docNode.docId,
      paras: paragraphs,
      parent: parent,
      time: docNode.timestamp,
      db: db,
    );
    // If the document has no content(or only has a title), add an title line
    if(blocks.isEmpty) {
      ParagraphDesc title = ParagraphDesc.fromTitle(docNode.title);
      paragraphs.add(title);
      doc.insertEmptyLineAfterTitle();
      doc.setModified();
    } else if(blocks.length == 1 && blocks[0].isTitle()) {
      doc.insertEmptyLineAfterTitle();
      doc.setModified();
    }
    for(var block in blocks) {
      final blockUpdatedTime = block.getLastUpdated();
      if(blockUpdatedTime > doc._lastUpdate) {
        doc.setModified();
        doc._lastUpdate = blockUpdatedTime;
        docNode.timestamp = blockUpdatedTime;
      }
    }
    return doc;
  }

  factory Document.createDocument(DbHelper db, String docId, String title, String content, DocumentManager parent, int now) {
    final titlePara = ParagraphDesc.fromTitle(title);
    List<ParagraphDesc> paragraphs = [titlePara];
    for(var line in content.split('\n')) {
      var para = ParagraphDesc.fromRawString(line);
      paragraphs.add(para);
    }
    Document doc = Document(
      id: docId,
      paras: paragraphs,
      parent: parent,
      time: now,
      db: db,
    );
    for(var p in paragraphs) {
      p.flushDb(); // Here will set modified
    }
    doc._flushDocStructure();
    return doc;
  }

  void updateBlocks(Document newDoc) {
    var _oldMap = _mapOfParagraphs;
    paragraphs = newDoc.paragraphs;
    _mapOfParagraphs = newDoc._mapOfParagraphs;
    id = newDoc.id;
    _hasModified = newDoc._hasModified;
    _lastUpdate = newDoc._lastUpdate;

    // Restore saved state and position
    //TODO Should be optimized
    for(var entry in _mapOfParagraphs.entries) {
      var blockId = entry.key;
      var block = entry.value;
      block.setDocument(this);
      var oldBlock = _oldMap[blockId];
      var oldEditState = oldBlock?.getEditState();
      if(oldEditState != null) {
        block.setEditState(oldEditState);
      }

      var oldPosition = oldBlock?.getTextSelection();
      if(oldPosition != null) {
        bool hasCursor = oldBlock!.hasCursor();
        block.setTextSelection(oldPosition, isEditing: hasCursor);
      }
    }
  }

  DbHelper? getDb() => _db;
  ParagraphDesc getTitle() {
    return paragraphs[0];
  }
  List<String> getTitlePath() {
    return <String>[getTitle().getPlainText()];
  }

  bool hasContent() {
    for(var para in paragraphs) {
      if(para.isTitle()) continue;
      if(para.hasContent()) {
        return true;
      }
    }
    return false;
  }
  ParagraphDesc? getParagraph(String _id) {
    return _mapOfParagraphs[_id];
  }

  ParagraphDesc insertEmptyLineAfterTitle() {
    String id = Constants.keyTitleId;
    ParagraphDesc para = ParagraphDesc();
    insertNewParagraphAfterId(id, para);
    return para;
  }
  void insertNewParagraphAfterId(String _id, ParagraphDesc newItem) {
    int idx;
    for(idx = 0; idx < paragraphs.length; idx++) {
      if(paragraphs[idx].getBlockId() == _id) {
        break;
      }
    }
    newItem.setDocument(this);
    paragraphs[idx].setNext(newItem);
    paragraphs[idx].flushDb();
    newItem.setPrevious(paragraphs[idx]);
    if(idx < paragraphs.length - 1) {
      paragraphs[idx + 1].setPrevious(newItem);
      newItem.setNext(paragraphs[idx + 1]);
    }
    newItem.flushDb();
    paragraphs.insert(idx + 1, newItem);
    _mapOfParagraphs[newItem.getBlockId()] = newItem;
    _flushDocStructure();
    return;
  }
  //TODO merge with the previous function
  void insertNewParagraphsAfterId(String _id, List<ParagraphDesc> newItems) {
    int idx;
    for(idx = 0; idx < paragraphs.length; idx++) {
      if(paragraphs[idx].getBlockId() == _id) {
        break;
      }
    }
    //TODO could be optimized here, reduce IO
    for(var item in newItems) {
      item.setDocument(this);
      paragraphs[idx].setNext(item);
      paragraphs[idx].flushDb();
      item.setPrevious(paragraphs[idx]);
      if(idx < paragraphs.length - 1) {
        paragraphs[idx + 1].setPrevious(item);
        item.setNext(paragraphs[idx + 1]);
      }
      item.flushDb();
      paragraphs.insert(idx + 1, item);
      _mapOfParagraphs[item.getBlockId()] = item;
      idx++;
    }
    _flushDocStructure();
  }

  void removeParagraph(String _id) {
    var para = getParagraph(_id);
    if(para == null) {
      return;
    }
    var previous = para.getPrevious();
    var next = para.getNext();
    previous?.setNext(next);
    next?.setPrevious(previous);
    para.drop();
    paragraphs.remove(para);
    _mapOfParagraphs.remove(_id);
    _flushDocStructure();
  }

  void updateTitle(String title) {
    var now = Util.getTimeStamp();
    // _db.storeDocTitle(id, title, now);
    parent?.updateDocTitle(id, title, now);

    _lastUpdate = now;
    setModified();

    controller.refreshDocNavigator();
  }

  void clearTextSelection() {
    controller.selectionController.clearSelection();
    for(var p in paragraphs) {
      p.clearTextSelection();
    }
  }
  void clearEditingBlock() {
    _editingBlockId = null;
    controller.triggerBlockFormatChanged(null);
    controller.triggerSelectionChanged(null);
  }
  void setEditingBlockId(String _id) {
    _editingBlockId = _id;
    // TODO Here may need to trigger format_changed_event even if state is null
    var state = getBlockState(_id);
    if(state == null) {
      return;
    }
    var para = getParagraph(_id);
    controller.triggerBlockFormatChanged(para);
  }
  String? getEditingBlockId() {
    return _editingBlockId;
  }
  void setBlockStateToTreeNode(String id, MindEditBlockState _state) {
    var para = getParagraph(id);
    para?.setEditState(_state);
  }
  MindEditBlockState? getBlockState(String _id) {
    return getParagraph(_id)?.getEditState();
  }
  MindEditBlockState? getEditingBlockState() {
    var editingBlockId = getEditingBlockId();
    if(editingBlockId == null) {
      return null;
    }
    return getBlockState(editingBlockId);
  }
  ParagraphDesc? getEditingBlockDesc() {
    String? editingBlockId = getEditingBlockId();
    if(editingBlockId == null) {
      return null;
    }
    return getParagraph(editingBlockId);
  }

  String? getPreviousBlockId(String _id) {
    var node = getParagraph(_id);
    if(node == null) {
      return null;
    }
    var previousNode = node.getPrevious();
    return previousNode?.getBlockId();
  }
  String? getNextBlockId(String _id) {
    var node = getParagraph(_id);
    if(node == null) {
      return null;
    }
    var nextNode = node.getNext();
    return nextNode?.getBlockId();
  }

  String genAndSaveObject() {
    // if(!_hasModified) return hash;
    // Store ContentBlock objects and DocContent object
    int now = Util.getTimeStamp();
    for(var p in paragraphs) {
      // if(p.getLastUpdated() > _lastUpdate) {
      //   p.storeObject();
      // }
      //TODO should optimize here, only store objects that is modified
      p.storeObject(now);
    }
    var docContent = _generateDocContent();
    String docHash = docContent.getHash();
    _db?.storeObject(docHash, jsonEncode(docContent), now, Constants.createdFromLocal, ModelConstants.statusAvailable);
    return docHash;
  }

  Map<String, String> getRequiredBlocks() {
    Map<String, String> result = {};
    //TODO should be optimize here to avoid duplicated call to _generateDocContent
    var docContent = _generateDocContent();
    for(var b in docContent.contents) {
      var blockHash = b.blockHash;
      var object = _db?.getObject(blockHash);
      if(object == null) continue;
      result[blockHash] = object.data;
    }
    return result;
  }

  void setModified() {
    _hasModified = true;
    parent?.setModified();
  }
  bool getModified() {
    return _hasModified;
  }
  void clearModified() {
    _hasModified = false;
  }
  int getLastUpdateTime() {
    return _lastUpdate;
  }

  void closeDocument() {
    for(var p in paragraphs) {
      p.close();
    }
  }

  static List<ParagraphDesc> _loadBlocks(DbHelper db, String docId) {
    var data = db.getDoc(docId);
    if(data == null) {
      return [];
    }
    DocContent docContent = DocContent.fromJson(jsonDecode(data.docContent));

    List<ParagraphDesc> result = [];
    var blocks = db.getBlockMapOfDoc(docId);
    for(var b in docContent.contents) {
      final blockId = b.blockId;
      var blockData = blocks[blockId];
      if(blockData == null) {
        MyLogger.warn('_loadBlocks: could not find block(id=$blockId) in block map of document(id=$docId)');
        continue;
      }
      MyLogger.debug('_loadBlocks: block=${blockData.blockId}}, extra=${blockData.blockExtra}');
      var p = ParagraphDesc.buildFromJson(id: blockData.blockId, jsonStr: blockData.blockData, time: blockData.updatedAt, extra: blockData.blockExtra);
      result.add(p);
    }
    return result;
  }

  void _flushDocStructure() {
    final now = Util.getTimeStamp();
    var docContent = _generateDocContent();
    final jsonStr = jsonEncode(docContent);
    _db?.updateDocContent(id, jsonStr, now);
    _lastUpdate = now;
  }

  DocContent _generateDocContent() {
    List<DocContentItem> list = [];
    for(var p in paragraphs) {
      final block = p.getBlockContent();
      var hash = block.getHash();
      var item = DocContentItem(
        blockId: p.getBlockId(),
        blockHash: hash,
      );
      list.add(item);
    }
    return DocContent(contents: list);
  }
}