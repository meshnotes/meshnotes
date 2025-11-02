import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'find_operation_types.dart';
import 'find_operations.dart';

class DiffOperations {
  String versionHash;
  List<TreeOperation> operations;
  // VersionContent versionContent;

  DiffOperations({
    // required this.versionContent,
    required this.operations,
    required this.versionHash,
  });

  factory DiffOperations.fromVersionContent(VersionContent versionContent) {
    List<TreeOperation> operations = [];
    String? lastNodeId;
    int timestamp = versionContent.timestamp;
    for(var item in versionContent.table) {
      var op = TreeOperation(
        type: TreeOperationType.add,
        id: item.docId,
        parentId: item.parentDocId,
        previousId: lastNodeId,
        newData: item.docHash,
        timestamp: timestamp,
      );
      operations.add(op);
      lastNodeId = item.docId;
    }
    return DiffOperations(operations: operations, versionHash: versionContent.getHash());
  }
}


class ContentNode {
  String contentId;
  String contentHash;
  String? parentId;
  String? previousId;
  int updatedAt;

  ContentNode({
    required this.contentId,
    required this.contentHash,
    this.parentId,
    this.previousId,
    required this.updatedAt,
  });
}
class DiffManager {
  /// Find diff operations to convert from version2 to version1
  /// 0. If version2 is empty, return operations of version1
  /// 1. Convert contents of version1 and 2 from list to map
  /// 2. Label nodes with operations in version1
  ///   2.1 If any item appears in version1 but not in version2, that's added
  ///   2.2 If any item appears in version2 but not in version1, that's deleted
  ///   2.3 If any item appears both in version1 and version2
  ///     2.3.1 but with different parent or previous node, that's moved
  ///     2.3.3 but with different hash, that's modified
  ///     2.3.4 the operations above may occur at the same time
  ///   2.4 Otherwise, the content does not change
  /// 3. Only leave add/delete/move/rename/modify operations
  DiffOperations findDifferentOperation(VersionContent targetVersion, VersionContent? baseVersion) {
    if(baseVersion == null) {
      return DiffOperations.fromVersionContent(targetVersion);
    }

    final targetVersionTimestamp = targetVersion.timestamp; // Use for delete operation to determine the timestamp
    var targetList = _convertToContentNodes(targetVersion);
    var baseList = _convertToContentNodes(baseVersion);
    final operations = findOperations(baseList, targetList, targetVersionTimestamp);
    return DiffOperations(operations: operations, versionHash: targetVersion.getHash());
  }

  List<FlatResource> _convertToContentNodes(VersionContent contentVersion) {
    var list = <FlatResource>[];
    String? previousNodeId;
    String? lastParentId;
    for(var item in contentVersion.table) {
      var docId = item.docId;
      var docHash = item.docHash;
      var timestamp = item.updatedAt;
      if(item.parentDocId != lastParentId) { // If parentId is changed, that means it's the first child of previous node, so reset previousNodeId
        previousNodeId = null;
      }
      var resource = FlatResource(id: docId, content: docHash, parentId: item.parentDocId, previousId: previousNodeId, updatedAt: timestamp);
      list.add(resource);
      previousNodeId = docId;
      lastParentId = item.parentDocId;
    }
    return list;
  }
}