import 'dart:convert';
import 'package:libp2p/application/application_api.dart';
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
  static const int _mergeInterval = 15000; // 15 seconds
  final DbHelper _db;
  final Controller controller = Controller();
  int _lastCheckTimeStamp = 0;

  MergeTask({required DbHelper db}): _db = db {
    controller.eventTasksManager.addTimerTask('mergeTask', () {
      check();
    }, _mergeInterval);
  }

  void check() {
    int now = Util.getTimeStamp();
    if(now - _lastCheckTimeStamp < _mergeInterval) return; // Not enough time passed, do nothing
    _lastCheckTimeStamp = now;

    if(!_db.hasSyncingVersion()) return; // No syncing version, do nothing

    _tryToMerge();
  }

  void addVersionTree(List<VersionNode> dag) {
    _storeVersionToSyncDb(dag);
    _tryToMerge();
  }

  void addResources(List<UnsignedResource> resources) {
    _storeResourcesToSyncDb(resources);
    _tryToMerge();
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
    if(missingVersions.isNotEmpty) { //TODO: Ignore some missing versions after too many retries
      MyLogger.info('_tryToMerge: missing versions: $missingVersions');
      controller.sendRequireVersions(missingVersions.map((node) => node.versionHash).toList());
    } else {
      MyLogger.info('_tryToMerge: store syncing versions to db');
      _storeSyncingVersionsToDb(localDagMap);
      MyLogger.info('_tryToMerge: try to merge versions');
      controller.mergeVersionTree();
      MyLogger.info('_tryToMerge: clear syncing tables');
      _db.clearSyncingTables();
    }
  }

  void _storeVersionToSyncDb(List<VersionNode> versionDag) {
    for(var node in versionDag) {
      String versionHash = node.versionHash;
      String parents = DocUtils.buildParents(node.parents);
      int timestamp = node.createdAt;
      if(_db.getSyncingVersionData(versionHash) == null) {
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
      final versionHash = e.key;
      final node = e.value;
      final localObject = _db.getObject(versionHash);
      final syncingObject = _db.getSyncingObject(versionHash);
      if(localObject == null && syncingObject == null) {
        missing.add(node);
        continue;
      }
      if(node.status == ModelConstants.statusAvailable) { // Skip available versions
        continue;
      }
      final versionObject = localObject ?? syncingObject;
      if(_hasMissingObject(versionObject)) { // Check whether any object in version is missing
        missing.add(node);
      } else {
        _db.updateSyncingVersionStatus(versionHash, ModelConstants.statusAvailable);
      }
    }
    return missing;
  }

  bool _hasMissingObject(ObjectDataModel? versionObject) {
    if(versionObject == null) return false; // Impossible
    
    final json = versionObject.data;
    final versionContent = VersionContent.fromJson(jsonDecode(json));
    final requiredObjects = DocUtils.genRequiredObjects(versionContent, _db, findSyncingObject: true);

    for(final e in requiredObjects.entries) {
      final objHash = e.key;
      final obj = _db.getObject(objHash)?? _db.getSyncingObject(objHash);
      if(obj == null) return true;
    }
    return false;
  }

  void _storeResourcesToSyncDb(List<UnsignedResource> resources) {
    for(var res in resources) {
      String key = res.key;
      int timestamp = res.timestamp;
      String content = res.data;
      if(!_db.hasObject(key) && !_db.hasSyncingObject(key)) {
        _db.storeSyncingObject(key, content, timestamp, Constants.createdFromPeer);
      }
    }
  }

  void _storeSyncingVersionsToDb(Map<String, DagNode> map) {
    _db.storeFromSyncingTables();
  }
}