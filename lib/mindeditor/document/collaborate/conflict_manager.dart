import 'package:mesh_note/mindeditor/document/collaborate/merge_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';

class ConflictManager {
  DocContent baseDoc;

  ConflictManager({
    required this.baseDoc,
  });

  (List<TransformOperation>, List<ContentConflict>) mergeOperations(DocContent doc1, int timestamp1, DocContent doc2, int timestamp2) {
    TransformManager tm1 = TransformManager(baseContent: baseDoc, createdAt: timestamp1);
    var operations1 = tm1.findTransformOperations(doc1);
    TransformManager tm2 = TransformManager(baseContent: baseDoc, createdAt: timestamp2);
    var operations2 = tm2.findTransformOperations(doc2);

    var totalOperations = [...operations1, ...operations2];
    List<ContentConflict> conflicts = [];
    var opMap = _buildOperationMap(totalOperations);
    _mergeTransformOperations(totalOperations, opMap, conflicts);
    return (totalOperations, conflicts);
  }

  DocContent mergeDocument(List<TransformOperation> operations) {
    var contents = baseDoc.contents;
    for(var op in operations) {
      if(!op.isValid()) continue; // Skip deleted operation
      if(op.parentId != null) {
        MyLogger.warn('mergeDocument: parent of all nodes must be null in current version!!');
      }

      switch(op.type) {
        case TransformType.add:
          int idx = _findIndexOf(contents, op.previousId);
          var newBlock = DocContentItem(blockId: op.targetId, blockHash: op.data!);
          contents.insert(idx + 1, newBlock);
          break;
        case TransformType.del:
          int idx = _findIndexOf(contents, op.targetId);
          contents.removeAt(idx);
          break;
        case TransformType.move:
          int idx = _findIndexOf(contents, op.targetId);
          var node = contents.removeAt(idx);
          int newIdx = _findIndexOf(contents, op.previousId);
          contents.insert(newIdx + 1, node);
          break;
        case TransformType.modify:
          int idx = _findIndexOf(contents, op.targetId);
          var node = contents[idx];
          node.blockHash = op.data!;
          break;
      }
    }
    return DocContent(contents: contents);
  }

  Map<String, List<TransformOperation>> _buildOperationMap(List<TransformOperation> operations) {
    var result = <String, List<TransformOperation>>{};
    for(var item in operations) {
      String contentId = item.targetId;
      var ops = result[contentId];
      if(ops == null) {
        ops = <TransformOperation>[];
        result[contentId] = ops;
      }
      ops.add(item);
      if(ops.length > 2) {
        MyLogger.warn('Count of operations on target(id=$contentId) is too large: $ops');
      }
    }
    return result;
  }

  void _mergeTransformOperations(List<TransformOperation> operations, Map<String, List<TransformOperation>> map, List<ContentConflict> conflicts) {
    for(var thisOp in operations) {
      if(!thisOp.isValid()) continue;

      String targetId = thisOp.targetId;
      var opList = map[targetId];
      if(opList == null) continue;
      for(var thatOp in opList) {
        if(thatOp == thisOp) continue;
        if(!thatOp.isValid()) continue;

        // Now we have thisOP and thatOp with the same targetId
        switch(thisOp.type) {
          case TransformType.add:
            switch(thatOp.type) {
              case TransformType.add:
                if(thisOp.data != thatOp.data || thisOp.parentId != thatOp.parentId || thisOp.previousId != thatOp.previousId) {
                  MyLogger.warn('Conflict transform operations! Add($thisOp) <==> Add($thatOp)');
                }
                _leaveLatestOperation(thisOp, thatOp); // Leave only the latest add, even if title/data/parentId/previousId are all identity
                break;
              case TransformType.del:
              case TransformType.move:
              case TransformType.modify:
                MyLogger.warn('Impossible transform operations! Add($thisOp) <==> $thatOp');
                thatOp.setInvalid();
                break;
            }
            break;
          case TransformType.move:
            switch(thatOp.type) {
              case TransformType.move:
                MyLogger.warn('Conflict transform operations! Move($thisOp) <==> Move($thatOp)');
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TransformType.del:
                MyLogger.warn('Conflict transform operations! Move($thisOp) <==> Del($thatOp)');
                thatOp.setInvalid();
                break;
              case TransformType.add:
                MyLogger.warn('Impossible transform operations! Move($thisOp) <==> Add($thatOp)');
                thisOp.setInvalid();
                break;
              case TransformType.modify:
                // Compatible, do nothing
                break;
            }
            break;
          case TransformType.del:
            switch(thatOp.type) {
              case TransformType.move:
              case TransformType.modify:
                MyLogger.warn('Conflict transform operations! Del($thisOp) <==> $thatOp');
                thisOp.setInvalid();
                break;
              case TransformType.del:
                _leaveLatestOperation(thisOp, thatOp); // Compatible, only leave one
                break;
              case TransformType.add:
                MyLogger.warn('Impossible transform operations! Del($thisOp) <==> Add($thatOp)');
                thisOp.setInvalid();
                break;
            }
            break;
          case TransformType.modify:
            if(thisOp.data == null) {
              thisOp.setInvalid();
              continue;
            }
            switch(thatOp.type) {
              case TransformType.modify:
                if(thisOp.data != thatOp.data) {
                  MyLogger.warn('Conflict transform operations! Modify($thisOp) <==> Del($thatOp)');
                  //TODO should merge block here, if a good solution is found
                }
                _leaveLatestOperation(thisOp, thatOp);
                break;
              case TransformType.del:
                MyLogger.warn('Conflict transform operations! Modify($thisOp) <==> Del($thatOp)');
                thatOp.setInvalid();
                break;
              case TransformType.move:
                // Compatible, do nothing
                break;
              case TransformType.add:
                MyLogger.warn('Impossible transform operations! Modify($thisOp) <==> Add($thatOp)');
                thisOp.setInvalid();
                break;
            }
            break;
        }
      }
    }
  }
  void _leaveLatestOperation(TransformOperation thisOp, TransformOperation thatOp) {
    if(thisOp.timestamp < thatOp.timestamp) {
      thisOp.setInvalid();
    } else {
      thatOp.setInvalid();
    }
  }
  int _findIndexOf(List<DocContentItem> table, String? contentId) {
    if(contentId == null) {
      return -1;
    }
    for(int idx = 0; idx < table.length; idx++) {
      if(table[idx].blockId == contentId) {
        return idx;
      }
    }
    return -1;
  }
}

class ContentTreeNode {
  String? contentId;
  String? data;
  ContentTreeNode? parent;
  ContentTreeNode? previousSibling, nextSibling;
  ContentTreeNode? firstChild, lastChild;

  ContentTreeNode({
    this.contentId,
    this.data,
    this.parent,
    this.previousSibling,
    this.nextSibling,
    this.firstChild,
    this.lastChild,
  });
}

enum TransformType {
  add,
  del,
  move,
  modify,
}

class TransformOperation {
  String targetId;
  TransformType type;
  String? data;
  String? parentId;
  String? previousId;
  int timestamp;
  bool _isValid = true;

  TransformOperation({
    required this.targetId,
    required this.type,
    required this.timestamp,
    this.data,
    this.parentId,
    this.previousId,
  });

  bool isValid() => _isValid;
  void setInvalid() {
    _isValid = false;
  }
}

class TransformManager {
  DocContent baseContent;
  int createdAt;

  TransformManager({
    required this.baseContent,
    required this.createdAt,
  });

  List<TransformOperation> findTransformOperations(DocContent targetContent) {
    var (rootBase, mapBase) = _buildContentTree(baseContent);
    var (rootTarget, mapTarget) = _buildContentTree(targetContent);

    List<TransformOperation> operations = [];
    List<ContentTreeNode> deleteList = _recursiveFindTransformOperations(rootTarget.firstChild, mapTarget, rootBase.firstChild, mapBase, operations);
    for(var item in deleteList) {
      _recursiveGenerateDeleteOperations(item, operations);
    }
    return operations;
  }

  (ContentTreeNode, Map<String?, ContentTreeNode>) _buildContentTree(DocContent doc) {
    ContentTreeNode root = ContentTreeNode();
    Map<String?, ContentTreeNode> map = {
      null: root,
    };

    _recursiveBuildContentTreeNode(root, doc.contents, map); // Build root and map recursively
    return (root, map);
  }
  void _recursiveBuildContentTreeNode(ContentTreeNode parent, List<DocContentItem> nodes, Map<String?, ContentTreeNode> map) {
    ContentTreeNode? lastNode;
    for(var item in nodes) {
      final blockId = item.blockId;
      final blockHash = item.blockHash;
      final children = item.children;
      ContentTreeNode node = ContentTreeNode(
        contentId: blockId,
        data: blockHash,
        parent: parent,
        previousSibling: lastNode,
      );
      map[blockId] = node;
      parent.firstChild ??= node;
      lastNode?.nextSibling = node;
      lastNode = node;
      if(children.isNotEmpty) {
        _recursiveBuildContentTreeNode(node, children, map);
      }
    }
    parent.lastChild = lastNode;
  }

  /// Recursively find transform operations between target and base.
  /// Returns a list of nodes that should be deleted in base.
  List<ContentTreeNode> _recursiveFindTransformOperations(
      ContentTreeNode? targetNode, Map<String?, ContentTreeNode> targetMap,
      ContentTreeNode? baseNode, Map<String?, ContentTreeNode> baseMap,
      List<TransformOperation> operations) {

    List<ContentTreeNode> deleteList = [];
    String? lastNodeId;
    while(targetNode != null && baseNode != null) {
      final targetId = targetNode.contentId!;
      final baseId = baseNode.contentId!;
      if(targetId == baseId) { // With same ID, maybe modify
        if(targetNode.data != baseNode.data) {
          var op = TransformOperation(type: TransformType.modify, targetId: targetId, data: targetNode.data, timestamp: createdAt);
          operations.add(op);
          baseNode.data = targetNode.data;
        }
        var deletedInChild = _recursiveFindTransformOperations(targetNode.firstChild, targetMap, baseNode.firstChild, baseMap, operations);
        deleteList.addAll(deletedInChild);

        targetNode = targetNode.nextSibling;
        baseNode = baseNode.nextSibling;
      } else { // IDs are different in the same position, maybe move or add or del
        if(!targetMap.containsKey(baseId)) { // Should be deleted, add del operation, no need to build recursively
          var op = TransformOperation(type: TransformType.del, targetId: baseId, timestamp: createdAt);
          operations.add(op);
          var nextBaseNode = baseNode.nextSibling;
          _deleteNode(baseNode, baseMap, deleteList);

          baseNode = nextBaseNode;
          continue;
        }
        if(baseMap.containsKey(targetId)) { // Should be moved, add move operation and wait for next round to check whether need to modify, and recursively analyze children node
          var toBeMoved = baseMap[targetId]!;
          var op = TransformOperation(type: TransformType.move, targetId: targetId, parentId: targetNode.parent?.contentId, previousId: lastNodeId, timestamp: createdAt);
          operations.add(op);
          _moveNodeToReplace(toBeMoved, baseNode);

          baseNode = toBeMoved;
          continue;
        }
        // Should be added, insert add operation, and build children recursively
        var op = TransformOperation(
          type: TransformType.add,
          targetId: targetId,
          parentId: targetNode.parent?.contentId,
          previousId: lastNodeId,
          data: targetNode.data,
          timestamp: createdAt,
        );
        operations.add(op);
        targetNode = targetNode.nextSibling;
      }
      lastNodeId = targetId;
    }
    while(targetNode != null) {
      var op = TransformOperation(
        type: TransformType.add,
        data: targetNode.data,
        targetId: targetNode.contentId!,
        parentId: targetNode.parent?.contentId,
        previousId: lastNodeId,
        timestamp: createdAt,
      );
      operations.add(op);
      lastNodeId = targetNode.contentId;
      targetNode = targetNode.nextSibling;
    }
    // Move remaining base nodes to toBeDeleted list.
    _insertToDeleteList(deleteList, baseNode);
    return deleteList;
  }

  void _deleteNode(ContentTreeNode toBeDeleted, Map<String?, ContentTreeNode> map, List<ContentTreeNode> remainingList) {
    /// 1. Remove toBeDeleted from tree
    /// 2. Remove toBeDeleted from map
    /// 3. Add all children of toBeDeleted to remainingList
    // step 1
    _pickOutFromTree(toBeDeleted);
    // step 2
    String contentId = toBeDeleted.contentId!;
    map.remove(contentId);
    // step 3
    var child = toBeDeleted.firstChild;
    _insertToDeleteList(remainingList, child);
  }

  void _moveNodeToReplace(ContentTreeNode toBeMove, ContentTreeNode toBeReplace) {
    /// 1. Remove toBeMove from tree
    /// 2. Insert toBeMove in front of toBeReplace
    ///   2.1 update previous sibling
    ///   2.2 update next sibling
    /// 3. If toBeReplace is the first child of its parent, update parent's first child
    _pickOutFromTree(toBeMove);
    var previousSibling = toBeReplace.previousSibling;
    var parent = toBeReplace.parent;
    toBeMove.previousSibling = previousSibling;
    previousSibling?.nextSibling = toBeMove;
    toBeMove.nextSibling = toBeReplace;
    toBeReplace.previousSibling = toBeMove;
    if(parent != null && parent.firstChild == toBeReplace) {
      parent.firstChild = toBeMove;
    }
  }

  void _pickOutFromTree(ContentTreeNode node) {
    /// 1. Remove from parent
    ///   1.1 if it is the first child, make parent's first child to be its next sibling
    ///   1.2 if it is the last child, make parent's last child to be its previous sibling
    /// 2 Remove from sibling
    ///   2.1 if it has previous sibling, make previous sibling's next sibling to be its next sibling
    ///   2.2 if it has next sibling, make next sibling's previous sibling to be its previous sibling
    var parent = node.parent;
    var previousSibling = node.previousSibling;
    var nextSibling = node.nextSibling;
    // step 1.1
    if(parent != null) {
      if(parent.lastChild == node) {
        parent.lastChild = node.previousSibling;
      }
      if(parent.firstChild == node) {
        parent.firstChild = node.nextSibling;
      }
    }
    // step 1.2
    if(previousSibling != null) {
      previousSibling.nextSibling = nextSibling;
    }
    if(nextSibling != null) {
      nextSibling.previousSibling = previousSibling;
    }
  }

  void _insertToDeleteList(List<ContentTreeNode> deleteList, ContentTreeNode? node) {
    if(node == null) return;

    while(node != null) {
      deleteList.add(node);
      node.parent = null;
      node = node.nextSibling;
    }
  }

  void _recursiveGenerateDeleteOperations(ContentTreeNode remainingNodes, List<TransformOperation> operations) {
    ContentTreeNode? node = remainingNodes;
    while(node != null) {
      var op = TransformOperation(targetId: node.contentId!, type: TransformType.del, timestamp: createdAt);
      operations.add(op);
      if(node.firstChild != null) {
        _recursiveGenerateDeleteOperations(node.firstChild!, operations);
      }
      node = node.nextSibling;
    }
  }
}