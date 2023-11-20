import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data.dart';

class VersionManager {
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
    DagNode? resultNode = findCommonAncestor(verNode1, verNode2);
    return resultNode?.versionHash??'';
  }

  /// Find common ancestor of dag1 and dag2
  ///
  /// TODO: Should optimize the algorithm and support multiple parents
  DagNode? findCommonAncestor(DagNode dag1, DagNode dag2) {
    DagNode node = dag1;
    while(true) {
      DagNode? found = _findNodeInDag(node, dag2);
      if(found != null) {
        return found;
      }
      if(dag1.parents.isEmpty) break;
      node = dag1.parents[0];
    }
    return null;
  }

  /// Traverse dag to find target
  ///
  /// TODO: Should optimize the algorithm and support multiple parents
  DagNode? _findNodeInDag(DagNode target, DagNode dag) {
    while(true) {
      if(target == dag) {
        return target;
      }
      if(dag.parents.isEmpty) break;
      dag = dag.parents[0];
    }
    return null;
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
}

class DagNode {
  String versionHash;
  List<DagNode> parents;

  DagNode({
    required this.versionHash,
    required this.parents,
  });
}