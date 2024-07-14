import 'dart:convert';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/collaborate/conflict_manager.dart';
import 'package:mesh_note/mindeditor/document/collaborate/merge_manager.dart';
import 'package:mesh_note/mindeditor/document/collaborate/version_manager.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data_model.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/inspired_seed.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:mesh_note/mindeditor/document/text_desc.dart';
import 'package:my_log/my_log.dart';
import '../../net/version_chain_api.dart';
import '../../util/util.dart';
import '../setting/constants.dart';
import 'collaborate/diff_manager.dart';

class DocumentManager {
  bool _hasModified = false;
  final DbHelper _db;
  final Map<String, Document> _documents = {};
  VersionManager vm = VersionManager();
  DiffManager dm = DiffManager();
  String? currentDocId;
  List<DocDataModel> _docTitles = [];
  String _currentVersion = '';
  int _currentVersionTimestamp = 0;
  bool _syncing = false;

  DocumentManager({
    required DbHelper db,
  }): _db = db {
    Controller.instance.evenTasksManager.addAfterInitTask(() {
      Future(() {
        checkConsistency();
      });
    });
  }

  Document? getCurrentDoc() {
    if(currentDocId == null) return null;
    return _documents[currentDocId];
  }

  List<DocDataModel> getAllDocuments() {
    if(_docTitles.isNotEmpty) {
      return _docTitles;
    }
    var data = _getAllDocumentAndTitles();
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
      Controller.instance.sendVersionTree();
    }

    // If the document was not open, load it from db
    if(!_documents.containsKey(docId)) {
      var document = _getDocFromDb(docId);
      if(document != null) {
        _documents[docId] = document;
      } else { // Load failed
        //TODO Show error message here
        return;
      }
    }
    currentDocId = docId;
  }

  String newDocument() {
    var title = Constants.newDocumentTitle;
    var now = Util.getTimeStamp();
    var docId = _db.newDocument(now);

    const blockId = Constants.keyTitleId;
    var block = _genDefaultTitleBlock(title);
    _db.storeDocBlock(docId, blockId, jsonEncode(block), now);
    var docContent = _genDocContentWithTitle(docId, blockId, block);
    _db.storeDocContent(docId, jsonEncode(docContent), now);
    _docTitles.add(DocDataModel(docId: docId, title: title, hash: '', timestamp: now));
    return docId;
  }

  (List<VersionDataModel>, int) genAndSaveNewVersionTree() {
    if(!hasModified()) return ([], 0);
    final now = Util.getTimeStamp();
    var version = _genVersionAndClearModified(now);
    _saveVersion(version, _currentVersion, now);
    return (_getVersionMap(), now);
  }

  /// Generate new version tree by merging local and remote version tree.
  /// If missing any version, require it from remote nodes.
  /// If no missing version, merge versions.
  /// Once assembling, set syncing status to stop other nodes sending version_tree concurrently.
  void assembleVersionTree(List<VersionNode> versionDag) {
    setSyncing();
    _storeVersions(versionDag);
    // Map<String, DagNode> remoteDagMap = _buildRemoteVersionTreeMap(versionDag);
    Map<String, DagNode> localDagMap = _genVersionMapFromDb();
    // Map<String, DagNode> newMap = _mergeLocalAndRemoteMap(localDagMap, remoteDagMap);
    _tryToMergeVersionTree(localDagMap);
  }
  void _storeVersions(List<VersionNode> versionDag) {
    for(var node in versionDag) {
      String versionHash = node.versionHash;
      String parents = _buildParents(node.parents);
      int timestamp = node.createdAt;
      var localVersion = _db.getVersionData(versionHash);
      if(localVersion == null) { // If the version is not exists, create one and set it as from_peer/unavailable
        _db.storeVersion(versionHash, parents, timestamp, Constants.createdFromPeer, Constants.statusUnavailable);
      }
    }
  }

  List<SendVersions> assembleRequireVersions(List<String> requiredVersions) {
    List<SendVersions> result = [];
    for(var versionHash in requiredVersions) {
      final versionData = _db.getVersionData(versionHash);
      if(versionData == null) {
        MyLogger.warn('assembleRequireVersions: version(hash=$versionHash) not found!!!');
        continue;
      }
      final object = _db.getObject(versionHash);
      if(object == null) {
        MyLogger.warn('assembleRequireVersions: object(hash=$versionHash) not found!!!, versionData=$versionData');
        continue;
      }
      final json = object.data;
      final versionContent = VersionContent.fromJson(jsonDecode(json));
      Map<String, RelatedObject> requiredObjects = _genRequiredObjects(versionContent);

      var node = SendVersions(
          versionHash: versionHash,
          versionContent: json,
          createdAt: versionData.createdAt,
          parents: versionData.parents,
          requiredObjects: requiredObjects
      );
      result.add(node);
    }
    return result;
  }

  /// Assemble resources, and try to merge if all required resources are ready
  ///
  /// 1. Store all resources into objects
  /// 2. Load version tree
  /// 3. Try to merge entire version tree
  void assembleResources(List<UnsignedResource> resources) {
    for(var res in resources) {
      String key = res.key;
      int timestamp = res.timestamp;
      String content = res.data;
      if(_db.getObject(key) == null) {
        _db.storeObject(key, content, timestamp, Constants.createdFromPeer, Constants.statusAvailable);
      }
    }
    var _versionMap = _genVersionMapFromDb();
    _tryToMergeVersionTree(_versionMap);
  }

  bool isSyncing() => _syncing;
  void setSyncing() {
    _syncing = true;
  }
  void clearSyncing() {
    _syncing = false;
  }

  void checkConsistency() {
    _checkVersionIntegrity();
    _checkObjectsIntegrity();
  }

  /// Try to merge entire version tree, called after receiving new version_tree or receiving missing versions.
  /// 1. If some versions are still missing, send require_versions request to other nodes
  /// 2. If all versions are ready, merge versions
  void _tryToMergeVersionTree(Map<String, DagNode> newMap) {
    List<String> missingVersions = _findMissingVersions(newMap);
    if(missingVersions.isNotEmpty) {
      Controller.instance.sendRequireVersions(missingVersions);
    } else {
      MyLogger.info('_tryToMergeVersionTree: ready to merge');
      _mergeVersions(newMap);
    }
  }
  /// Merge all leaf nodes of versions
  /// 1. Find all leaf nodes(versions that has no child) except current version
  /// 2. Merge current version and each leaf versions two by two in one time
  ///   2.1. Find common ancestor of current version and leaf version
  ///   2.2. Merge current version and leaf version based on common ancestor, and we get a new merged version
  ///   2.3 Update current version to that newly merged version
  /// 5. Refresh view
  void _mergeVersions(Map<String, DagNode> map) {
    var leafNodes = _findLeafNodesInDag(map);
    MyLogger.info('_mergeVersions: find leaf nodes: $leafNodes');
    leafNodes.remove(_currentVersion);
    for(var leafHash in leafNodes) {
      String commonVersionHash = _getCommonAncestor(_currentVersion, leafHash, map);
      MyLogger.info('_mergeVersions: Try to merge version($_currentVersion) and version($leafHash) by common version($commonVersionHash)');
      _mergeCurrentAndSave(leafHash, commonVersionHash);
    }
    Controller.instance.refreshDocNavigator();
    clearSyncing();
  }
  /// Find all nodes that is not parent of any other node
  Set<String> _findLeafNodesInDag(Map<String, DagNode> map) {
    Set<String> result = map.keys.toSet();
    for(var e in map.values) {
      var parents = e.parents;
      for(var p in parents) {
        result.remove(p.versionHash);
      }
    }
    return result;
  }
  void _mergeCurrentAndSave(String targetVersion, String commonVersion) {
    // Make sure to get the fix order in every machine
    String v1 = _currentVersion, v2 = targetVersion;
    if(v1.compareTo(v2) > 0) {
      v2 = _currentVersion;
      v1 = targetVersion;
    }
    var contentVersion = _merge(v1, v2, commonVersion);
    if(contentVersion == null) {
      return;
    }
    var newVersionHash = contentVersion.getHash();
    if(newVersionHash == _currentVersion) {
      MyLogger.info('_mergeCurrentAndSave: merge result is current version($_currentVersion), do nothing');
      return;
    }

    for(var doc in contentVersion.table) {
      _updateDoc(doc, {});
    }

    bool fastForward = newVersionHash == _currentVersion || newVersionHash == targetVersion;
    var now = fastForward? contentVersion.timestamp: Util.getTimeStamp();
    var parents = fastForward? '': '$_currentVersion,$targetVersion'; // Ignore parents if fast_forward
    _saveVersion(contentVersion, parents, now, fastForward: fastForward);
  }
  void _updateDoc(VersionContentItem node, Map<String, String> objects) {
    var docId = node.docId;
    DocDataModel? found;
    for(var item in _docTitles) {
      if(item.docId == docId) {
        found = item;
        break;
      }
    }
    /// 1. If found and identical, ignore it
    /// 2. If not found, insert it
    /// 3. If found and not identical, update it, and restore doc content
    if(found != null && found.hash == node.docHash && found.timestamp == node.updatedAt) return;

    if(found == null) {
      found = DocDataModel(docId: docId, title: '', hash: node.docHash, timestamp: node.updatedAt);
      _docTitles.add(found);
    } else {
      found..hash = node.docHash
        ..timestamp = node.updatedAt;
    }
    // Restore doc list
    _db.insertOrUpdateDoc(docId, found.hash, found.timestamp);

    // Store doc content into objects
    // var docContentStr = objects[found.hash]!;
    var docObject = _db.getObject(found.hash);
    var docContentStr = docObject!.data;
    MyLogger.info('_updateDoc: docContent=$docContentStr');
    var docContent = DocContent.fromJson(jsonDecode(docContentStr));

    // Store blocks into objects
    for(var content in docContent.contents) {
      var blockId = content.blockId;
      var blockHash = content.blockHash;
      // Not support .children
      // String blockStr = objects[blockHash]!;
      var blockObject = _db.getObject(blockHash);
      var blockStr = blockObject!.data;
      MyLogger.info('_updateDoc: docId=$docId, blockId=$blockId, blockHash=$blockHash, blockStr=$blockStr');
      if(blockId == Constants.keyTitleId) {
        BlockContent blockContent = BlockContent.fromJson(jsonDecode(blockStr));
        var title = '';
        for(var t in blockContent.text) {
          title += t.text;
        }
        found.title = title;
      }
      // _db.storeObject(blockHash, blockStr);
      _db.storeDocBlock(docId, blockId, blockStr, found.timestamp);
    }
    // Update doc content
    _db.storeDocContent(docId, docContentStr, found.timestamp);

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
      MyLogger.info('_updateDoc: refresh current document');
      var blockState = Controller.instance.getEditingBlockState();
      var currentBlockId = blockState?.getBlockId();
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
    final (docId, blockId) = seed.ids[index];
    if(seed.cache.containsKey(blockId) && seed.cache[blockId] != null) {
      return seed.cache[blockId];
    }
    var data = _db.getRawBlockById(docId, blockId);
    if(data != null) {
      var para = ParagraphDesc.buildFromJson(id: data.blockId, jsonStr: data.blockData, time: data.updatedAt, extra: data.blockExtra);
      seed.cache[blockId] = para;
      return para;
    }
    return null;
  }

  (String, int) _getCurrentVersionAndTimestamp() {
    var ver = _db.getFlag(Constants.flagNameCurrentVersion);
    var t = _db.getFlag(Constants.flagNameCurrentVersionTimestamp);
    int? timestamp = int.tryParse(t, radix: 10);
    return (ver, timestamp?? 0);
  }

  void _saveVersion(VersionContent version, String parents, int now, {bool fastForward = false}) {
    final hash = version.getHash();
    if(fastForward) {
      MyLogger.info('Fast forward to version($hash)');
      _db.setFlag(Constants.flagNameCurrentVersion, hash);
      _currentVersionTimestamp = now;
      _currentVersion = hash;
    } else {
      final jsonStr = jsonEncode(version);
      // Save version object, version tree, current_version flag, and current_version_timestamp flag
      _db.storeObject(hash, jsonStr, now, Constants.createdFromLocal, Constants.statusAvailable);
      _db.storeVersion(hash, parents, now, Constants.createdFromLocal, Constants.statusAvailable);
      _db.setFlag(Constants.flagNameCurrentVersion, hash);
      _db.setFlag(Constants.flagNameCurrentVersionTimestamp, now.toString());

      MyLogger.info('Save new version($hash), parent=$parents');
      _currentVersionTimestamp = now;
      _currentVersion = hash;
    }
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

  DocDataModel? _getDocTreeNode(String docId) {
    for(var node in _docTitles) {
      if(node.docId == docId) {
        return node;
      }
    }
    return null;
  }

  VersionContent _genVersionAndClearModified(int now) {
    List<Document> modifiedDocuments = _findModifiedDocuments();
    Map<String, String> newHashes = _genAndSaveDocuments(modifiedDocuments);
    _updateDocumentHashes(newHashes, now);
    var docTable = _genDocTreeNodeList(_docTitles);
    var version = VersionContent(table: docTable, timestamp: now, parentsHash: [_currentVersion]);
    _clearModified(modifiedDocuments);
    return version;
  }

  Map<String, RelatedObject> _genRequiredObjects(VersionContent versionContent) {
    Map<String, RelatedObject> result = {};

    for(var item in versionContent.table) {
      var docId = item.docId;
      var docHash = item.docHash;
      var docObject = _db.getObject(docHash);
      if(docObject == null) continue;
      MyLogger.info('_genRequiredObjects: docId=$docId, docHash=$docHash, docStr=$docObject');
      result[docHash] = RelatedObject(objHash: docHash, objContent: docObject.data, createdAt: docObject.timestamp);

      //TODO should load history document by docHash
      var docContent = DocContent.fromJson(jsonDecode(docObject.data));
      for(var block in docContent.contents) {
        _recursiveAddToMap(block, result);
      }
    }
    return result;
  }
  void _recursiveAddToMap(DocContentItem block, Map<String, RelatedObject> map) {
    var blockHash = block.blockHash;
    if(!map.containsKey(blockHash)) {
      var blockObject = _db.getObject(blockHash);
      if(blockObject == null) return;
      map[blockHash] = RelatedObject(objHash: blockHash, objContent: blockObject.data, createdAt: blockObject.timestamp);
    }
    for(var item in block.children) {
      _recursiveAddToMap(item, map);
    }
  }

  static List<VersionContentItem> _genDocTreeNodeList(List<DocDataModel> list) {
    List<VersionContentItem> result = [];
    for(var item in list) {
      var node = VersionContentItem(docId: item.docId, docHash: item.hash, updatedAt: item.timestamp);
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

  String _getCommonAncestor(String version1, String version2, Map<String, DagNode> _versionMap) {
    if(_versionMap.isEmpty) {
      _versionMap = _genVersionMapFromDb();
    }
    var verNode1 = _versionMap[version1];
    var verNode2 = _versionMap[version2];
    if(verNode1 == null || verNode2 == null) {
      return '';
    }
    DagNode? resultNode = vm.findNearestCommonAncestor([verNode1, verNode2], _versionMap);
    return resultNode?.versionHash??'';
  }
  Map<String, DagNode> _genVersionMapFromDb() {
    var _allVersions = _db.getAllVersions();

    // Generate version map
    Map<String, DagNode> _map = {};
    for(var item in _allVersions) {
      final versionHash = item.versionHash;
      final timestamp = item.createdAt;
      var node = DagNode(versionHash: versionHash, createdAt: timestamp, parents: []);
      _map[versionHash] = node;
    }
    // Generate version parents pointer
    for(var item in _allVersions) {
      final versionHash = item.versionHash;
      final parents = _splitParents(item.parents);
      final currentNode = _map[versionHash]!;
      for(var p in parents) {
        var parentNode = _map[p];
        if(parentNode == null) continue;
        currentNode.parents.add(parentNode);
      }
    }
    return _map;
  }
  // Map<String, DagNode> _buildRemoteVersionTreeMap(List<VersionNode> dagList) {
  //   Map<String, DagNode> result = {};
  //   for(var item in dagList) {
  //     final versionHash = item.versionHash;
  //     final timestamp = item.createdAt;
  //     var node = DagNode(versionHash: versionHash, createdAt: timestamp, parents: []);
  //     result[versionHash] = node;
  //   }
  //   for(var item in dagList) {
  //     final versionHash = item.versionHash;
  //     final parents = item.parents;
  //     final currentNode = result[versionHash]!;
  //     for(var p in parents) {
  //       var parentNode = result[p];
  //       if(parentNode == null) continue;
  //       currentNode.parents.add(parentNode);
  //     }
  //   }
  //   return result;
  // }
  String _buildParents(List<String> parents) {
    String result = '';
    for(var p in parents) {
      if(result.isEmpty) {
        result = p;
      } else {
        result += ',' + p;
      }
    }
    return result;
  }
  List<String> _splitParents(String parents) {
    List<String> _sp = parents.split(',');
    return _sp;
  }
  // Map<String, DagNode> _mergeLocalAndRemoteMap(Map<String, DagNode> localMap, Map<String, DagNode> remoteMap) {
  //   for(var e in remoteMap.entries) {
  //     var key = e.key;
  //     var remoteNode = e.value;
  //     if(localMap.containsKey(key)) {
  //       var localNode = localMap[key]!;
  //       if(!_isParentsEqual(localNode.parents, remoteNode.parents)) {
  //         MyLogger.err('_mergeLocalAndRemoteMap: find unmatched node, may be caused by hash conflict!!! '
  //             'local node $key(parents=${localNode.parents}), remote node $key(parents=${remoteNode.parents})');
  //       }
  //       continue;
  //     } else { // New version node
  //       localMap[key] = remoteNode;
  //       // var parentsStr = remoteNode.parents.map((e) => e.versionHash).join(',');
  //       // MyLogger.info('_mergeLocalAndRemoteMap: add new version node: hash=${remoteNode.versionHash}, parents=$parentsStr, created=${remoteNode.createdAt}');
  //       // _db.storeVersion(remoteNode.versionHash, parentsStr, remoteNode.createdAt);
  //     }
  //   }
  //   return localMap;
  // }
  // bool _isParentsEqual(List<DagNode> p1, List<DagNode> p2) {
  //   /// 1. Build a map containing all the values in p1
  //   /// 2. traverse p2, if there is any item that is not contained in map, then p2 has something not in p1, returns false
  //   /// 3. traverse map, if there is any item that is not traversed in step 2, then p1 has something not in p2, returns false
  //   /// 4. Otherwise, returns true
  //   Map<String, bool> traverseMap = {};
  //   for(final item in p1) {
  //     final hash = item.versionHash;
  //     traverseMap[hash] = false;
  //   }
  //   for(final item in p2) {
  //     final hash = item.versionHash;
  //     if(!traverseMap.containsKey(hash)) {
  //       return false;
  //     }
  //     traverseMap[hash] = true;
  //   }
  //   for(final e in traverseMap.entries) {
  //     if(e.value == false) {
  //       return false;
  //     }
  //   }
  //   return true;
  // }
  
  /// Find all versions that has no corresponding object.
  /// That means, these versions are from remote peer, but the objects are not syncing yet.
  /// Should sync these objects using 'query' message
  List<String> _findMissingVersions(Map<String, DagNode> map) {
    List<String> missing = [];
    // final versionHashList = _db.getAllValidVersionHashes();
    // Set<String> hashSet = {};
    // hashSet.addAll(versionHashList);
    for(final e in map.entries) {
      final versionHash = e.key;
      var content = _db.getObject(versionHash);
      if(content == null) {
        missing.add(versionHash);
      }
    }
    return missing;
  }
  VersionContent? _merge(String version1, String version2, String commonVersion) {
    MyLogger.info('_merge: merging version($version1) and version($version2) based on version($commonVersion)');
    final versionContent1 = _loadVersionContent(version1);
    final versionContent2 = _loadVersionContent(version2);

    if(versionContent1 == null && versionContent2 == null) {
      return null;
    }
    if(versionContent1 == null && versionContent2 != null) {
      return versionContent2;
    }
    if(versionContent1 != null && versionContent2 == null) {
      return versionContent1;
    }
    if(commonVersion == version1) {
      return versionContent2!;
    }
    if(commonVersion == version2) {
      return versionContent1!;
    }

    final commonVersionContent = _loadVersionContent(commonVersion);

    DiffOperations op1 = dm.findDifferentOperation(versionContent1!, commonVersionContent);
    DiffOperations op2 = dm.findDifferentOperation(versionContent2!, commonVersionContent);
    var mm = MergeManager(baseVersion: commonVersionContent);
    var (operations, conflicts) = mm.mergeOperations(op1, op2);
    var solvedOperations = _solveConflicts(conflicts);
    operations.addAll(solvedOperations);
    var contentVersion = mm.mergeVersions(operations, [version1, version2]);
    MyLogger.info('Merge version($version1) and version($version2) based on version($commonVersion) '
        'with ${operations.length} operations(including ${conflicts.length} conflicts), '
        'generate new version(${contentVersion.getHash()})');
    return contentVersion;
  }
  VersionContent? _loadVersionContent(String versionHash) {
    var data = _db.getObject(versionHash);
    MyLogger.info('_loadVersionContent: ($data)');
    return data == null? null: VersionContent.fromJson(jsonDecode(data.data));
  }

  List<VersionDataModel> _getVersionMap() {
    var versions = _db.getAllVersions();
    return versions;
  }

  // This function have to be placed at the bottom of a source file.
  // It seems Android Studio does not support record very well.
  // Any code after this function could not jump by ctrl+click.
  void _randomSort(List<(String, String)> list) {
    final maxIndex = list.length;
    for(var idx = 0; idx < maxIndex; idx++) {
      var newIdx = Util.getRandom(maxIndex);
      var tmp = list[idx];
      list[idx] = list[newIdx];
      list[newIdx] = tmp;
    }
  }

  List<ContentOperation> _solveConflicts(List<ContentConflict> operations) {
    List<ContentOperation> resolvedOperations = [];
    for(var item in operations) {
      var targetId = item.targetId;
      var baseHash = item.originalHash;
      var docHash1 = item.conflictHash1;
      var docHash2 = item.conflictHash2;
      var timestamp1 = item.timestamp1;
      var timestamp2 = item.timestamp2;
      var baseDoc = _loadDocContent(baseHash);
      if(baseDoc == null) {
        MyLogger.warn('_solveConflicts: error while loading document $baseHash');
        continue;
      }
      var doc1 = _loadDocContent(docHash1);
      if(doc1 == null) {
        MyLogger.warn('_solveConflicts: error while loading document $docHash1');
        continue;
      }
      var doc2 = _loadDocContent(docHash2);
      if(doc2 == null) {
        MyLogger.warn('_solveConflicts: error while loading document $docHash2');
        continue;
      }
      ConflictManager cm = ConflictManager(baseDoc: baseDoc);
      var (totalOperations, conflicts) = cm.mergeOperations(doc1, timestamp1, doc2, timestamp2);
      //TODO ignore conflicts now, should be optimized here if a better solution is found
      if(conflicts.isNotEmpty) {
        MyLogger.warn('mergeOperations: should not have any conflict here!');
      }
      var newDoc = cm.mergeDocument(totalOperations);
      var now = Util.getTimeStamp();
      var newDocHash = newDoc.getHash();
      if(_db.getObject(newDocHash) == null) { // Create a local merged document
        _db.storeObject(newDocHash, jsonEncode(newDoc), now, Constants.createdFromLocal, Constants.statusAvailable);
      }
      var op = ContentOperation(operation: ContentOperationType.modify, targetId: targetId, data: newDocHash, timestamp: now);
      MyLogger.info('Solve conflict of document($docHash1) and document($docHash2) based on document($baseHash), generate new document($newDocHash)');
      resolvedOperations.add(op);
    }
    return resolvedOperations;
  }

  DocContent? _loadDocContent(String docHash) {
    var obj = _db.getObject(docHash);
    if(obj == null) return null;
    return DocContent.fromJson(jsonDecode(obj.data));
  }

  List<DocDataModel> _getAllDocumentAndTitles() {
    var data = _db.getAllDocuments();
    var titleMap = _db.getAllTitles();
    for(var doc in data) {
      var blockStr = titleMap[doc.docId]!;
      var block = BlockContent.fromJson(jsonDecode(blockStr));
      doc.title = block.text[0].text;
    }
    return data;
  }

  /// Check all versions has object of corresponding version hash
  void _checkVersionIntegrity() {
    var versions = _db.getAllVersions();
    int countOfProblem = 0;
    for(final version in versions) {
      final hash = version.versionHash;
      final object = _db.getObject(hash);
      if(object == null) {
        if(version.status != Constants.statusUnavailable) {
          _db.updateVersionStatus(hash, Constants.statusUnavailable);
        }
        countOfProblem++;
        MyLogger.warn('Find data inconsistency of version $hash');
      }
    }
    MyLogger.info('Find $countOfProblem inconsistency issue(s)');
  }
  void _checkObjectsIntegrity() {
    // Not implemented yet
  }

  static BlockContent _genDefaultTitleBlock(String title) {
    var blockContent = BlockContent(
      type: Constants.blockTypeTitleTag,
      listing: Constants.blockListTypeNone,
      level: Constants.blockLevelDefault,
      text: [TextDesc()..text = title],
    );
    return blockContent;
  }
  static DocContent _genDocContentWithTitle(String docId, String blockId, BlockContent blockContent) {
    DocContentItem block = DocContentItem(blockId: blockId, blockHash: '');
    return DocContent(contents: [block]);
  }
}