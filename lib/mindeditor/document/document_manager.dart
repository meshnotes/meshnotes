import 'dart:async';
import 'dart:convert';
import 'package:keygen/keygen.dart';
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
import 'version_tree_status.dart';
import 'package:mesh_note/mindeditor/document/text_desc.dart';
import 'package:my_log/my_log.dart';
import '../../net/version_chain_api.dart';
import '../../util/util.dart';
import '../setting/constants.dart';
import 'collaborate/diff_manager.dart';

class DocumentManager {
  SyncStatus _syncStatus = SyncStatus.idle;
  VersionStatus _versionStatus = VersionStatus.idle;
  bool _hasModified = false;
  final DbHelper _db;
  final Map<String, Document> _documents = {};
  VersionManager vm = VersionManager();
  DiffManager dm = DiffManager();
  String? currentDocId;
  List<DocDataModel> _docTitles = [];
  String _currentVersion = '';
  int _currentVersionTimestamp = 0;
  Timer? _idleTimer;
  int _lastSyncTime = 0;
  final Set<String> _allWaitingVersions = {};
  final Map<String, int> _retryCounter = {};
  final controller = Controller();

  DocumentManager({
    required DbHelper db,
  }): _db = db {
    _allWaitingVersions.addAll(_loadAllUnavailableNodes());
    _initRetryCounter(_allWaitingVersions);
    MyLogger.info('DocumentManager: loaded missing versions: $_allWaitingVersions');
    controller.evenTasksManager.addAfterInitTask(() {
      Future(() {
        checkConsistency();
      });
    });
    // Periodically send newest version to peers
    Timer.periodic(const Duration(seconds: Constants.timeoutOfPeriodSync), (timer) {
      final now = Util.getTimeStamp();
      _checkSyncingStatus(now);
      _checkIfSendVersionBroadcast(now);
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
      controller.tryToSaveAndSendVersionTree();
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
  void closeDocument() {
    if(currentDocId == null) return;

    if(hasModified()) {
      controller.tryToSaveAndSendVersionTree();
    }
    _documents[currentDocId]?.closeDocument();
    currentDocId = null;
  }

  Document? getDocument(String docId) {
    if(_documents.containsKey(docId)) return _documents[docId]!;
    final document = _getDocFromDb(docId);
    if(document == null) return null;
    _documents[docId] = document;
    return document;
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

  void deleteDocument(String docId) {
    _db.deleteDocument(docId);
    _docTitles.removeWhere((e) => e.docId == docId);
    _documents.remove(docId);
    setModified();
  }
  void deleteCurrentDocument() {
    if(currentDocId == null) return;

    deleteDocument(currentDocId!);
    currentDocId = null;
  }

  bool createDocument(String title, String content) {
    final now = Util.getTimeStamp();
    final docId = _db.newDocument(now);
    final doc = Document.createDocument(_db, docId, title, content, this, now);
    _documents[docId] = doc;
    _docTitles.add(DocDataModel(docId: docId, title: title, hash: '', timestamp: now));
    return docId.isNotEmpty;
  }

  List<VersionDataModel> getCurrentRawVersionTree() {
    var versions = _db.getAllVersions();
    return versions;
  }
  List<VersionDataModel> getCurrentValidVersionTree() {
    if(_currentVersion.isEmpty || _currentVersionTimestamp == 0) return []; // Not ready
    final versions = _getValidVersionMap(_currentVersion);
    return versions;
  }

  String getLatestVersion() {
    return _currentVersion;
  }

  void genNewVersionTree({String? parent}) {
    if(!hasModified()) return;
    if(isGenerating() || isSyncing()) return;
    _setGenerating();
    final now = Util.getTimeStamp();
    final parents = [parent?? _currentVersion];
    var version = _genVersionAndClearModified(now, parents);
    _storeVersionFromLocalAndUpdateCurrentVersion(version, parents, now);
    _clearGenerating();
    final versions = _getValidVersionMap(_currentVersion); // Just for test, to check version tree's size
    CallbackRegistry.showToast('version tree has ${versions.length} nodes');
  }
  // If current version is not synced, and has 0 or 1 parent, override it
  void tryToGenNewVersionTreeAndOverrideCurrent() {
    // If current version is not exists, generate a new version tree
    if(_currentVersion.isEmpty) {
      genNewVersionTree();
      return;
    }
    final versionData = _db.getVersionData(_currentVersion);
    // If current version is synced, or is not created from local, it is better not to override and deprecate it.
    // So generate a new version tree
    if(versionData == null || versionData.syncStatus != Constants.syncStatusNew || versionData.createdFrom != Constants.createdFromLocal) {
      genNewVersionTree();
      return;
    }
    // If current version has more than one parent, it cannot be overridden, so generate a new version tree
    final parents = versionData.getParentsList();
    if(parents.length > 1) {
      genNewVersionTree();
      return;
    }
    final savedCurrentVersion = _currentVersion;
    final parent = parents.length == 1? parents.first: null;
    MyLogger.info('tryToGenNewVersionTreeAndOverrideCurrent: parent=$parent');
    genNewVersionTree(parent: parent);
    _deprecateVersion(savedCurrentVersion);
  }

  (List<VersionDataModel>, int) genCurrentVersionTree() {
    if(_currentVersion.isEmpty || _currentVersionTimestamp == 0) return ([], 0); // Not ready
    final versions = _getValidVersionMap(_currentVersion);
    CallbackRegistry.showToast('version tree has ${versions.length} nodes');
    return (versions, _currentVersionTimestamp);
  }

  /// Generate new version tree by merging local and remote version tree.
  /// If missing any version, require it from remote nodes.
  /// If no missing version, merge versions.
  /// Once assembling, set syncing status to stop other nodes sending version_tree concurrently.
  void assembleVersionTree(List<VersionNode> versionDag) {
    _setSyncing();
    _storeVersionsFromPeer(versionDag);
    // Map<String, DagNode> remoteDagMap = _buildRemoteVersionTreeMap(versionDag);
    Map<String, DagNode> localDagMap = _genVersionMapFromDb();
    // Map<String, DagNode> newMap = _mergeLocalAndRemoteMap(localDagMap, remoteDagMap);
    _tryToMergeVersionTree(localDagMap);
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
    MyLogger.info('assembleResources: resources=$resources');
    for(var res in resources) {
      String key = res.key;
      int timestamp = res.timestamp;
      String content = res.data;
      if(!_db.hasObject(key)) {
        _db.storeObject(key, content, timestamp, Constants.createdFromPeer, Constants.statusAvailable);
      }
      if(_allWaitingVersions.contains(key)) {
        _allWaitingVersions.remove(key);
        _db.updateVersionStatus(key, Constants.statusAvailable);
      }
    }
    var _versionMap = _genVersionMapFromDb();
    _tryToMergeVersionTree(_versionMap);
  }

  bool isGenerating() => _versionStatus != VersionStatus.idle;
  void _setGenerating() {
    _versionStatus = VersionStatus.generating;
  }
  void _clearGenerating() {
    _versionStatus = VersionStatus.idle;
  }
  bool isSyncing() => _syncStatus != SyncStatus.idle;
  void _setSyncing() {
    _syncStatus = SyncStatus.waiting;
    _lastSyncTime = Util.getTimeStamp();
  }
  void _setMerging() {
    _syncStatus = SyncStatus.merging;
  }
  void _clearSyncing() {
    _syncStatus = SyncStatus.idle;
    _lastSyncTime = 0;
  }
  bool isBusy() => isGenerating() || isSyncing();

  void checkConsistency() {
    _checkVersionIntegrity();
    _checkObjectsIntegrity();
  }

  void markCurrentVersionAsSyncing() {
    final versionData = _db.getVersionData(_currentVersion);
    // Not possible to be null
    if(versionData == null || versionData.syncStatus != Constants.syncStatusNew) return;
    _db.updateVersionSyncStatus(_currentVersion, Constants.syncStatusSyncing);
  }

  /// Try to merge entire version tree, called after receiving new version_tree or receiving missing versions.
  /// 1. If some versions are still waiting for detail data, send require_versions request to other peers
  /// 2. If some versions are missing, but no waiting versions, ignore missing versions and try to merge
  /// 3. If all versions are ready, merge versions
  void _tryToMergeVersionTree(Map<String, DagNode> newMap) {
    Set<DagNode> missingVersions = _findWaitingOrMissingVersions(newMap);
    _allWaitingVersions.addAll(missingVersions.map((e) => e.versionHash));
    _increaseRetryCounterAndFilter(_allWaitingVersions);
    bool forceMerge = _checkForceMergeOrNot(missingVersions);
    if(missingVersions.isNotEmpty && !forceMerge) {
      controller.sendRequireVersions(_allWaitingVersions.toList());
    } else {
      var leafNodes = _findAvailableLeafNodesInDag(newMap); // Find available leaf nodes before removing unavailable nodes
      leafNodes.remove(_currentVersion);
      if(leafNodes.isEmpty) {
        MyLogger.info('Try to merge, but no leaf nodes available');
        return;
      }
      removeMissingVersions(newMap);
      removeDeprecatedVersions(newMap);
      MyLogger.info('Try to merge $_currentVersion with $leafNodes');
      _mergeVersions(newMap, leafNodes);
    }
  }
  /// Merge all leaf nodes of versions
  /// 1. Find all leaf nodes(versions that has no child) except current version
  /// 2. Merge current version and each leaf versions two by two in one time
  ///   2.1. Find common ancestor of current version and leaf version
  ///   2.2. Merge current version and leaf version based on common ancestor, and we get a new merged version
  ///   2.3 Update current version to that newly merged version
  /// 5. Refresh view
  void _mergeVersions(Map<String, DagNode> map, Set<String> leafNodes) {
    _setMerging();
    MyLogger.info('_mergeVersions: find leaf nodes: $leafNodes');
    MyLogger.info('_mergeVersions: remove current node: $_currentVersion');
    for(var leafHash in leafNodes) {
      String commonVersionHash = _getCommonAncestor(_currentVersion, leafHash, map);
      MyLogger.info('_mergeVersions: Try to merge version($_currentVersion) and version($leafHash) by common version($commonVersionHash)');
      _mergeCurrentAndSave(leafHash, commonVersionHash);
    }
    controller.refreshDocNavigator();
    _clearSyncing();
  }
  /// Find all nodes that is available and is not parent of any other node
  Set<String> _findAvailableLeafNodesInDag(Map<String, DagNode> map) {
    Set<String> result = map.keys.toSet();
    for(var e in map.values) {
      if(e.status != Constants.statusAvailable) {
        result.remove(e.versionHash);
        continue;
      }
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
    // Remove document that is not in new version tree, that means it is deleted
    List<String> docToDelete = [];
    for(var docTitle in _docTitles) {
      final docId = docTitle.docId;
      bool found = false;
      for(var docNode in contentVersion.table) {
        if(docId == docNode.docId) {
          found = true;
          break;
        }
      }
      if(!found) {
        docToDelete.add(docId);
      }
    }
    for(var docId in docToDelete) {
      deleteDocument(docId);
    }

    bool fastForward = newVersionHash == _currentVersion || newVersionHash == targetVersion;
    var now = fastForward? contentVersion.timestamp: Util.getTimeStamp();
    List<String> parents = fastForward? []: [_currentVersion, targetVersion]; // Ignore parents if fast_forward
    _storeVersionFromLocalAndUpdateCurrentVersion(contentVersion, parents, now, fastForward: fastForward);
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
      var blockState = controller.getEditingBlockState();
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
    int? timestamp;
    if(t != null) {
      timestamp = int.tryParse(t, radix: 10);
    }
    return (ver?? '', timestamp?? 0);
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

  void setIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: Constants.timeoutOfSyncIdle), () {
      controller.evenTasksManager.triggerIdle();
      controller.tryToSaveAndSendVersionTree();
      _idleTimer = null;
    });
  }

  DocDataModel? _getDocTreeNode(String docId) {
    for(var node in _docTitles) {
      if(node.docId == docId) {
        return node;
      }
    }
    return null;
  }

  void _storeVersionFromLocalAndUpdateCurrentVersion(VersionContent version, List<String> parents, int now, {bool fastForward = false}) {
    MyLogger.info('storeVersionFromLocalAndUpdateCurrentVersion: parents=${parents.join(',')}');
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
      _db.storeVersion(hash, parents.join(','), now, Constants.createdFromLocal, Constants.statusAvailable);
      _db.setFlag(Constants.flagNameCurrentVersion, hash);
      _db.setFlag(Constants.flagNameCurrentVersionTimestamp, now.toString());

      MyLogger.info('Save new version($hash), parent=$parents');
      _currentVersionTimestamp = now;
      _currentVersion = hash;
    }
  }
  void _storeVersionsFromPeer(List<VersionNode> versionDag) {
    for(var node in versionDag) {
      String versionHash = node.versionHash;
      String parents = _buildParents(node.parents);
      int timestamp = node.createdAt;
      var localVersion = _db.getVersionData(versionHash);
      if(localVersion == null) { // If the version is not exists, create one and set it as from_peer/waiting
        _db.storeVersion(versionHash, parents, timestamp, Constants.createdFromPeer, Constants.statusWaiting);
      }
    }
  }

  VersionContent _genVersionAndClearModified(int now, List<String> parents) {
    List<Document> modifiedDocuments = _findModifiedDocuments();
    Map<String, String> newHashes = _genAndSaveDocuments(modifiedDocuments);
    _updateDocumentHashes(newHashes, now);
    var docTable = _genDocTreeNodeList(_docTitles);
    var version = VersionContent(table: docTable, timestamp: now, parentsHash: parents);
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

    return Document.loadByNode(_db, docNode, this);
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
    var verNode1 = _versionMap[version1];
    var verNode2 = _versionMap[version2];
    if(verNode1 == null || verNode2 == null) {
      return '';
    }
    DagNode? resultNode = vm.findNearestCommonAncestor([verNode1, verNode2], _versionMap);
    return resultNode?.versionHash?? '';
  }

  Map<String, DagNode> _genVersionMapFromDb() {
    var _allVersions = _db.getAllVersions();

    // Generate version map
    Map<String, DagNode> _map = {};
    for(var item in _allVersions) {
      final versionHash = item.versionHash;
      final timestamp = item.createdAt;
      final status = item.status;
      var node = DagNode(versionHash: versionHash, createdAt: timestamp, status: status, parents: []);
      _map[versionHash] = node;
    }
    // Generate version parents pointer
    for(var item in _allVersions) {
      final versionHash = item.versionHash;
      final parents = item.getParentsList();
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

  /// If all the nodes' statuses are missing or deprecated, then we can force merge them.
  /// If some nodes are in waiting status, then we should wait for them.
  bool _checkForceMergeOrNot(Set<DagNode> nodes) {
    for(var node in nodes) {
      if(node.status == Constants.statusWaiting) {
        return false;
      }
    }
    return true;
  }
  /// Find all versions that has no corresponding object.
  /// That means, these versions are from remote peer, but the objects are not syncing yet.
  /// Should sync these objects using 'query' message
  Set<DagNode> _findWaitingOrMissingVersions(Map<String, DagNode> map) {
    Set<DagNode> missing = {};
    for(final e in map.entries) {
      final versionHash = e.key;
      final node = e.value;
      if(!_db.hasObject(versionHash)) {
        missing.add(e.value);
      }
      if(node.status == Constants.statusWaiting) {// || node.status == Constants.statusMissing) {
        missing.add(e.value);
      }
    }
    return missing;
  }

  /// Remove all missing or waiting version nodes from the map
  static void removeMissingVersions(Map<String, DagNode> map) {
    /// 1. Find all unavailable(missing or waiting) nodes
    /// 2. For each unavailable node, remove it from its children nodes' parents list, replace with its parents
    /// 3. Remove unavailable nodes from the map
    final unavailableNodes = <DagNode>{};
    // Step 1
    for(final node in map.values) {
      if(node.status == Constants.statusWaiting || node.status == Constants.statusMissing) {
        unavailableNodes.add(node);
      }
    }
    MyLogger.info('Unavailable versions to remove: $unavailableNodes');
    // Step 2
    for(final badNode in unavailableNodes) {
      for(final node in map.values) {
        Set<DagNode> parents = node.parents.toSet(); // Change to set, to avoid redundant
        if(parents.contains(badNode)) {
          parents.remove(badNode);
          parents.addAll(badNode.parents);
          node.parents = parents.toList();
        }
      }
    }
    // Step 3
    map.removeWhere((_, value) => unavailableNodes.contains(value));
  }
  /// Remove all the deprecated version nodes from the map, along with their parents recursively
  static void removeDeprecatedVersions(Map<String, DagNode> map) {
    /// 1. Find all deprecated nodes
    /// 2. For each deprecated node, remove it from its children nodes' parents list
    /// 3. Remove unavailable nodes from the map
    MyLogger.info('Try to deprecated nodes');
    // Step 1
    Set<DagNode> deprecatedNodes = {};
    for(final node in map.values) {
      if(node.status == Constants.statusDeprecated) {
        deprecatedNodes.add(node);
      }
    }
    MyLogger.info('Deprecated versions to remove: $deprecatedNodes');
    // Step 2
    for(final d in deprecatedNodes) {
      for(final node in map.values) {
        final parents = node.parents;
        if(parents.contains(d)) {
          parents.remove(d);
        }
      }
    }
    // Step 3
    map.removeWhere((_, value) => deprecatedNodes.contains(value));
  }

  static void _recursiveRemoveDeprecatedNodes(DagNode node, Map<String, DagNode> map, Set<String> toRemove) {
    const tmpRemoveTag = -999999; // Use this tag instead of searching node in the toRemove set to avoid time consuming
    final parents = node.parents;
    for(final p in parents) {
      if(p.status == tmpRemoveTag) continue;

      _recursiveRemoveDeprecatedNodes(p, map, toRemove);
    }
    node.status = tmpRemoveTag;
    toRemove.add(node.versionHash);
  }

  VersionContent? _merge(String version1, String version2, String commonVersion) {
    MyLogger.info('_merge: merging version(${HashUtil.formatHash(version1)}) and version(${HashUtil.formatHash(version2)}) based on version(${HashUtil.formatHash(commonVersion)})');
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
    MyLogger.info('Merge version(${HashUtil.formatHash(version1)}) and version(${HashUtil.formatHash(version2)}) based on version(${HashUtil.formatHash(commonVersion)}) '
        'with ${operations.length} operations(including ${conflicts.length} conflicts), '
        'generate new version(${HashUtil.formatHash(contentVersion.getHash())})');
    return contentVersion;
  }
  VersionContent? _loadVersionContent(String versionHash) {
    if(versionHash == '') return null;

    var versionObject = _db.getObject(versionHash);
    MyLogger.info('_loadVersionContent: ($versionObject)');
    return versionObject == null? null: VersionContent.fromJson(jsonDecode(versionObject.data));
  }

  List<VersionDataModel> _getValidVersionMap(String newestVersion) {
    var versions = _db.getAllVersions();
    versions = filterUnreachableVersions(versions, newestVersion);
    MyLogger.info('_getValidVersionMap: version tree has ${versions.length} nodes');
    return versions;
  }
  static List<VersionDataModel> filterUnreachableVersions(List<VersionDataModel> versions, String newestVersion) {
    /// 1. Visit every parent versions from newestVersion
    /// 2. Mark every visited version
    /// 3. Add every visited version to result, ignore all unreachable(unvisited) versions
    Map<String, bool> visited = {};
    Map<String, VersionDataModel> map = {};
    Set<String> waitingQueue = {};
    for(final ver in versions) {
      visited[ver.versionHash] = false;
      map[ver.versionHash] = ver;
    }
    waitingQueue.add(newestVersion);
    while(waitingQueue.isNotEmpty) {
      final currentHash = waitingQueue.first;
      waitingQueue.remove(currentHash);

      final current = map[currentHash];
      if(current == null) continue;

      visited[currentHash] = true;
      final parents = current.getParentsList();
      waitingQueue.addAll(parents);
    }
    List<VersionDataModel> result = [];
    for(final ver in versions) {
      if(visited[ver.versionHash] == true) {
        result.add(ver);
      }
    }
    return result;
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
      if(!_db.hasObject(newDocHash)) { // Create a local merged document if not exists
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
    int countOfGood = 0;
    for(final version in versions) {
      final hash = version.versionHash;
      if(!_db.hasObject(hash)) {
        if(version.status != Constants.statusWaiting || version.status != Constants.statusMissing) {
          // _db.updateVersionStatus(hash, Constants.statusWaiting);
        }
        countOfProblem++;
        MyLogger.warn('Find data inconsistency for version ${HashUtil.formatHash(hash)}');
      } else {
        countOfGood++;
      }
    }
    MyLogger.info('Find $countOfProblem inconsistency issue(s)');
    CallbackRegistry.showToast('Versions: $countOfGood good, $countOfProblem bad');
  }
  void _checkObjectsIntegrity() {
    // Not implemented yet
  }
  Set<String> _loadAllUnavailableNodes() {
    var versions = _db.getAllVersions();
    Set<String> result = {};
    for(final version in versions) {
      if(version.status == Constants.statusMissing) {// || version.status == Constants.statusWaiting) {
        result.add(version.versionHash);
      }
    }
    return result;
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

  void _checkSyncingStatus(int now) {
    if(_lastSyncTime == 0 || now - _lastSyncTime < 30000) return;
    MyLogger.info('_checkSyncingStatus: try to clear waiting versions and retry');
    // // Clearing syncing flag if timeout(>30s)
    // if(isSyncing()) {
    //   _clearSyncing();
    // }
    if(_allWaitingVersions.isNotEmpty) {
      for(var hash in _allWaitingVersions) {
        var node = _db.getVersionData(hash);
        if(node?.status == Constants.statusWaiting) {
          _db.updateVersionStatus(hash, Constants.statusMissing);
        }
      }
      _allWaitingVersions.clear();
    }
    assembleResources([]);
  }
  void _checkIfSendVersionBroadcast(int now) {
    if(now - _currentVersionTimestamp < 15000) return;
    // Broadcast latest version if the it has been generated over 15s
    controller.sendVersionBroadcast();
  }

  void _initRetryCounter(Set<String> missingVersions) {
    _retryCounter.clear();
    for(var hash in missingVersions) {
      _retryCounter[hash] = 0;
    }
  }
  void _increaseRetryCounterAndFilter(Set<String> retriedVersions) {
    Set<String> versionsExceedMaxRetryCount = {};
    for(final version in retriedVersions) {
      int count = _retryCounter[version]?? 0;
      count += 1;
      _retryCounter[version] = count;
      if(count > 3) {
        versionsExceedMaxRetryCount.add(version);
      }
    }
    for(final version in versionsExceedMaxRetryCount) {
      MyLogger.info('_increaseRetryCounterAndFilter: version($version) exceed max retry count, remove it from waiting list');
      _db.updateVersionStatus(version, Constants.statusMissing);
      retriedVersions.remove(version);
    }
  }

  void _deprecateVersion(String versionHash) {
    _db.updateVersionStatus(versionHash, Constants.statusDeprecated);
  }
}