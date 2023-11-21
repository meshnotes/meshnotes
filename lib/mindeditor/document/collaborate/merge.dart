import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data.dart';
import 'package:my_log/my_log.dart';

class VersionManager {
  static const String _tags = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  final DbHelper? _db;

  VersionManager({
    DbHelper? db,
  }): _db = db;

  String recursiveGetAncestors(String version1, String version2) {
    var _versionMap = _genVersionMap();
    var verNode1 = _versionMap[version1];
    var verNode2 = _versionMap[version2];
    if(verNode1 == null || verNode2 == null) {
      return '';
    }
    DagNode? resultNode = findNearestCommonAncestor([verNode1, verNode2], _versionMap);
    return resultNode?.versionHash??'';
  }

  /// Find the nearest common ancestor
  /// 1. clear visited tag of all nodes
  /// 2. Visit node 0, 1, 2, ..., n, and mark tag 0, 1, 2, ..., x
  /// 3. Find all nodes that ha all tags(that means these nodes are common nodes)
  /// 4. Find all nodes that has no child(that means they are "nearest") in step 3
  ///
  /// Result:
  /// - If the result is a single node, that is the common ancestor
  /// - If there are multiple results, do it again
  /// - If the result is null, that means some nodes are missing, or deleted. Just returns it
  DagNode? findNearestCommonAncestor(List<DagNode> nodes, Map<String, DagNode> entireMap) {
    while(true) {
      if (nodes.length > _tags.length) { // Should not happen here
        MyLogger.warn('findNearestCommonAncestor: Shit! not enough tag for this DAG!!!');
        return null;
      }
      for (var e in entireMap.entries) {
        e.value.clearTag();
        e.value.clearHasTaggedChild();
      }
      int tagIndex = 0;
      String targetTag = '';
      for (var item in nodes) {
        var tag = _tags.substring(tagIndex, tagIndex + 1);
        targetTag += tag;
        _visitNode(item, tag);
        tagIndex += 1;
      }
      Set<DagNode> resultSet = {};
      for (var item in nodes) {
        _labelHasTaggedChild(item, targetTag);
        var commonAncestors = _findFirstNodesWithTag(item, targetTag);
        if(commonAncestors.isEmpty) {
          MyLogger.debug('findNearestCommonAncestor: common ancestors from node(${item.versionHash}) is empty');
        } else {
          MyLogger.debug('findNearestCommonAncestor: common ancestors from node(${item.versionHash}): ${commonAncestors.join(", ")}');
        }
        resultSet.addAll(commonAncestors);
        break;
      }
      // Not found
      if (resultSet.isEmpty) {
        return null;
      }
      // Find one result, that's it
      if (resultSet.length == 1) {
        return resultSet.first;
      }
      // Find multiple result, make the result as the source list, and do it again
      MyLogger.info('findNearestCommonAncestor: find multiple results: $resultSet, try again');
      nodes = resultSet.toList();
    }
  }

  Map<String, DagNode> _genVersionMap() {
    List<VersionData> _allVersions = _db!.getAllVersions();
    // Generate version map
    Map<String, DagNode> _map = {};
    for(var item in _allVersions) {
      final versionHash = item.versionHash;
      var ver = DagNode(versionHash: versionHash, parents: []);
      _map[versionHash] = ver;
    }
    // Generate version parents pointer
    for(var item in _allVersions) {
      final versionHash = item.versionHash;
      final parents = _splitParents(item.parents);
      final currentNode = _map[versionHash]!;
      for(var item in parents) {
        var parentNode = _map[item];
        if(parentNode == null) continue;
        currentNode.parents.add(parentNode);
      }
    }
    return _map;
  }
  List<String> _splitParents(String parents) {
    List<String> _sp = parents.split(',');
    return _sp;
  }

  void _visitNode(DagNode root, String tag) {
    if(root.hasTag(tag)) return;

    root.appendTag(tag);
    for(var p in root.parents) {
      _visitNode(p, tag);
    }
  }
  void _labelHasTaggedChild(DagNode root, String tag) {
    if(root.hasTag(tag)) {
      for(var item in root.parents) {
        item.setHasTagggedChild();
      }
    }
    for(var item in root.parents) {
      _labelHasTaggedChild(item, tag);
    }
  }
  List<DagNode> _findFirstNodesWithTag(DagNode root, String tag) {
    if(root.hasTag(tag) && root.notHasTaggedChild()) {
      return [root];
    }
    List<DagNode> result = [];
    for(var item in root.parents) {
      result.addAll(_findFirstNodesWithTag(item, tag));
    }
    return result;
  }
}

class DagNode {
  String versionHash;
  List<DagNode> parents;
  bool _hasTaggedChild = false;
  String _visitedTag = '';

  DagNode({
    required this.versionHash,
    required this.parents,
  });

  void clearTag() {
    _visitedTag = '';
  }
  void appendTag(String t) {
    _visitedTag += t;
  }
  bool hasTag(String t) {
    return _visitedTag.contains(t);
  }

  void clearHasTaggedChild() {
    _hasTaggedChild = false;
  }
  void setHasTagggedChild() {
    _hasTaggedChild = true;
  }
  bool hasTaggedChild() {
    return _hasTaggedChild;
  }
  bool notHasTaggedChild() {
    return !hasTaggedChild();
  }

  @override
  String toString() {
    return versionHash;
  }
}