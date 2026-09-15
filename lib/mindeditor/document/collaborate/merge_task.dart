import 'dart:convert';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import '../dal/db_helper.dart';
import '../dal/doc_data_model.dart';
import '../doc_content.dart';
import '../doc_utils.dart';
import 'version_manager.dart';

enum MissingObjectType { version, document, block }

class MissingObject {
  final String hash;
  final MissingObjectType type;

  const MissingObject({required this.hash, required this.type});
}

class MergeTask {
  static const int _checkInterval = 15000; // 15 seconds
  static const int _sendMissingRequestInterval = 120000; // 2 minutes
  final DbHelper _db;
  final Controller controller = Controller();
  final void Function(List<String>) _sendRequireVersions;
  int _lastCheckTimeStamp = 0;
  int _lastSentMissingRequestTimeStamp = 0;
  int _progress = 0;
  final Map<String, MissingObject> _missingObjects = {};

  MergeTask({required DbHelper db, void Function(List<String>)? sendRequireVersions}):
        _db = db,
        _sendRequireVersions = sendRequireVersions?? Controller().sendRequireVersions {
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
    final addedResources = _storeResourcesToSyncDb(resources);
    if(addedResources.isNotEmpty) { // If no new resource added, do nothing
      _lastSentMissingRequestTimeStamp = 0;
      _tryToMerge(addedResources: addedResources);
    }
  }

  void clearSyncingTasks() {
    _db.clearSyncingTables();
    _missingObjects.clear();
    _progress = 0;
    controller.eventTasksManager.triggerUpdateSyncing(false, 0);
  }

  /// 1. Find missing objects, if any, request up to two and exit
  /// 2. If all objects are available, start to merge
  ///   2.1. Store sync_* tables to db
  ///   2.2. Try to merge versions
  ///   2.3. Clear sync_* tables if merge success
  void _tryToMerge({List<String>? addedResources}) {
    MyLogger.info('_tryToMerge: start to merge');
    Map<String, DagNode> localDagMap = _genVersionMapFromSyncingDb();
    _findWaitingOrMissingVersions(localDagMap);
    _removeAvailableObjectsFromMissingObjects(addedResources?? []);
    if(_missingObjects.isNotEmpty) { //TODO: Ignore some missing objects after too many retries, unless it's needed by the leaf version
      final hashes = _takeProperMissingHashes(2, 50);
      MyLogger.info('_tryToMerge: missing objects: $hashes');
      _sendRequireVersions(hashes);
      _lastSentMissingRequestTimeStamp = Util.getTimeStamp();
    } else {
      for(final node in localDagMap.values) {
        if(node.status == ModelConstants.statusAvailable) continue;
        node.status = ModelConstants.statusAvailable;
        _db.updateSyncingVersionStatus(node.versionHash, ModelConstants.statusAvailable);
      }
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
      _enqueueMissingObject(versionHash, MissingObjectType.version);
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

  _findWaitingOrMissingVersions(Map<String, DagNode> map) {
    /// Check whether every version in map:
    /// 1. Whether it exists in versions table
    /// 2. Whether its status is available
    ///   2.1. If yes, that means this version is ready, skip it
    ///   2.2. If not, recursively check whether any object(including doc and block) in version is missing
    ///     2.2.1. If missing, add to missing list and enqueue the version for staged object discovery
    ///     2.2.2. If not missing, set the status of version to be available
    for(final e in map.entries) {
      final node = e.value;
      if(node.status == ModelConstants.statusAvailable) continue;

      final versionHash = e.key;
      if(_missingObjects.containsKey(versionHash)) continue;
      
      final versionObject = _db.getObject(versionHash)?? _db.getSyncingObject(versionHash);
      if(versionObject == null) {
        _enqueueMissingObject(versionHash, MissingObjectType.version);
      } else {
        final (missingDocuments, missingBlocks) = _findMissingObjects(versionObject);
        if(missingDocuments.isNotEmpty || missingBlocks.isNotEmpty) {
          _enqueueMissingObject(versionHash, MissingObjectType.version);
          for(final objHash in missingDocuments) {
            _enqueueMissingObject(objHash, MissingObjectType.document);
          }
          for(final objHash in missingBlocks) {
            _enqueueMissingObject(objHash, MissingObjectType.block);
          }
        } else {
          node.status = ModelConstants.statusAvailable;
          _db.updateSyncingVersionStatus(versionHash, ModelConstants.statusAvailable);
        }
      }
    }
    final totalCount = map.length;
    final availableCount = map.values.where((node) => node.status == ModelConstants.statusAvailable).length;
    MyLogger.info('_findWaitingOrMissingVersions: progress: $availableCount / $totalCount');
    if(totalCount == 0) {
      _progress = 100;
    } else {
      _progress = (availableCount / totalCount * 100).toInt();
    }
  }

  (Set<String>, Set<String>) _findMissingObjects(ObjectDataModel versionObject) {
    final missingDocuments = <String>{};
    final missingBlocks = <String>{};
    final versionContent = VersionContent.fromJson(jsonDecode(versionObject.data));
    final (dependingDocuments, dependingBlocks) = DocUtils.genDependingObjects(versionContent, _db, findSyncingObject: true);
    for(final objHash in dependingDocuments.keys) {
      final object = _db.getObject(objHash)?? _db.getSyncingObject(objHash);
      if(object == null) missingDocuments.add(objHash);
    }
    for(final objHash in dependingBlocks.keys) {
      final object = _db.getObject(objHash)?? _db.getSyncingObject(objHash);
      if(object == null) missingBlocks.add(objHash);
    }
    return (missingDocuments, missingBlocks);
  }

  void _enqueueMissingObject(String hash, MissingObjectType type) {
    _missingObjects.putIfAbsent(hash, () => MissingObject(hash: hash, type: type));
  }

  /// Try to consume new coming resources to update the missing objects list
  /// If no new coming resources, try to traverse all the missing objects
  /// Only remove available objects.
  /// New missing objects will be added in the previous _findWaitingOrMissingVersions() method.
  void _removeAvailableObjectsFromMissingObjects(List<String> newComingResources) {
    final toBeDeleted = <String>[];
    if(newComingResources.isNotEmpty) {
      for(final hash in newComingResources) {
        final m = _missingObjects[hash];
        if(m != null) toBeDeleted.add(hash);
      }
    } else {
      for(final item in _missingObjects.values) {
        final object = _db.getObject(item.hash)?? _db.getSyncingObject(item.hash);
        if(object == null) continue;

        // The missing object is available now
        // So calculate the related objects of it, and remove it from the missing objects list
        final key = item.hash;
        toBeDeleted.add(key);
      }
    }
    for(final key in toBeDeleted) {
      _missingObjects.remove(key);
    }
  }

  /// Take maxObjectCount normal objects at maximum.
  /// But version objects are much larger, so only take maxVersionCount version objects.
  List<String> _takeProperMissingHashes(int maxVersionCount, int maxObjectCount) {
    final missing = _missingObjects.values.take(maxObjectCount).toList();
    final result = <String>[];
    int versionCount = 0;
    for(final m in missing) {
      result.add(m.hash);
      if(m.type == MissingObjectType.version) {
        versionCount++;
        if(versionCount >= maxVersionCount) break;
      }
    }
    return result;
  }

  void _enqueueBlocks(List<DocContentItem> blocks) {
    for(final block in blocks) {
      _enqueueMissingObject(block.blockHash, MissingObjectType.block);
      _enqueueBlocks(block.children);
    }
  }

  List<String> _storeResourcesToSyncDb(List<UnsignedResource> resources) {
    final addedResources = <String>[];
    for(var res in resources) {
      String key = res.key;
      int timestamp = res.timestamp;
      String content = res.data;
      if(!_db.hasObject(key) && !_db.hasSyncingObject(key)) {
        _db.storeSyncingObject(key, content, timestamp, Constants.createdFromPeer);
        addedResources.add(key);
      }
    }
    return addedResources;
  }

  void _storeSyncingVersionsToDb(Map<String, DagNode> map) {
    _db.storeFromSyncingTables();
  }
}
