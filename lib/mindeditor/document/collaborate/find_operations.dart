import './find_operation_types.dart';

/// Find transform operations from base to target
/// 1. Convert base and target to flat structure
/// 2. Find differences between target and base
/// 3. Convert diff to transform operations
List<TreeOperation> findOperations(List<TreeResource> base, List<TreeResource> target) {
  final flatBase = _convertToFlat(base);
  final flatTarget = _convertToFlat(target);
  final (indexGenerator, oldMap, newMap) = _generateIndexes(flatBase, flatTarget);

  final (added, deleted, moved, modified) = findDifferences(flatBase, flatTarget, oldMap, newMap, indexGenerator);

  final operations = _convertDifferencesToOperations(added, deleted, moved, modified, oldMap, newMap);
  
  return operations;
}

class FlatResource {
  final String id;
  final String content;
  final String? parentId;
  final String? previousId;

  const FlatResource({
    required this.id,
    required this.content,
    required this.parentId,
    required this.previousId,
  });
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

/// Convert tree structure to flat structure
List<FlatResource> _convertToFlat(List<TreeResource> roots) {
  final List<FlatResource> result = [];

  void traverse(String? parentId, List<TreeResource> nodes) {
    String? previousId;
    for (final node in nodes) {
      // Keep only id/content in the flattened view; children are ignored in flat
      result.add(FlatResource(id: node.id, content: node.content, parentId: parentId, previousId: previousId));
      if (node.children.isNotEmpty) {
        traverse(node.id, node.children);
      }
      previousId = node.id;
    }
  }

  traverse(null, roots);
  return result;
}

/// Find differences between target and base
/// 1. Find unchanged nodes using LIS(Longest Increasing Subsequence) algorithm
/// 2. Find added nodes and deleted nodes
/// 3. Find moved nodes
/// 4. Find modified nodes
/// 5. Return the differences
(List<String>, List<String>, List<String>, List<String>) 
findDifferences(List<FlatResource> flatBase, List<FlatResource> flatTarget, Map<String, FlatResource> oldMap, Map<String, FlatResource> newMap, _IndexGenerator indexGenerator) {

  // Use indexGenerator to find unchanged nodes(LIS algorithm)
  final unchanged = _findUnchangedNodes(oldMap, flatTarget, indexGenerator);

  // Use oldMap and newMap to find added and deleted nodes
  final added = _findAddedNodes(oldMap, newMap);
  final deleted = _findDeletedNodes(oldMap, newMap);

  final (moved, modified) = _findModifiedNodes(oldMap, newMap, unchanged);

  return (added, deleted, moved, modified);
}

/// Returns index map, old key map, and new key map
(_IndexGenerator, Map<String, FlatResource>, Map<String, FlatResource>) _generateIndexes(List<FlatResource> flatBase, List<FlatResource> flatTarget) {
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
  return (indexGenerator, oldMap, newMap);
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

List<TreeOperation> _convertDifferencesToOperations(List<String> added, deleted, moved, modified, Map<String, FlatResource> oldMap, newMap) {
  List<TreeOperation> result = [];
  result.addAll(_generateAddedNodes(added, newMap));
  result.addAll(_generateDeletedNodes(deleted, newMap));
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
    result.add(TreeOperation(type: TreeOperationType.add, id: item, parentId: targetItem.parentId, previousId: targetItem.previousId));
  }
  return result;
}

List<TreeOperation> _generateDeletedNodes(List<String> deleted, Map<String, FlatResource> map) {
  List<TreeOperation> result = [];
  for(var item in deleted) {
    result.add(TreeOperation(type: TreeOperationType.del, id: item));
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
    result.add(TreeOperation(type: TreeOperationType.move, id: item, parentId: targetItem.parentId, previousId: targetItem.previousId));
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
    result.add(TreeOperation(type: TreeOperationType.modify, id: item, originalData: oldItem.content, newData: targetItem.content));
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