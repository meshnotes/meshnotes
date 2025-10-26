import './find_operation_types.dart';

/// Find transform operations from base to target
/// 1. Generate maps and indexes for base and target, package them into a resource descriptor
/// 2. Find differences(added, deleted, moved, and modified) between base and target
/// 3. Convert differences to transform operations
List<TreeOperation> findOperationsByFlat(List<FlatResource> base, target, int targetTimestamp) {
  final resourceDescriptor = _generateIndexes(base, target, targetTimestamp);
  final diffDescriptor = _findDifferences(resourceDescriptor);
  final operations = _convertDifferencesToOperations(diffDescriptor, resourceDescriptor);
  return operations;
}

class _IndexGenerator {
  int _nextIndex = 1;
  final Map<String, int> _idndexMap = {};
  final Map<int, String> _reverseMap = {};

  void generateIndex(String key) {
    if(_idndexMap.containsKey(key)) {
      return;
    }
    final index = _nextIndex++;
    _idndexMap[key] = index;
    _reverseMap[index] = key;
  }

  int getIndex(String key) {
    return _idndexMap[key]!;
  }

  String? getKey(int index) {
    return _reverseMap[index];
  }
}

class _ResourceDescriptor {
  final List<FlatResource> base;
  final List<FlatResource> target;
  final int targetTimestamp;
  final Map<String, FlatResource> baseMap;
  final Map<String, FlatResource> targetMap;
  final _IndexGenerator indexGenerator;

  _ResourceDescriptor({
    required this.base,
    required this.target,
    required this.targetTimestamp,
    required this.baseMap,
    required this.targetMap,
    required this.indexGenerator,
  });
}

class _DiffDescriptor {
  final List<String> added;
  final List<String> deleted;
  final List<String> moved;
  final List<String> modified;

  _DiffDescriptor({
    required this.added,
    required this.deleted,
    required this.moved,
    required this.modified,
  });
}

// /// Convert tree structure to flat structure
// List<FlatResource> _convertToFlat(List<TreeResource> roots) {
//   final List<FlatResource> result = [];

//   void traverse(String? parentId, List<TreeResource> nodes) {
//     String? previousId;
//     for (final node in nodes) {
//       // Keep only id/content in the flattened view; children are ignored in flat
//       result.add(FlatResource(id: node.id, content: node.content, parentId: parentId, previousId: previousId, updatedAt: node.updatedAt));
//       if (node.children.isNotEmpty) {
//         traverse(node.id, node.children);
//       }
//       previousId = node.id;
//     }
//   }

//   traverse(null, roots);
//   return result;
// }

/// Find differences between target and base
/// 1. Find unchanged nodes using LIS(Longest Increasing Subsequence) algorithm
/// 2. Find added nodes and deleted nodes
/// 3. Find moved nodes
/// 4. Find modified nodes
/// 5. Return the differences
_DiffDescriptor _findDifferences(_ResourceDescriptor resourceDescriptor) {
  final oldMap = resourceDescriptor.baseMap;
  final newMap = resourceDescriptor.targetMap;
  final indexGenerator = resourceDescriptor.indexGenerator;
  final flatTarget = resourceDescriptor.target;
  // Use indexGenerator to find unchanged nodes(LIS algorithm)
  final unchanged = _findUnchangedNodes(oldMap, flatTarget, indexGenerator);

  // Use oldMap and newMap to find added and deleted nodes
  final added = _findAddedNodes(oldMap, newMap);
  final deleted = _findDeletedNodes(oldMap, newMap);

  final (moved, modified) = _findModifiedNodes(oldMap, newMap, unchanged);

  return _DiffDescriptor(added: added, deleted: deleted, moved: moved, modified: modified);
}

/// Returns index map, old key map, and new key map
_ResourceDescriptor _generateIndexes(List<FlatResource> flatBase, List<FlatResource> flatTarget, int targetTimestamp) {
  final indexGenerator = _IndexGenerator(); // Build index for each id
  Map<String, FlatResource> oldMap = {};
  Map<String, FlatResource> newMap = {};
  // Indexes of base must be in ascending order
  for(var item in flatBase) {
    indexGenerator.generateIndex(item.id);
    oldMap[item.id] = item;
  }
  // Indexes of target may not be in ascending order
  for(var item in flatTarget) {
    indexGenerator.generateIndex(item.id);
    newMap[item.id] = item;
  }
  return _ResourceDescriptor(
    base: flatBase,
    target: flatTarget,
    targetTimestamp: targetTimestamp,
    baseMap: oldMap,
    targetMap: newMap,
    indexGenerator: indexGenerator,
  );
}

/// Use LIS algorithm to find longest common node key list
/// 1. Convert key list to index list
/// 2. Find longest increasing subsequence of index list
/// 3. Convert longest increasing subsequence of index list to key list
Set<String> _findUnchangedNodes(Map<String, FlatResource> oldMap, List<FlatResource> flatTarget, _IndexGenerator indexGenerator) {
  final List<int> targetIndexes = flatTarget
      .where((item) => oldMap.containsKey(item.id)) // Only find common nodes
      .map((item) => indexGenerator.getIndex(item.id)) // Convert key to index
      .toList();
  final List<int> commonIndexes = findLongestIncreasingSubsequence(targetIndexes);
  final Set<String> commonKeys = commonIndexes.map((index) => indexGenerator.getKey(index)!).toSet();
  return commonKeys;
}

List<String> _findAddedNodes(Map<String, FlatResource> oldMap, Map<String, FlatResource> newMap) {
  return _subtract(newMap, oldMap);
}

List<String> _findDeletedNodes(Map<String, FlatResource> oldMap, Map<String, FlatResource> newMap) {
  return _subtract(oldMap, newMap);
}

List<String> _subtract(Map<String, FlatResource> map1, Map<String, FlatResource> map2) {
  final List<String> result = [];
  for(var k in map1.keys) {
    if(!map2.containsKey(k)) {
      result.add(k);
    }
  }
  return result;
}

/// `modified` includes both moved and modified nodes
/// If topological relationship is changed, it's moved
/// If content is changed, it's modified
/// A node may be both moved and modified
(List<String>, List<String>) _findModifiedNodes(Map<String, FlatResource> oldMap, Map<String, FlatResource> newMap, Set<String> unchanged) {
  final List<String> moved = [];
  final List<String> modified = [];
  for(var item in oldMap.entries) {
    final key = item.key;
    final oldNode = item.value;
    final newNode = newMap[key];
    // newNode does not exist, it's deleted, not common node
    if(newNode == null) {
      continue;
    }
    // 1. If content is different, it's modified
    if(oldNode.content != newNode.content) {
      modified.add(key);
    }
    // 2. If unchanged set does not contain this node, it has been moved
    if(!unchanged.contains(key)) {
      moved.add(key);
    } else {
      // 3. If the order is unchanged but parent is different, it's moved
      if(oldNode.parentId != newNode.parentId) {
        moved.add(key);
      }
    }
  }
  return (moved, modified);
}

List<TreeOperation> _convertDifferencesToOperations(_DiffDescriptor diffDescriptor, _ResourceDescriptor resourceDescriptor) {
  final added = diffDescriptor.added;
  final deleted = diffDescriptor.deleted;
  final moved = diffDescriptor.moved;
  final modified = diffDescriptor.modified;
  final oldMap = resourceDescriptor.baseMap;
  final newMap = resourceDescriptor.targetMap;
  final targetTimestamp = resourceDescriptor.targetTimestamp;
  List<TreeOperation> result = [];
  result.addAll(_generateAddedNodes(added, newMap));
  result.addAll(_generateDeletedNodes(deleted, targetTimestamp));
  result.addAll(_generateMovedNodes(moved, newMap));
  result.addAll(_generateModifiedNodes(modified, oldMap, newMap));
  return result;
}

List<TreeOperation> _generateAddedNodes(List<String> added, Map<String, FlatResource> map) {
  List<TreeOperation> result = [];
  for(var item in added) {
    final targetItem = map[item];
    if(targetItem == null) {
      continue;
    }
    result.add(TreeOperation(
      type: TreeOperationType.add,
      id: item,
      parentId: targetItem.parentId,
      previousId: targetItem.previousId,
      newData: targetItem.content,
      timestamp: targetItem.updatedAt,
    ));
  }
  return result;
}

List<TreeOperation> _generateDeletedNodes(List<String> deleted, int targetTimestamp) {
  List<TreeOperation> result = [];
  for(var item in deleted) {
    result.add(TreeOperation(type: TreeOperationType.del, id: item, timestamp: targetTimestamp));
  }
  return result;
}

List<TreeOperation> _generateMovedNodes(List<String> moved, Map<String, FlatResource> map) {
  List<TreeOperation> result = [];
  for(var item in moved) {
    final targetItem = map[item];
    if(targetItem == null) {
      continue;
    }
    result.add(TreeOperation(
      type: TreeOperationType.move,
      id: item,
      parentId: targetItem.parentId,
      previousId: targetItem.previousId,
      timestamp: targetItem.updatedAt,
    ));
  }
  return result;
}

List<TreeOperation> _generateModifiedNodes(List<String> modified, Map<String, FlatResource> oldMap, newMap) {
  List<TreeOperation> result = [];
  for(var item in modified) {
    final oldItem = oldMap[item];
    final targetItem = newMap[item];
    if(oldItem == null || targetItem == null) {
      continue;
    }
    result.add(TreeOperation(
      type: TreeOperationType.modify,
      id: item,
      newData: targetItem.content,
      timestamp: targetItem.updatedAt,
    ));
  }
  return result;
}

List<int> findLongestIncreasingSubsequence(List<int> sequence) {
  if (sequence.isEmpty) return [];

  final List<int> tails = [];
  final List<int> tailsIndices = [];
  final List<int> previousIndex = List.filled(sequence.length, -1);

  for (int i = 0; i < sequence.length; i++) {
    final int x = sequence[i];

    int left = 0;
    int right = tails.length;
    while (left < right) {
      final int mid = (left + right) >> 1;
      if (tails[mid] < x) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }

    if (left == tails.length) {
      tails.add(x);
      tailsIndices.add(i);
    } else {
      tails[left] = x;
      tailsIndices[left] = i;
    }

    previousIndex[i] = left > 0 ? tailsIndices[left - 1] : -1;
  }

  final int longestLength = tails.length;
  final List<int> result = List.filled(longestLength, 0);
  int k = tailsIndices[longestLength - 1];
  for (int i = longestLength - 1; i >= 0; i--) {
    result[i] = sequence[k];
    k = previousIndex[k];
  }

  return result;
}