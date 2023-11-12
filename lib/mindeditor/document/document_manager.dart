import 'dart:convert';

import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data.dart';
import 'package:mesh_note/mindeditor/document/doc_tree.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/inspired_seed.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:my_log/my_log.dart';
import '../../util/util.dart';
import '../setting/constants.dart';

class DocumentManager {
  bool _hasModified = false;
  final DbHelper _db;
  final Map<String, Document> _documents = {};
  String? currentDocId;
  List<DocData> _docTitles = [];
  String _currentVersion = '';
  int _currentVersionTimestamp = 0;

  DocumentManager({
    required DbHelper db,
  }): _db = db;

  Document? getCurrentDoc() {
    if(currentDocId == null) return null;
    return _documents[currentDocId];
  }

  List<DocData> getAllDocuments() {
    if(_docTitles.isNotEmpty) {
      return _docTitles;
    }
    var data = _db.getAllDocumentList();
    var (_version, _time) = _getCurrentVersionAndTimestamp();
    _currentVersion = _version;
    _currentVersionTimestamp = _time;
    _docTitles = data;
    return _docTitles;
  }

  /// Open document with docId to be current document
  void openDocument(String docId) {
    if(docId == currentDocId) return;

    if(currentDocId != null) {
      _documents[currentDocId]?.closeDocument();
    }
    // If modified, sync it before opening new document
    if(hasModified()) {
      Controller.instance.syncDocuments();
    }

    // If the document was not open, load it from db
    if(!_documents.containsKey(docId)) {
      var document = _getDocFromDb(docId);
      if(document != null) {
        _documents[docId] = document;
      } else { // Load failed
        return;
      }
    }
    currentDocId = docId;
  }

  String newDocument() {
    var title = Constants.newDocumentTitle;
    var now = Util.getTimeStamp();
    var id = _db.newDocument(title, now);
    _docTitles.add(DocData(docId: id, title: title, hash: '', timestamp: now));
    return id;
  }

  /// Generate version and returns version and required objects
  ///
  /// returns version and required objects
  (DocTreeVersion?, Map<String, String>) genAndSaveNewVersion() {
    if(!hasModified()) return (null, {});

    // generate and save version
    final now = Util.getTimeStamp();
    var version = _genVersionAndClearModified(now);
    _saveVersion(version, now);

    // generate required objects list
    var requiredObjects = _genRequiredObjects();
    return (version, requiredObjects);
  }

  void assembleVersionTree(String versionHash, DocTreeVersion version, List<String> parents, Map<String, String> requiredObjects) {
    for(var item in version.table) {
      _updateDoc(item, requiredObjects);
    }
    _currentVersion = versionHash;
    Controller.instance.refreshDocNavigator();
  }

  void _updateDoc(DocTreeNode node, Map<String, String> objects) {
    var docId = node.docId;
    DocData? found;
    for(var i in _docTitles) {
      if(i.docId == docId) {
        found = i;
        break;
      }
    }
    // If not found, insert it
    // If found and identical, ignore it
    // If found and not identical, update it, and restore doc content
    if(found != null && found.hash == node.docHash && found.timestamp == node.updatedAt) return;

    if(found == null) {
      found = DocData(docId: docId, title: node.title, hash: node.docHash, timestamp: node.updatedAt);
      _docTitles.add(found);
    } else {
      found..title = node.title
        ..hash = node.docHash
        ..timestamp = node.updatedAt;
    }
    // Restore doc list
    _db.insertOrUpdateDoc(docId, found.title, found.hash, found.timestamp);

    // Restore doc content
    var docContentStr = objects[found.hash]!;
    MyLogger.info('efantest: docContent=$docContentStr');
    _db.storeObject(found.hash, docContentStr);
    var docContent = DocContent.fromJson(jsonDecode(docContentStr));
    var root = BlockStructure(blockId: Constants.keyRootBlockId, children: []);
    for(var content in docContent.contents) {
      var blockId = content.blockId;
      var blockHash = content.blockHash;
      // Not support .children
      String blockStr = objects[blockHash]!;
      MyLogger.info('efantest: blockId=$blockId, blockHash=$blockHash, blockStr=$blockStr');
      _db.storeObject(blockHash, blockStr);
      _db.storeDocBlock(docId, blockId, blockStr, found.timestamp);

      var b = BlockStructure(blockId: blockId);
      root.children!.add(b);
    }
    // Restore docs
    _db.storeDocStructure(docId, jsonEncode(root), found.timestamp);

    // If document was loaded, update it
    var openingDocument = _documents[docId];
    if(openingDocument != null) {
      var newDocument = _getDocFromDb(docId);
      if(newDocument != null) {
        openingDocument.updateBlocks(newDocument);
      }
    }
    // If document is currently opening, refresh it
    if(currentDocId == docId) {
      MyLogger.info('efantest: refresh current document');
      var blockState = Controller.instance.getEditingBlockState();
      var currentBlockId = blockState?.widget.texts.getBlockId();
      var position = blockState?.widget.texts.getTextSelection()?.extentOffset;
      CallbackRegistry.refreshDoc(activeBlockId: currentBlockId, position: position?? 0);
    }
  }

  Future<InspiredSeed> getInspiredSeed() async {
    var ids = _db.getAllBlocks();
    _randomSort(ids);
    return InspiredSeed(ids: ids);
  }

  Future<ParagraphDesc?> getContentOfInspiredSeed(InspiredSeed seed, int index) async {
    if(index < 0 || seed.ids.length <= index) {
      return null;
    }
    final blockId = seed.ids[index];
    if(seed.cache.containsKey(blockId) && seed.cache[blockId] != null) {
      return seed.cache[blockId];
    }
    var data = _db.getRawBlockById(blockId);
    if(data != null) {
      var para = ParagraphDesc.fromStringList(data.id, data.type, data.data, data.listing, data.level);
      seed.cache[blockId] = para;
      return para;
    }
    return null;
  }

  void _randomSort(List<String> list) {
    final maxIndex = list.length;
    for(var idx = 0; idx < maxIndex; idx++) {
      var newIdx = Util.getRandom(maxIndex);
      var tmp = list[idx];
      list[idx] = list[newIdx];
      list[newIdx] = tmp;
    }
  }

  (String, int) _getCurrentVersionAndTimestamp() {
    var ver = _db.getFlag(Constants.flagNameCurrentVersion);
    var t = _db.getFlag(Constants.flagNameCurrentVersionTimestamp);
    int? timestamp = int.tryParse(t, radix: 10);
    return (ver, timestamp?? 0);
  }

  void _saveVersion(DocTreeVersion version, int now) {
    final hash = version.getHash();
    final jsonStr = jsonEncode(version);
    // Save version object, version tree, current_version flag, and current_version_timestamp flag
    _db.storeObject(hash, jsonStr);
    _db.storeVersion(hash, _currentVersion, now);
    _db.setFlag(Constants.flagNameCurrentVersion, hash);
    _db.setFlag(Constants.flagNameCurrentVersionTimestamp, now.toString());

    _currentVersionTimestamp = now;
    _currentVersion = hash;
  }

  void updateDocTitle(String docId, String title, int timestamp) {
    for(var node in _docTitles) {
      if(node.docId == docId) {
        node.title = title;
        node.timestamp = timestamp;
      }
    }
  }
  void setModified() {
    _hasModified = true;
  }

  bool hasModified() {
    return _hasModified;
  }

  DocData? _getDocTreeNode(String docId) {
    for(var node in _docTitles) {
      if(node.docId == docId) {
        return node;
      }
    }
    return null;
  }

  DocTreeVersion _genVersionAndClearModified(int now) {
    List<Document> modifiedDocuments = _findModifiedDocuments();
    Map<String, String> newHashes = _genAndSaveDocuments(modifiedDocuments);
    _updateDocumentHashes(newHashes, now);
    var docTable = _genDocTreeNodeList(_docTitles);
    var version = DocTreeVersion(table: docTable, timestamp: now, parentsHash: [_currentVersion]);
    _clearModified(modifiedDocuments);
    return version;
  }

  Map<String, String> _genRequiredObjects() {
    Map<String, String> result = {};

    for(var item in _docTitles) {
      var docId = item.docId;
      var docHash = item.hash;
      var docStr = _db.getObject(docHash);
      MyLogger.info('_genRequiredObjects: docId=$docId, docHash=$docHash, docStr=$docStr');
      result[docHash] = docStr;

      var doc = _documents[docId];
      doc ??= _getDocFromDb(docId);
      if(doc == null) continue;

      _documents[docId] = doc;
      var map = _documents[docId]?.getRequiredBlocks();
      if(map != null) {
        result.addAll(map);
      }
    }

    return result;
  }

  static List<DocTreeNode> _genDocTreeNodeList(List<DocData> list) {
    List<DocTreeNode> result = [];
    for(var item in list) {
      var node = DocTreeNode(docId: item.docId, docHash: item.hash, title: item.title, updatedAt: item.timestamp);
      result.add(node);
    }
    return result;
  }

  Document? _getDocFromDb(String docId) {
    var docNode = _getDocTreeNode(docId);
    if(docNode == null) return null;

    return Document.loadByNode(docNode, this);
  }

  List<Document> _findModifiedDocuments() {
    // TODO Load all documents whose timestamp greater than current_version_timestamp
    List<Document> result = [];
    for(var e in _documents.entries) {
      final doc = e.value;
      if(doc.getModified()) {
        result.add(doc);
      }
    }
    MyLogger.debug('_findModifiedDocuments: document modified list: $result');
    return result;
  }

  Map<String, String> _genAndSaveDocuments(List<Document> documents) {
    Map<String, String> result = {};
    for(var doc in documents) {
      String hash = doc.genAndSaveObject();
      result[doc.id] = hash;
    }
    return result;
  }
  void _updateDocumentHashes(Map<String, String> newHashes, int now) {
    for(var docData in _docTitles) {
      final docId = docData.docId;
      var newHash = newHashes[docId];
      if(newHash != null) {
        docData.hash = newHash;
        _db.storeDocHash(docId, newHash, now);
      }
    }
  }

  void _clearModified(List<Document> documents) {
    for(var doc in documents) {
      doc.clearModified();
    }
    _hasModified = false;
  }
}