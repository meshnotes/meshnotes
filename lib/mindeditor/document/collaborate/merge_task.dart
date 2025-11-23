import 'dart:convert';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/net/version_chain_api.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import '../dal/db_helper.dart';
import '../dal/doc_data_model.dart';
import '../doc_content.dart';
import '../doc_utils.dart';
import 'version_manager.dart';

class MergeTask {
  static const int _checkInterval = 15000; // 15 seconds
  static const int _sendMissingRequestInterval = 120000; // 2 minutes
  final DbHelper _db;
  final Controller controller = Controller();
  int _lastCheckTimeStamp = 0;
  int _lastSentMissingRequestTimeStamp = 0;
  int _progress = 0;

  MergeTask({required DbHelper db}): _db = db {
    controller.eventTasksManager.addTimerTask('mergeTask', () {
      check();
    }, _checkInterval);
  }

  void check() {
    int now = Util.getTimeStamp();
    if(now - _lastCheckTimeStamp < _checkInterval) return; // Not enough time passed, do nothing
    _lastCheckTimeStamp = now;

    if(!_db.hasSyncingVersion()) {
      controller.eventTasksManager.triggerUpdateSyncing(false, _progress);
      return; // No syncing version, do nothing
    }
    controller.eventTasksManager.triggerUpdateSyncing(true, _progress);
    if(now - _lastSentMissingRequestTimeStamp >= _sendMissingRequestInterval) {
      _tryToMerge();
    }
  }

  void addVersionTree(List<VersionNode> dag) {
    controller.eventTasksManager.triggerUpdateSyncing(true, _progress);
    _storeVersionToSyncDb(dag);
    _tryToMerge();
  }

  void addResources(List<UnsignedResource> resources) {
    final addedResourceCount = _storeResourcesToSyncDb(resources);
    if(addedResourceCount > 0) { // If no new resource added, do nothing
      _lastSentMissingRequestTimeStamp = 0;
      _tryToMerge();
    }
  }

  void clearSyncingTasks() {
    _db.clearSyncingTables();
    _progress = 0;
    controller.eventTasksManager.triggerUpdateSyncing(false, 0);
  }

  /// 1. Find missing versions, if any, send require versions and exit
  /// 2. If all versions are available, start to merge
  ///   2.1. Store sync_* tables to db
  ///   2.2. Try to merge versions
  ///   2.3. Clear sync_* tables if merge success
  void _tryToMerge() {
    MyLogger.info('_tryToMerge: start to merge');
    Map<String, DagNode> localDagMap = _genVersionMapFromSyncingDb();
    Set<DagNode> missingVersions = _findWaitingOrMissingVersions(localDagMap);
    if(missingVersions.isNotEmpty) { //TODO: Ignore some missing versions after too many retries, unless it's the leaf version
      MyLogger.info('_tryToMerge: missing versions: $missingVersions');
      controller.sendRequireVersions(missingVersions.map((node) => node.versionHash).toList());
      _lastSentMissingRequestTimeStamp = Util.getTimeStamp();
    } else {
      final badVersions = _db.findUnavailableSyncingVersions();
      if(badVersions.isNotEmpty) { // Impossible
        MyLogger.warn('_tryToMerge: bad versions: $badVersions');
        CallbackRegistry.showToast('Find bad versions, could not merge');
        return;
      }
      MyLogger.info('_tryToMerge: store syncing versions to db');
      _storeSyncingVersionsToDb(localDagMap);
      MyLogger.info('_tryToMerge: try to merge versions');
      controller.mergeVersionTree();
      MyLogger.info('_tryToMerge: clear syncing tables');
      clearSyncingTasks();
    }
  }

  void _storeVersionToSyncDb(List<VersionNode> versionDag) {
    for(var node in versionDag) {
      String versionHash = node.versionHash;
      String parents = DocUtils.buildParents(node.parents);
      int timestamp = node.createdAt;
      if(_db.getVersionData(versionHash) == null && _db.getSyncingVersionData(versionHash) == null) {
        _db.storeSyncingVersion(versionHash, parents, timestamp, Constants.createdFromPeer, ModelConstants.statusWaiting);
      }
    }
  }

  Map<String, DagNode> _genVersionMapFromSyncingDb() {
    var _allVersions = _db.getAllSyncingVersions();
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
  Set<DagNode> _findWaitingOrMissingVersions(Map<String, DagNode> map) {
    /// Check whether every version in map:
    /// 1. Whether it exists in versions table
    /// 2. Whether it's status is available
    ///   2.1. If yes, that means this version is ready, skip it
    ///   2.2. If not, recursively check whether any object(including doc and block) in version is missing
    ///     2.2.1. If missing, add to missing list
    ///     2.2.2. If not missing, set the status of version to be available
    Set<DagNode> missing = {};
    for(final e in map.entries) {
      if(missing.length >= 2) { // Don't send too many missing versions at once
        break;
      }
      final node = e.value;
      if(node.status == ModelConstants.statusAvailable) { // Skip available versions
        continue;
      }
      final versionHash = e.key;
      final localObject = _db.getObject(versionHash);
      final syncingObject = _db.getSyncingObject(versionHash);
      if(localObject == null && syncingObject == null) {
        missing.add(node);
        continue;
      }
      final versionObject = localObject ?? syncingObject;
      if(_hasMissingObject(versionObject)) { // Check whether any object in version is missing
        missing.add(node);
      } else { // If no missing object, set the status of version to be available
        node.status = ModelConstants.statusAvailable;
        _db.updateSyncingVersionStatus(versionHash, ModelConstants.statusAvailable);
      }
    }
    final totalCount = map.length;
    int availableCount = 0;
    for(final e in map.entries) {
      final node = e.value;
      if(node.status == ModelConstants.statusAvailable) {
        availableCount++;
      }
    }
    MyLogger.info('_findWaitingOrMissingVersions: progress: $availableCount / $totalCount');
    _progress = (availableCount / totalCount * 100).toInt();
    return missing;
  }

  bool _hasMissingObject(ObjectDataModel? versionObject) {
    if(versionObject == null) return false; // Impossible
    
    final json = versionObject.data;
    final versionContent = VersionContent.fromJson(jsonDecode(json));
    final dependingObjects = DocUtils.genDependingObjects(versionContent, _db, findSyncingObject: true);

    for(final e in dependingObjects.entries) {
      final objHash = e.key;
      final obj = _db.getObject(objHash)?? _db.getSyncingObject(objHash);
      if(obj == null) return true;
    }
    return false;
  }

  int _storeResourcesToSyncDb(List<UnsignedResource> resources) {
    int addedResourceCount = 0;
    for(var res in resources) {
      String key = res.key;
      int timestamp = res.timestamp;
      String content = res.data;
      if(!_db.hasObject(key) && !_db.hasSyncingObject(key)) {
        _db.storeSyncingObject(key, content, timestamp, Constants.createdFromPeer);
        addedResourceCount++;
      }
    }
    return addedResourceCount;
  }

  void _storeSyncingVersionsToDb(Map<String, DagNode> map) {
    _db.storeFromSyncingTables();
  }
}