import 'dart:convert';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/collaborate/conflict_manager.dart';
import 'package:mesh_note/mindeditor/document/collaborate/merge_manager.dart';
import 'package:mesh_note/mindeditor/document/collaborate/version_manager.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/inspired_seed.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:mesh_note/mindeditor/document/text_desc.dart';
import 'package:my_log/my_log.dart';
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
  List<DocData> _docTitles = [];
  String _currentVersion = '';
  int _currentVersionTimestamp = 0;
  bool _syncing = false;

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
    _docTitles.add(DocData(docId: docId, title: title, hash: '', timestamp: now));
    return docId;
  }

  List<VersionData> genAndSaveNewVersionTree() {
    if(!hasModified()) return [];
    final now = Util.getTimeStamp();
    var version = _genVersionAndClearModified(now);
    _saveVersion(version, _currentVersion, now);
    return _getVersionMap();
  }
  /// Generate version and returns version and required objects
  ///
  /// returns version and required objects
  // Map<String, VersionTreeItem> genAndSaveNewVersion() {
  //   if(!hasModified()) return {};
  //
  //   // generate and save version
  //   final now = Util.getTimeStamp();
  //   var version = _genVersionAndClearModified(now);
  //   _saveVersion(version, now);
  //
  //   // generate required objects list
  //   var requiredObjects = _genRequiredObjects();
  //   return (version, requiredObjects);
  // }

  /// Generate new version tree by merging local and remote version tree.
  /// If missing any version, require it from remote nodes.
  /// If no missing version, merge versions.
  /// Once assembling, set syncing status to stop other nodes sending version_tree concurrently.
  void assembleVersionTree(List<VersionNode> versionDag) {
    setSyncing();
    Map<String, DagNode> remoteDagMap = _buildRemoteVersionTreeMap(versionDag);
    Map<String, DagNode> localDagMap = _genVersionMap();
    Map<String, DagNode> newMap = _mergeLocalAndRemoteMap(localDagMap, remoteDagMap);
    _tryToMergeVersionTree(newMap);
  }
  /// Assemble new version into current version
  /// 
  /// 1. Store all required objects(including version object itself) into database
  /// 2. Get common ancestor version of current version and new version
  /// 3. Merge these two version based on common version, and we get a new merged version
  /// 4. Update current version to merged version
  /// 5. Save version flags and refresh view
  void assembleVersion(String versionHash, String versionStr, List<String> parents, Map<String, String> requiredObjects) {
    // requiredObjects[versionHash] = versionStr;
    // _storeAllObjects(requiredObjects);
    //
    // String ancestorVersion = _getCommonAncestor(_currentVersion, versionHash, {});
    // var mergedVersion = _merge(_currentVersion, versionHash, ancestorVersion);
    // mergedVersion = VersionContent.fromJson(jsonDecode(versionStr));
    //
    // for(var item in mergedVersion.table) {
    //   _updateDoc(item, requiredObjects);
    // }
    //
    // var now = Util.getTimeStamp();
    // _saveVersion(mergedVersion, now);
    //
    // Controller.instance.refreshDocNavigator();
  }
  List<SendVersionsNode> assembleRequireVersions(List<String> requiredVersions) {
    List<SendVersionsNode> result = [];
    for(var versionHash in requiredVersions) {
      final versionData = _db.getVersionData(versionHash);
      if(versionData == null) {
        MyLogger.warn('assembleRequireVersions: version(hash=$versionHash) not found!!!');
        continue;
      }
      final json = _db.getObject(versionHash);
      final versionContent = VersionContent.fromJson(jsonDecode(json));
      Map<String, String> requiredObjects = _genRequiredObjects(versionContent);

      var node = SendVersionsNode(
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
  /// Assemble new version into current version
  ///
  /// 1. Store all required objects(including version object itself) into database
  /// 2. Try to merge entire version tree
  void assembleVersions(List<SendVersionsNode> versions) {
    for(var item in versions) {
      var versionHash = item.versionHash;
      var versionContent = item.versionContent;
      var timestamp = item.createdAt;
      var parents = item.parents;
      _db.storeVersion(versionHash, parents, timestamp);
      _db.storeObject(versionHash, versionContent);
      MyLogger.info('assembleVersions: storing objects for version $versionHash');
      var requiredObjects = item.requiredObjects;
      _storeAllObjects(requiredObjects);
    }
    var _versionMap = _genVersionMap();
    MyLogger.info('efantest: _versionMap=$_versionMap');
    _tryToMergeVersionTree(_versionMap);
  }

  bool isSyncing() => _syncing;
  void setSyncing() {
    _syncing = true;
  }
  void clearSyncing() {
    _syncing = false;
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

    for(var item in contentVersion.table) {
      _updateDoc(item, {});
    }

    bool fastForward = newVersionHash == _currentVersion || newVersionHash == targetVersion;
    var now = fastForward? contentVersion.timestamp: Util.getTimeStamp();
    var parents = fastForward? '': '$_currentVersion,$targetVersion'; // Ignore parents if fast_forward
    _saveVersion(contentVersion, parents, now, fastForward: fastForward);
  }
  void _updateDoc(VersionContentItem node, Map<String, String> objects) {
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
    _db.insertOrUpdateDoc(docId, found.hash, found.timestamp);

    // Store doc content into objects
    // var docContentStr = objects[found.hash]!;
    var docContentStr = _db.getObject(found.hash);
    MyLogger.info('efantest: docContent=$docContentStr');
    _db.storeObject(found.hash, docContentStr);
    var docContent = DocContent.fromJson(jsonDecode(docContentStr));

    // Store blocks into objects
    for(var content in docContent.contents) {
      var blockId = content.blockId;
      var blockHash = content.blockHash;
      // Not support .children
      // String blockStr = objects[blockHash]!;
      String blockStr = _db.getObject(blockHash);
      MyLogger.info('efantest: blockId=$blockId, blockHash=$blockHash, blockStr=$blockStr');
      _db.storeObject(blockHash, blockStr);
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
    final (docId, blockId) = seed.ids[index];
    if(seed.cache.containsKey(blockId) && seed.cache[blockId] != null) {
      return seed.cache[blockId];
    }
    var data = _db.getRawBlockById(docId, blockId);
    if(data != null) {
      var para = ParagraphDesc.buildFromJson(id: data.blockId, jsonStr: data.blockData, time: data.updatedAt);
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
      _db.storeObject(hash, jsonStr);
      _db.storeVersion(hash, parents, now);
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

  DocData? _getDocTreeNode(String docId) {
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

  Map<String, String> _genRequiredObjects(VersionContent versionContent) {
    Map<String, String> result = {};

    for(var item in versionContent.table) {
      var docId = item.docId;
      var docHash = item.docHash;
      var docContentStr = _db.getObject(docHash);
      MyLogger.info('_genRequiredObjects: docId=$docId, docHash=$docHash, docStr=$docContentStr');
      result[docHash] = docContentStr;

      //TODO should load history document by docHash
      var docContent = DocContent.fromJson(jsonDecode(docContentStr));
      for(var block in docContent.contents) {
        _recursiveAddToMap(block, result);
      }
    }
    return result;
  }
  void _recursiveAddToMap(DocContentItem block, Map<String, String> map) {
    var blockHash = block.blockHash;
    if(!map.containsKey(blockHash)) {
      var blockContent = _db.getObject(blockHash);
      map[blockHash] = blockContent;
    }
    for(var item in block.children) {
      _recursiveAddToMap(item, map);
    }
  }

  static List<VersionContentItem> _genDocTreeNodeList(List<DocData> list) {
    List<VersionContentItem> result = [];
    for(var item in list) {
      var node = VersionContentItem(docId: item.docId, docHash: item.hash, title: item.title, updatedAt: item.timestamp);
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

  void _storeAllObjects(Map<String, String> objects) {
    for(var entry in objects.entries) {
      var hash = entry.key;
      var value = entry.value;
      _db.storeObject(hash, value);
    }
  }
  String _getCommonAncestor(String version1, String version2, Map<String, DagNode> _versionMap) {
    if(_versionMap.isEmpty) {
      _versionMap = _genVersionMap();
    }
    var verNode1 = _versionMap[version1];
    var verNode2 = _versionMap[version2];
    if(verNode1 == null || verNode2 == null) {
      return '';
    }
    DagNode? resultNode = vm.findNearestCommonAncestor([verNode1, verNode2], _versionMap);
    return resultNode?.versionHash??'';
  }
  Map<String, DagNode> _genVersionMap() {
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
  Map<String, DagNode> _buildRemoteVersionTreeMap(List<VersionNode> dagList) {
    Map<String, DagNode> result = {};
    for(var item in dagList) {
      final versionHash = item.versionHash;
      final timestamp = item.createdAt;
      var node = DagNode(versionHash: versionHash, createdAt: timestamp, parents: []);
      result[versionHash] = node;
    }
    for(var item in dagList) {
      final versionHash = item.versionHash;
      final parents = item.parents;
      final currentNode = result[versionHash]!;
      for(var p in parents) {
        var parentNode = result[p];
        if(parentNode == null) continue;
        currentNode.parents.add(parentNode);
      }
    }
    return result;
  }
  List<String> _splitParents(String parents) {
    List<String> _sp = parents.split(',');
    return _sp;
  }
  Map<String, DagNode> _mergeLocalAndRemoteMap(Map<String, DagNode> localMap, Map<String, DagNode> remoteMap) {
    for(var e in remoteMap.entries) {
      var key = e.key;
      var remoteNode = e.value;
      if(localMap.containsKey(key)) {
        var localNode = localMap[key]!;
        if(!_isParentsEqual(localNode.parents, remoteNode.parents)) {
          MyLogger.err('_mergeLocalAndRemoteMap: find unmatched node, may be caused by hash conflict!!! '
              'local node $key(parents=${localNode.parents}), remote node $key(parents=${remoteNode.parents})');
        }
        continue;
      } else { // New version node
        localMap[key] = remoteNode;
        // var parentsStr = remoteNode.parents.map((e) => e.versionHash).join(',');
        // MyLogger.info('_mergeLocalAndRemoteMap: add new version node: hash=${remoteNode.versionHash}, parents=$parentsStr, created=${remoteNode.createdAt}');
        // _db.storeVersion(remoteNode.versionHash, parentsStr, remoteNode.createdAt);
      }
    }
    return localMap;
  }
  bool _isParentsEqual(List<DagNode> p1, List<DagNode> p2) {
    /// 1. Build a map containing all the values in p1
    /// 2. traverse p2, if there is any item that is not contained in map, then p2 has something not in p1, returns false
    /// 3. traverse map, if there is any item that is not traversed in step 2, then p1 has something not in p2, returns false
    /// 4. Otherwise, returns true
    Map<String, bool> traverseMap = {};
    for(final item in p1) {
      final hash = item.versionHash;
      traverseMap[hash] = false;
    }
    for(final item in p2) {
      final hash = item.versionHash;
      if(!traverseMap.containsKey(hash)) {
        return false;
      }
      traverseMap[hash] = true;
    }
    for(final e in traverseMap.entries) {
      if(e.value == false) {
        return false;
      }
    }
    return true;
  }
  List<String> _findMissingVersions(Map<String, DagNode> map) {
    List<String> result = [];
    final versionHashList = _db.getAllValidVersionHashes();
    Set<String> hashSet = {};
    hashSet.addAll(versionHashList);
    for(final e in map.entries) {
      final versionHash = e.key;
      if(!hashSet.contains(versionHash)) {
        result.add(versionHash);
      }
    }
    return result;
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
    return data.isEmpty? null: VersionContent.fromJson(jsonDecode(data));
  }

  List<VersionData> _getVersionMap() {
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
      var newDocHash = newDoc.getHash();
      _db.storeObject(newDocHash, jsonEncode(newDoc));
      var now = Util.getTimeStamp();
      var op = ContentOperation(operation: ContentOperationType.modify, targetId: targetId, data: newDocHash, timestamp: now);
      MyLogger.info('Solve conflict of document($docHash1) and document($docHash2) based on document($baseHash), generate new document($newDocHash)');
      resolvedOperations.add(op);
    }
    return resolvedOperations;
  }

  DocContent? _loadDocContent(String docHash) {
    String str = _db.getObject(docHash);
    if(str.isEmpty) return null;
    return DocContent.fromJson(jsonDecode(str));
  }

  List<DocData> _getAllDocumentAndTitles() {
    var data = _db.getAllDocuments();
    var titleMap = _db.getAllTitles();
    for(var doc in data) {
      var blockStr = titleMap[doc.docId]!;
      var block = BlockContent.fromJson(jsonDecode(blockStr));
      doc.title = block.text[0].text;
    }
    return data;
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