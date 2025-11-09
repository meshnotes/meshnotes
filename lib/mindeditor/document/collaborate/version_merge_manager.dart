import 'package:keygen/keygen.dart';
import 'package:mesh_note/mindeditor/document/collaborate/diff_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';

import 'find_operation_types.dart';

class MergeManager {
  VersionContent? baseVersion;

  MergeManager({
    required this.baseVersion,
  });

  /// Merge two operations and return the conflicts
  /// 1. Generate operations map to accelerate computation, the key is the id
  /// 2. Traverse operations set 1
  ///   2.1. find all operations based on the key
  ///   2.2 Add operation
  ///     2.2.1 conflicts to another add operation, unless it has the same title, and hash, and parent, and previous node
  ///       2.2.1.1 use the latest one
  ///     2.2.2 del/move/modify are not possible
  ///   2.3 Move operation
  ///     2.3.1 conflicts to another move operation, unless it has the same parent and previous node
  ///       2.3.1.1 use the latest one
  ///     2.3.2 conflicts to del operation
  ///       2.3.2.1 use the latest one
  ///     2.3.3 compatible to modify operation
  ///     2.3.4 add is not possible
  ///   2.4 Del operation
  ///     2.4.1 conflicts to move/modify operations
  ///       2.4.1.1 use the latest one
  ///     2.4.2 compatible to del operation
  ///     2.4.3 add is not possible
  ///   2.5 Modify operation
  ///     2.5.1 conflicts to another modify operation, unless it has the same hash
  ///       2.5.1.1 use the merge content algorithm
  ///     2.5.2 conflicts to del operation
  ///       2.5.2.1 use the latest one
  ///     2.5.3 compatible to move operations
  ///     2.5.4 add is not possible
  /// 3. Return all operations and conflicts
  (List<TreeOperation>, List<ContentConflict>) mergeOperationsAndFileConflicts(DiffOperations op1, DiffOperations op2) {
    var totalOperations = <TreeOperation>[...op1.operations, ...op2.operations];
    var opMap = _buildOperationsMap(totalOperations);

    final conflicts =_findConflicts(totalOperations, opMap);
    return (totalOperations, conflicts);
  }

  List<ContentConflict> _findConflicts(List<TreeOperation> totalOperations, Map<String, List<TreeOperation>> opMap) {
    List<ContentConflict> conflicts = [];
    for(var thisOp in totalOperations) {
      if(thisOp.isFinished()) continue;

      String targetId = thisOp.id;
      var opList = opMap[targetId];
      if(opList == null) continue;
      for(var thatOp in opList) { // Find all operations on the same node
        if(thatOp == thisOp) continue;
        if(thatOp.isFinished()) continue;

        // Now we have thisOP and thatOp with the same targetId
        switch(thisOp.type) {
          case TreeOperationType.add:
            switch(thatOp.type) {
              case TreeOperationType.add:
                if(thisOp.newData != thatOp.newData || thisOp.parentId != thatOp.parentId || thisOp.previousId != thatOp.previousId) {
                  MyLogger.warn('Conflict operations! Add($thisOp) <==> Add($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp); // Leave only the latest add, even if title/data/parentId/previousId are all identity
                break;
              case TreeOperationType.del:
                MyLogger.warn('Impossible operations! Add($thisOp) <==> Del($thatOp)');
                thatOp.setFinished();
                break;
              case TreeOperationType.move:
                MyLogger.warn('Impossible operations! Add($thisOp) <==> Move($thatOp)');
                thatOp.setFinished();
                break;
              case TreeOperationType.modify:
                MyLogger.warn('Impossible operations! Add($thisOp) <==> Modify($thatOp)');
                thatOp.setFinished();
                break;
            }
            break;
          case TreeOperationType.move:
            switch(thatOp.type) {
              case TreeOperationType.add:
                MyLogger.warn('Impossible operations! Move($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.del:
                MyLogger.warn('Conflict operations! Move($thisOp) <==> Del($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.move:
                if(thisOp.parentId != thatOp.parentId || thisOp.previousId != thatOp.previousId) {
                  MyLogger.warn('Conflict operations! Move($thisOp) <==> Move($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.modify:
                // Compatible, do nothing
                break;
            }
            break;
          case TreeOperationType.del:
            switch(thatOp.type) {
              case TreeOperationType.add:
                MyLogger.warn('Impossible operations! Del($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.del:
                _leaveLatestOperation(thisOp, thatOp); // Compatible, only leave one
                break;
              case TreeOperationType.move:
                MyLogger.warn('Conflict operations! Del($thisOp) <==> Move($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.modify:
                MyLogger.warn('Conflict operations! Del($thisOp) <==> Modify($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
            }
            break;
          case TreeOperationType.modify:
            if(thisOp.newData == null) {
              thisOp.setFinished();
              continue;
            }
            switch(thatOp.type) {
              case TreeOperationType.add:
                MyLogger.warn('Impossible operations! Modify($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.del:
                MyLogger.warn('Conflict operations! Modify($thisOp) <==> Del($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.move:
                // Compatible, do nothing
                break;
              case TreeOperationType.modify:
                if(thatOp.newData == null) {
                  thatOp.setFinished();
                  continue;
                }
                if(thisOp.newData != thatOp.newData) { // Two versions modify the same document, should use document merge
                  MyLogger.warn('Version conflict: Find conflicts between $thisOp and $thatOp');
                  var baseHash = _findBaseHash(targetId);
                  if(baseHash == null) {
                    MyLogger.warn('Data incorrect! base hash should not be null if there are modification conflict!! target_id=$targetId, base_version=$baseVersion');
                    continue;
                  }
                  var conflict = ContentConflict(
                    targetId: targetId,
                    originalHash: baseHash,
                    conflictHash1: thisOp.newData!,
                    conflictHash2: thatOp.newData!,
                    timestamp1: thisOp.timestamp,
                    timestamp2: thatOp.timestamp,
                  );
                  conflicts.add(conflict);
                  thisOp.setFinished();
                  thatOp.setFinished();
                } else {
                  _leaveLatestOperation(thisOp, thatOp); // If two operations' data are identical, leave any one shall be OK
                }
                break;
            }
            break;
        }
      }
    }
    return conflicts;
  }

  Map<String, List<TreeOperation>> _buildOperationsMap(List<TreeOperation> opList) {
    var result = <String, List<TreeOperation>>{};
    for(var item in opList) {
      String contentId = item.id;
      var ops = result[contentId];
      if(ops == null) {
        ops = [];
        result[contentId] = ops;
      }
      ops.add(item);
    }
    return result;
  }

  void _leaveLatestOperation(TreeOperation thisOp, thatOp) {
    if(thisOp.timestamp < thatOp.timestamp) {
      thisOp.setFinished();
    } else {
      thatOp.setFinished();
    }
  }

  VersionContent mergeVersions(List<TreeOperation> operations, List<String> parents) {
    var table = baseVersion?.table?? [];
    for(var op in operations) {
      if(op.isFinished()) continue; // Skip deleted operation

      switch(op.type) {
        case TreeOperationType.add:
          int idx = _findIndexOf(table, op.parentId, op.previousId);
          var newNode = VersionContentItem(docId: op.id, docHash: op.newData!, updatedAt: op.timestamp, parentDocId: op.parentId);
          table.insert(idx + 1, newNode);
          break;
        case TreeOperationType.del:
          int idx = _findIndexOf(table, op.parentId, op.id);
          table.removeAt(idx);
          break;
        case TreeOperationType.move:
          int idx = _findIndexOf(table, op.parentId, op.id);
          var node = table.removeAt(idx);
          int newIdx = _findIndexOf(table, op.parentId, op.previousId);
          node.updatedAt = op.timestamp;
          node.parentDocId = op.parentId; // Update parent relationship
          table.insert(newIdx + 1, node);
          break;
        case TreeOperationType.modify:
          int idx = _findIndexOf(table, op.parentId, op.id);
          var node = table[idx];
          node.docHash = op.newData!;
          node.updatedAt = op.timestamp;
          break;
      }
    }
    int now = Util.getTimeStamp();
    return VersionContent(table: table, timestamp: now, parentsHash: parents);
  }

  int _findIndexOf(List<VersionContentItem> table, String? parentId, targetId) {
    // Both parent and previous id are null, that means it's the first node
    if(parentId == null && targetId == null) {
      return -1;
    }
    // If contentId is null, use parentId. Because it's the first child of this parent. Otherwise, find the target id directly
    targetId ??= parentId;
    for(int idx = 0; idx < table.length; idx++) {
      if(table[idx].docId == targetId) {
        return idx;
      }
    }
    return -1;
  }

  String? _findBaseHash(String targetId) {
    if(baseVersion == null) return null;

    for(var item in baseVersion!.table) {
      if(item.docId == targetId) {
        return item.docHash;
      }
    }
    return null;
  }
}

class ContentConflict {
  String targetId;
  String originalHash;
  String conflictHash1;
  String conflictHash2;
  int timestamp1;
  int timestamp2;

  ContentConflict({
    required this.targetId,
    required this.originalHash,
    required this.conflictHash1,
    required this.conflictHash2,
    required this.timestamp1,
    required this.timestamp2,
  });

  @override
  String toString() {
    return 'ContentConflict(targetId=$targetId, originalHash=${HashUtil.formatHash(originalHash)}, conflictHash1=${HashUtil.formatHash(conflictHash1)}, conflictHash2=${HashUtil.formatHash(conflictHash2)}, timestamp1=$timestamp1, timestamp2=$timestamp2)';
  }
}