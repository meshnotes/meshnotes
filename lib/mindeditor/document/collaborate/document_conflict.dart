import 'package:mesh_note/mindeditor/document/collaborate/version_merge_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';
import 'find_operation_types.dart';
import 'find_operations.dart';

class DocumentConflictManager {
  DocContent baseDoc;

  DocumentConflictManager({
    required this.baseDoc,
  });

  (List<TreeOperation>, List<ContentConflict>) mergeDocumentOperations(DocContent doc1, int timestamp1, DocContent doc2, int timestamp2) {
    TransformManager tm1 = TransformManager(baseContent: baseDoc, createdAt: timestamp1);
    var operations1 = tm1.findTransformOperations(doc1);
    TransformManager tm2 = TransformManager(baseContent: baseDoc, createdAt: timestamp2);
    var operations2 = tm2.findTransformOperations(doc2);

    var totalOperations = [...operations1, ...operations2];
    var opMap = _buildOperationMap(totalOperations);
    final conflicts = _mergeTransformOperations(totalOperations, opMap);

    if(MyLogger.isDebug()) {
      MyLogger.debug('mergeDocumentOperations: operations1=$operations1');
      MyLogger.debug('mergeDocumentOperations: operations2=$operations2');
      MyLogger.debug('mergeDocumentOperations: conflicts=$conflicts');
    }
    return (totalOperations, conflicts);
  }

  DocContent mergeDocument(List<TreeOperation> operations) {
    var contents = baseDoc.contents;
    for(var op in operations) {
      if(op.isFinished()) continue; // Skip deleted operation
      // if(op.parentId != null) {
      //   MyLogger.warn('mergeDocument: parent of all nodes must be null in current version!!');
      // }

      switch(op.type) {
        case TreeOperationType.add:
          var newBlock = DocContentItem(blockId: op.id, blockHash: op.newData!, updatedAt: op.timestamp);
          _insertIntoTreeContent(contents, op.parentId, op.previousId, newBlock);
          break;
        case TreeOperationType.del:
          _removeFromTreeContent(contents, op.id);
          break;
        case TreeOperationType.move:
          final node = _removeFromTreeContent(contents, op.id);
          if(node != null) _insertIntoTreeContent(contents, op.parentId, op.previousId, node);
          break;
        case TreeOperationType.modify:
          final (siblings, node) = _findNodeInTreeContent(contents, op.id);
          if(node != null) {
            node.blockHash = op.newData!;
          }
          break;
      }
    }
    return DocContent(contents: contents);
  }

  Map<String, List<TreeOperation>> _buildOperationMap(List<TreeOperation> operations) {
    var result = <String, List<TreeOperation>>{};
    for(var item in operations) {
      String contentId = item.id;
      var ops = result[contentId];
      if(ops == null) {
        ops = <TreeOperation>[];
        result[contentId] = ops;
      }
      ops.add(item);
      if(ops.length > 2) {
        MyLogger.warn('Count of operations on target(id=$contentId) is too large: $ops');
      }
    }
    return result;
  }

  List<ContentConflict> _mergeTransformOperations(List<TreeOperation> operations, Map<String, List<TreeOperation>> map) {
    List<ContentConflict> conflicts = [];
    for(var thisOp in operations) {
      if(thisOp.isFinished()) continue;

      String targetId = thisOp.id;
      var opList = map[targetId];
      if(opList == null) continue;
      for(var thatOp in opList) {
        if(thatOp == thisOp) continue;
        if(thatOp.isFinished()) continue;

        // Now we have thisOP and thatOp with the same targetId
        switch(thisOp.type) {
          case TreeOperationType.add:
            switch(thatOp.type) {
              case TreeOperationType.add:
                if(thisOp.newData != thatOp.newData || thisOp.parentId != thatOp.parentId || thisOp.previousId != thatOp.previousId) {
                  MyLogger.warn('Conflict transform operations! Add($thisOp) <==> Add($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp); // Leave only the latest add, even if title/data/parentId/previousId are all identity
                break;
              case TreeOperationType.del:
              case TreeOperationType.move:
              case TreeOperationType.modify:
                MyLogger.warn('Impossible transform operations! Add($thisOp) <==> $thatOp');
                thatOp.setFinished();
                break;
            }
            break;
          case TreeOperationType.move:
            switch(thatOp.type) {
              case TreeOperationType.move:
                MyLogger.warn('Conflict transform operations! Move($thisOp) <==> Move($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.del:
                MyLogger.warn('Conflict transform operations! Move($thisOp) <==> Del($thatOp)');
                thatOp.setFinished();
                break;
              case TreeOperationType.add:
                MyLogger.warn('Impossible transform operations! Move($thisOp) <==> Add($thatOp)');
                thisOp.setFinished();
                break;
              case TreeOperationType.modify:
                // Compatible, do nothing
                break;
            }
            break;
          case TreeOperationType.del:
            switch(thatOp.type) {
              case TreeOperationType.move:
              case TreeOperationType.modify:
                MyLogger.warn('Conflict transform operations! Del($thisOp) <==> $thatOp');
                thisOp.setFinished();
                break;
              case TreeOperationType.del:
                _leaveLatestOperation(thisOp, thatOp); // Compatible, only leave one
                break;
              case TreeOperationType.add:
                MyLogger.warn('Impossible transform operations! Del($thisOp) <==> Add($thatOp)');
                thisOp.setFinished();
                break;
            }
            break;
          case TreeOperationType.modify:
            if(thisOp.newData == null) {
              thisOp.setFinished();
              continue;
            }
            switch(thatOp.type) {
              case TreeOperationType.modify:
                if(thisOp.newData != thatOp.newData) {
                  MyLogger.warn('Conflict transform operations! Modify($thisOp) <==> Del($thatOp)');
                  //TODO should merge block here, if a good solution is found
                }
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TreeOperationType.del:
                MyLogger.warn('Conflict transform operations! Modify($thisOp) <==> Del($thatOp)');
                thatOp.setFinished();
                break;
              case TreeOperationType.move:
                // Compatible, do nothing
                break;
              case TreeOperationType.add:
                MyLogger.warn('Impossible transform operations! Modify($thisOp) <==> Add($thatOp)');
                thisOp.setFinished();
                break;
            }
            break;
        }
      }
    }
    return conflicts;
  }
  void _leaveLatestOperation(TreeOperation thisOp, TreeOperation thatOp) {
    if(thisOp.timestamp < thatOp.timestamp) {
      thisOp.setFinished();
    } else {
      thatOp.setFinished();
    }
  }

  /// Insert a node into the tree content, based on the parentId and previousId
  /// Returns true if inserted, false otherwise
  bool _insertIntoTreeContent(List<DocContentItem> contents, String? parentId, String? previousId, DocContentItem node) {
    // If parentId is null, must insert to the top level
    if(parentId == null) {
      if(previousId == null) {
        contents.insert(0, node);
        return true;
      }
      for(int i = 0; i < contents.length; i++) {
        if(contents[i].blockId == previousId) {
          contents.insert(i + 1, node);
          return true;
        }
      }
      return false;
    }
    // If parent is not null, recursively find the proper position to insert
    bool _recursiveInsert(List<DocContentItem> contents, String? parentId, String? previousId, DocContentItem node) {
      for(var item in contents) {
        if(item.blockId == parentId) {// Found the parent node
          // Insert at the beginning if no previousId is provided
          if(previousId == null) {
            item.children.insert(0, node);
            return true;
          }
          // Insert at the proper position
          for(int i = 0; i < item.children.length; i++) {
            if(item.children[i].blockId == previousId) {
              item.children.insert(i + 1, node);
              return true;
            }
          }
        }
        // If not found, try the children
        if(_recursiveInsert(item.children, parentId, previousId, node)) return true;
      }
      return false;
    }
    return _recursiveInsert(contents, parentId, previousId, node);
  }

  /// Remove a node from the tree content, based on the contentId
  /// Returns the removed node if found, null otherwise
  DocContentItem? _removeFromTreeContent(List<DocContentItem> contents, String contentId) {
    final (siblings, node) = _findNodeInTreeContent(contents, contentId);
    if(node != null) {
      siblings.remove(node);
      return node;
    }
    return null;
  }

  /// Find a node in the tree content, based on the contentId
  /// Returns the siblings list(may need to be updated) and the target node if found, null otherwise
  (List<DocContentItem>, DocContentItem?) _findNodeInTreeContent(List<DocContentItem> contents, String contentId) {
    (List<DocContentItem>, DocContentItem?) _recursiveFind(List<DocContentItem> siblings, String contentId) {
      for(var item in siblings) {
        if(item.blockId == contentId) {
          return (siblings, item);
        }
        // If not found, try the children
        final (s, ret) = _recursiveFind(item.children, contentId);
        if(ret != null) return (s, ret);
      }
      return ([], null);
    }
    return _recursiveFind(contents, contentId);
  }
}

class TransformManager {
  DocContent baseContent;
  int createdAt;

  TransformManager({
    required this.baseContent,
    required this.createdAt,
  });

  List<TreeOperation> findTransformOperations(DocContent targetContent) {
    var baseList = _buildContentList(baseContent);
    var targetList = _buildContentList(targetContent);
    final operations = findOperations(baseList, targetList, createdAt);
    return operations;
    // var (rootBase, mapBase) = _buildContentTree(baseContent);
    // var (rootTarget, mapTarget) = _buildContentTree(targetContent);

    // List<TreeOperation> operations = [];
    // List<ContentTreeNode> deleteList = _recursiveFindTransformOperations(rootTarget.firstChild, mapTarget, rootBase.firstChild, mapBase, operations);
    // for(var item in deleteList) {
    //   _recursiveGenerateDeleteOperations(item, operations);
    // }
    // return operations;
  }

  List<FlatResource> _buildContentList(DocContent doc) {
    var list = <FlatResource>[];
    List<FlatResource> _recursiveBuildContentList(List<DocContentItem> blocks, String? parentId) {
      var list = <FlatResource>[];
      String? previousNodeId;
      for(var block in blocks) {
        var blockId = block.blockId;
        var blockHash = block.blockHash;
        var timestamp = block.updatedAt ?? createdAt; // Old version may not contain timestamp, so use document's timestamp
        var resource = FlatResource(id: blockId, content: blockHash, parentId: parentId, previousId: previousNodeId, updatedAt: timestamp);
        list.add(resource);
        list.addAll(_recursiveBuildContentList(block.children, blockId));
        previousNodeId = blockId;
      }
      return list;
    }
    list.addAll(_recursiveBuildContentList(doc.contents, null));
    return list;
  }
}