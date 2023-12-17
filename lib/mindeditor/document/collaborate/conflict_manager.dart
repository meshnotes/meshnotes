import 'package:mesh_note/mindeditor/document/doc_content.dart';

class ConflictManager {
  DocContent baseDoc;

  ConflictManager({
    required this.baseDoc,
  });

  DocContent genNewDocument(DocContent doc1, DocContent doc2) {
    TransformManager tm = TransformManager();
    var operations1 = tm.findTransformOperations(doc1, baseDoc);
    var operations2 = tm.findTransformOperations(doc2, baseDoc);

    // var totalOperations = _solveConflicts(operations1, operations2);
    // var newDoc = _generateNewDocument(baseDoc, totalOperations);
    // return newDoc;
    return DocContent();
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

  TransformOperation({
    required this.targetId,
    required this.type,
    this.data,
    this.parentId,
    this.previousId,
  });
}

class TransformManager {
  List<TransformOperation> findTransformOperations(DocContent targetContent, DocContent baseContent) {
    var (rootBase, mapBase) = _buildContentTree(baseContent);
    var (rootTarget, mapTarget) = _buildContentTree(targetContent);

    List<TransformOperation> operations = [];
    List<ContentTreeNode> deleteList = _recursiveFindTransformOperations(rootTarget.firstChild, mapTarget, rootBase.firstChild, mapBase, operations);
    for(var item in deleteList) {
      _recursiveGenerateDeleteOperations(item, operations);
    }
    // while(baseNode != null) {
    //   var op = TransformOperation(type: TransformType.del, targetId: baseNode.contentId!);
    //   operations.add(op);
    //   baseNode = baseNode.nextSibling;
    // }
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
          var op = TransformOperation(type: TransformType.modify, targetId: targetId, data: targetNode.data);
          operations.add(op);
          baseNode.data = targetNode.data;
        }
        var deletedInChild = _recursiveFindTransformOperations(targetNode.firstChild, targetMap, baseNode.firstChild, baseMap, operations);
        deleteList.addAll(deletedInChild);

        targetNode = targetNode.nextSibling;
        baseNode = baseNode.nextSibling;
      } else { // IDs are different in the same position, maybe move or add or del
        if(!targetMap.containsKey(baseId)) { // Should be deleted, add del operation, no need to build recursively
          var op = TransformOperation(type: TransformType.del, targetId: baseId);
          operations.add(op);
          var nextBaseNode = baseNode.nextSibling;
          _deleteNode(baseNode, baseMap, deleteList);

          baseNode = nextBaseNode;
          continue;
        }
        if(baseMap.containsKey(targetId)) { // Should be moved, add move operation and wait for next round to check whether need to modify, and recursively analyze children node
          var toBeMoved = baseMap[targetId]!;
          var op = TransformOperation(type: TransformType.move, targetId: targetId, parentId: targetNode.parent?.contentId, previousId: lastNodeId);
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
        );
        operations.add(op);
        targetNode = targetNode.nextSibling;
      }
      lastNodeId = targetId;
    }
    while(targetNode != null) {
      var op = TransformOperation(
        type: TransformType.add,
        targetId: targetNode.contentId!,
        parentId: targetNode.parent?.contentId,
        previousId: lastNodeId,
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
    var nextSibling = toBeReplace.nextSibling;
    var parent = toBeReplace.parent;
    if(previousSibling != null) {
      previousSibling.nextSibling = toBeMove;
      toBeMove.previousSibling = previousSibling;
    }
    if(nextSibling != null) {
      nextSibling.previousSibling = toBeMove;
      toBeMove.nextSibling = nextSibling;
    }
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

    deleteList.add(node);
    while(node != null) {
      node.parent = null;
      node = node.nextSibling;
    }
  }

  void _recursiveGenerateDeleteOperations(ContentTreeNode remainingNodes, List<TransformOperation> operations) {
    ContentTreeNode? node = remainingNodes;
    while(node != null) {
      var op = TransformOperation(targetId: node.contentId!, type: TransformType.del);
      operations.add(op);
      if(node.firstChild != null) {
        _recursiveGenerateDeleteOperations(node.firstChild!, operations);
      }
      node = node.nextSibling;
    }
  }
}