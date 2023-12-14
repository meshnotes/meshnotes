import 'package:mesh_note/mindeditor/document/collaborate/diff_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';

class MergeManager {
  VersionContent? baseVersion;

  MergeManager({
    required this.baseVersion,
  });

  /// Merge two operations and solve the conflicts
  /// 1. Generate operations map to accelerate computation, the key is the id
  /// 2. Traverse operations set 1
  ///   2.1. find all operations based on the key
  ///   2.2 Add operation
  ///     2.2.1 conflicts to another add operation, unless it has the same title, and hash, and parent, and previous node
  ///       2.2.1.1 use the latest one
  ///     2.2.2 del/move/rename/modify are not possible
  ///   2.3 Move operation
  ///     2.3.1 conflicts to another move operation, unless it has the same parent and previous node
  ///       2.3.1.1 use the latest one
  ///     2.3.2 conflicts to del operation
  ///       2.3.2.1 use the latest one
  ///     2.3.3 compatible to rename or modify operation
  ///     2.3.4 add is not possible
  ///   2.4 Del operation
  ///     2.4.1 conflicts to move/rename/modify operations
  ///       2.4.1.1 use the latest one
  ///     2.4.2 compatible to del operation
  ///     2.4.3 add is not possible
  ///   2.5 Rename operation
  ///     2.5.1 conflicts to another rename operation, unless it has the same title
  ///       2.5.1.1 use the latest one
  ///     2.5.2 conflicts to del operation
  ///       2.5.2.1 use the latest one
  ///     2.5.3 compatible to move or modify operation
  ///     2.5.4 add is not possible
  ///   2.6 Modify operation
  ///     2.6.1 conflicts to another modify operation, unless it has the same hash
  ///       2.6.1.1 use the merge content algorithm
  ///     2.6.2 conflicts to del operation
  ///       2.6.2.1 use the latest one
  ///     2.6.3 compatible to move/rename operations
  ///     2.6.4 add is not possible
  VersionContent merge(DiffOperations op1, DiffOperations op2) {
    var totalOperations = <ContentOperation>[...op1.operations, ...op2.operations];
    var opMap = _buildOperationsMap(totalOperations);

    _mergeOperations(totalOperations, opMap);
    var versionContent = _buildVersionContentFromOperations(baseVersion, totalOperations, [op1.versionHash, op2.versionHash]);
    return versionContent;
  }

  void _mergeOperations(List<ContentOperation> totalOperations, Map<String, List<ContentOperation>> opMap) {
    for(var thisOp in totalOperations) {
      if(!thisOp.isValid()) continue;

      String targetId = thisOp.targetId;
      var opList = opMap[targetId];
      if(opList == null) continue;
      for(var thatOp in opList) {
        if(thatOp == thisOp) continue;
        if(!thatOp.isValid()) continue;

        // Now we have thisOP and thatOp with the same targetId
        switch(thisOp.operation) {
          case ContentOperationType.add:
            switch(thatOp.operation) {
              case ContentOperationType.add:
                if(thisOp.title != thatOp.title || thisOp.data != thatOp.data || thisOp.parentId != thatOp.parentId || thisOp.previousId != thatOp.previousId) {
                  MyLogger.warn('Conflict operations! Add($thisOp) <==> Add($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp); // Leave only the latest add, even if title/data/parentId/previousId are all identity
                break;
              case ContentOperationType.del:
              case ContentOperationType.move:
              case ContentOperationType.rename:
              case ContentOperationType.modify:
                MyLogger.warn('Impossible operations! Add($thisOp) <==> $thatOp');
                _leaveLatestOperation(thisOp, thatOp);
                break;
            }
            break;
          case ContentOperationType.move:
            switch(thatOp.operation) {
              case ContentOperationType.move:
                MyLogger.warn('Conflict operations! Move($thisOp) <==> Move($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.del:
                MyLogger.warn('Conflict operations! Move($thisOp) <==> Del($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.add:
                MyLogger.warn('Impossible operations! Move($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.rename:
              case ContentOperationType.modify:
                // Compatible, do nothing
                break;
            }
            break;
          case ContentOperationType.del:
            switch(thatOp.operation) {
              case ContentOperationType.move:
              case ContentOperationType.rename:
              case ContentOperationType.modify:
                MyLogger.warn('Conflict operations! Del($thisOp) <==> $thatOp');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.del:
                _leaveLatestOperation(thisOp, thatOp); // Compatible, only leave one
                break;
              case ContentOperationType.add:
                MyLogger.warn('Impossible operations! Del($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
            }
            break;
          case ContentOperationType.rename:
            switch(thatOp.operation) {
              case ContentOperationType.rename:
                if(thisOp.title != thatOp.title) {
                  MyLogger.warn('Conflict operations! Rename($thisOp) <==> Rename($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.del:
                MyLogger.warn('Conflict operations! Rename($thisOp) <==> Del($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.move:
              case ContentOperationType.modify:
                // Compatible, do nothing
                break;
              case ContentOperationType.add:
                MyLogger.warn('Impossible operations! Rename($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
            }
            break;
          case ContentOperationType.modify:
            switch(thatOp.operation) {
              case ContentOperationType.modify:
                if(thisOp.data != thatOp.data) {
                  MyLogger.warn('Conflict operations! Modify($thisOp) <==> Modify($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp); // TODO: Should be fixed here!!! Should merge content instead of using latest one
                break;
              case ContentOperationType.del:
                MyLogger.warn('Conflict operations! Modify($thisOp) <==> Del($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case ContentOperationType.move:
              case ContentOperationType.rename:
                // Compatible, do nothing
                break;
              case ContentOperationType.add:
                MyLogger.warn('Impossible operations! Modify($thisOp) <==> Add($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
            }
            break;
        }
      }
    }
  }

  Map<String, List<ContentOperation>> _buildOperationsMap(List<ContentOperation> opList) {
    var result = <String, List<ContentOperation>>{};
    for(var item in opList) {
      String contentId = item.targetId;
      var ops = result[contentId];
      if(ops == null) {
        ops = <ContentOperation>[];
        result[contentId] = ops;
      }
      ops.add(item);
    }
    return result;
  }

  void _leaveLatestOperation(ContentOperation thisOp, ContentOperation thatOp) {
    if(thisOp.timestamp < thatOp.timestamp) {
      thisOp.setInvalid();
    } else {
      thatOp.setInvalid();
    }
  }

  VersionContent _buildVersionContentFromOperations(VersionContent? baseVersion, List<ContentOperation> operations, List<String> parents) {
    var table = baseVersion?.table?? [];
    int now = Util.getTimeStamp();
    for(var op in operations) {
      if(!op.isValid()) continue; // Skip deleted operation

      switch(op.operation) {
        case ContentOperationType.add:
          int idx = _findIndexOf(table, op.previousId);
          var newNode = VersionContentItem(docId: op.targetId, docHash: op.data!, title: op.title!, updatedAt: now);
          table.insert(idx + 1, newNode);
          break;
        case ContentOperationType.del:
          int idx = _findIndexOf(table, op.targetId);
          table.removeAt(idx + 1);
          break;
        case ContentOperationType.move:
          int idx = _findIndexOf(table, op.targetId);
          var node = table.removeAt(idx);
          int newIdx = _findIndexOf(table, op.previousId);
          node.updatedAt = now;
          table.insert(newIdx, node);
          break;
        case ContentOperationType.rename:
          int idx = _findIndexOf(table, op.targetId);
          var node = table[idx];
          node.title = op.title!;
          node.updatedAt = now;
          break;
        case ContentOperationType.modify:
          int idx = _findIndexOf(table, op.targetId);
          var node = table[idx];
          node.docHash = op.data!;
          node.updatedAt = now;
          break;
      }
    }
    return VersionContent(table: table, timestamp: now, parentsHash: parents);
  }

  int _findIndexOf(List<VersionContentItem> table, String? contentId) {
    if(contentId == null) {
      return -1;
    }
    for(int idx = 0; idx < table.length; idx++) {
      if(table[idx].docId == contentId) {
        return idx;
      }
    }
    return 0;
  }
}