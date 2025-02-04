import 'package:my_log/my_log.dart';
import '../dal/doc_data_model.dart';

class VersionManager {
  static const String _tags = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// Find the nearest common ancestor
  /// 1. clear visited tag of all nodes
  /// 2. Visit node 0, 1, 2, ..., n, and mark tag 0, 1, 2, ..., x
  /// 3. Find all nodes that has all tags(that means these nodes are ancestors of all target nodes, in another word, the common ancestors)
  /// 4. Find all nodes that has no child(that means they are "nearest") in step 3
  ///
  /// Result:
  /// - If the result is a single node, that is the common ancestor
  /// - If there are multiple results, do it again
  /// - If the result is null, just return null, which means use empty as common ancestor(Maybe some nodes are missing or deleted or
  /// deprecated)
  DagNode? findNearestCommonAncestor(List<DagNode> targetNodes, Map<String, DagNode> entireMap) {
    while(true) {
      if (targetNodes.length > _tags.length) { // Should never happen here
        MyLogger.warn('findNearestCommonAncestor: Shit! not enough tags for this DAG!!!, nodes.length=${targetNodes.length}');
        return null;
      }
      // Step 1: Clear visited tags
      for (var e in entireMap.entries) {
        // Every target node has a tag, for example, target node A has 1.
        // If a node in the DAG map has the tag 1, that means this node is ancestor of node A, or it's node A itself.
        // When we have to find the common ancestors of node A(tag 0) and node B(tag 1), we just need to find the nodes with tag "01"
        // So the purpose of tag is to find all common ancestors of target nodes
        e.value.clearTag();
        // If a node has "has tagged child" tag, that means at least one of its children is one of common ancestors.
        // So itself is also one of the common ancestors.
        // If a node has tag "01", but without "has tagged child" tag, that means this node is the nearest common ancestor.
        e.value.clearHasTaggedChild();
      }
      int tagIndex = 0;
      // targetTag is a string that contains all tags. For example, there are two leaf nodes, then their corresponding tags are 0 and 1.
      // Then the mission of this method is to find the first node that contains tag "01"
      String targetTag = '';
      // Step 2: For every child nodes, visit all its ancestors
      for (var item in targetNodes) {
        var tag = _tags.substring(tagIndex, tagIndex + 1);
        targetTag += tag;
        _visitNode(item, tag);
        tagIndex += 1;
      }
      Set<DagNode> resultSet = {};
      for (var item in targetNodes) {
        //TODO Should optimize here, to avoid visit nodes repeatedly
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
      targetNodes = resultSet.toList();
    }
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
        item.setHasTaggedChild();
      }
    }
    for(var item in root.parents) {
      _labelHasTaggedChild(item, tag);
    }
  }
  List<DagNode> _findFirstNodesWithTag(DagNode root, String tag) {
    if(root.hasTag(tag) && root.notHasTaggedChild() && root.isAvailable()) {
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
  int createdAt;
  List<DagNode> parents;
  bool _hasTaggedChild = false;
  String _visitedTag = '';
  int status;

  DagNode({
    required this.versionHash,
    required this.createdAt,
    this.status = ModelConstants.statusAvailable,
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
  void setHasTaggedChild() {
    _hasTaggedChild = true;
  }
  bool hasTaggedChild() {
    return _hasTaggedChild;
  }
  bool notHasTaggedChild() {
    return !hasTaggedChild();
  }

  bool isAvailable() {
    return status == ModelConstants.statusAvailable;
  }

  @override
  String toString() {
    return versionHash;
  }
}