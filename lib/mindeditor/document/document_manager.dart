import 'dart:convert';

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
  Document? document;
  String? currentDocId;
  List<DocData> _docTitles = [];
  String _currentVersion = '';
  int _currentVersionTimestamp = 0;

  DocumentManager({
    required DbHelper db,
  }): _db = db;

  Document? getCurrentDoc() {
    return document;
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
  
  void openDocument(String docId) {
    document?.closeDocument();
    // If modified, sync it before opening new document
    if(hasModified()) {
      Controller.instance.syncDocuments();
    }
    currentDocId = docId;
    document = _getDocFromDb();
  }

  String newDocument() {
    var title = Constants.newDocumentTitle;
    var now = Util.getTimeStamp();
    var id = _db.newDocument(title, now);
    _docTitles.add(DocData(docId: id, title: title, hash: '', timestamp: now));
    return id;
  }

  DocTreeVersion? genAndSaveNewVersion() {
    if(!hasModified()) return null;

    List<Document> modifiedDocuments = _findModifiedDocuments();
    Map<String, String> newHashes = _genAndSaveDocuments(modifiedDocuments);
    final now = Util.getTimeStamp();
    _updateDocumentHashes(newHashes, now);
    var docTable = _genDocTreeNodeList(_docTitles);
    var version = DocTreeVersion(table: docTable, timestamp: now, parentsHash: [_currentVersion]);
    final versionHash = _saveVersion(version, now);
    _currentVersionTimestamp = now;
    _currentVersion = versionHash;

    _clearModified(modifiedDocuments);
    return version;
  }

  void assembleVersionTree(String versionHash, DocTreeVersion version, List<String> parents, Map<String, String> requiredObjects) {
    for(var item in version.table) {
      _updateDoc(item, requiredObjects);
    }
    _currentVersion = versionHash;
    Controller.instance.refreshDocNavigator();
  }

  void _updateDoc(DocTreeNode node, Map<String, String> objects) {
    DocData? find;
    for(var i in _docTitles) {
      if(i.docId == node.docId) {
        find = i;
        break;
      }
    }
    // If not found, insert it
    // If found and identical, ignore it
    // If found and not identical, update it, and restore doc content
    if(find != null && find.hash == node.docHash && find.timestamp == node.updatedAt) return;

    if(find == null) {
      find = DocData(docId: node.docId, title: node.title, hash: node.docHash, timestamp: node.updatedAt);
      _docTitles.add(find);
    } else {
      find..title = node.title
          ..hash = node.docHash
          ..timestamp = node.updatedAt;
    }
    // Restore doc list
    _db.insertOrUpdateDoc(find.docId, find.title, find.hash, find.timestamp);

    // Restore doc content
    var docContentStr = objects[find.hash]!;
    MyLogger.info('efantest: docContent=$docContentStr');
    _db.storeObject(find.docId, docContentStr);
    var docContent = DocContent.fromJson(jsonDecode(docContentStr));
    var root = BlockStructure(blockId: Constants.keyRootBlockId, children: []);
    for(var content in docContent.contents) {
      var blockId = content.blockId;
      var blockHash = content.blockHash;
      // Not support .children
      String blockStr = objects[blockHash]!;
      MyLogger.info('efantest: blockId=$blockId, blockHash=$blockHash, blockStr=$blockStr');
      _db.storeObject(blockHash, blockStr);
      _db.storeDocBlock(find.docId, blockId, blockStr, find.timestamp);

      var b = BlockStructure(blockId: blockId);
      root.children!.add(b);
    }
    // Restore docs
    _db.storeDocStructure(find.docId, jsonEncode(root), find.timestamp);
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

  String _saveVersion(DocTreeVersion version, int now) {
    final hash = version.getHash();
    final jsonStr = jsonEncode(version);
    // Save version object, version tree, current_version flag, and current_version_timestamp flag
    _db.storeObject(hash, jsonStr);
    _db.storeVersion(hash, _currentVersion, now);
    _db.setFlag(Constants.flagNameCurrentVersion, hash);
    _db.setFlag(Constants.flagNameCurrentVersionTimestamp, now.toString());
    return hash;
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

  static List<DocTreeNode> _genDocTreeNodeList(List<DocData> list) {
    List<DocTreeNode> result = [];
    for(var item in list) {
      var node = DocTreeNode(docId: item.docId, docHash: item.hash, title: item.title, updatedAt: item.timestamp);
      result.add(node);
    }
    return result;
  }

  Document? _getDocFromDb() {
    var docNode = _getDocTreeNode(currentDocId!);
    if(docNode == null) return null;

    return Document.loadByNode(docNode, this);
  }

  List<Document> _findModifiedDocuments() {
    // TODO Load all documents whose timestamp greater than current_version_timestamp
    List<DocData> result = [];
    for(var d in _docTitles) {
      if(d.timestamp > _currentVersionTimestamp) {
        result.add(d);
      }
    }
    return [document!];
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