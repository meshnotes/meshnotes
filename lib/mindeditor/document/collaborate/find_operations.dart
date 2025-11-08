import './find_operation_types.dart';

/// Find transform operations from base to target
/// 1. Generate maps and indexes for base and target, package them into a resource descriptor
/// 2. Find differences(added, deleted, moved, and modified) between base and target
/// 3. Convert differences to transform operations
List<TreeOperation> findOperations(List<FlatResource> base, target, int targetTimestamp) {
  final resourceDescriptor = _generateIndexes(base, target, targetTimestamp);
  final operations = _generateOperations(resourceDescriptor);
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

/// Find differences between target and base
/// 1. Find unchanged nodes using LIS(Longest Increasing Subsequence) algorithm
/// 2. Find transform operations from base to target using the unchanged nodes
/// 3. Return the differences
List<TreeOperation> _generateOperations(_ResourceDescriptor resourceDescriptor) {
  final oldMap = resourceDescriptor.baseMap;
  final newMap = resourceDescriptor.targetMap;
  final indexGenerator = resourceDescriptor.indexGenerator;
  final flatTarget = resourceDescriptor.target;
  final flatBase = resourceDescriptor.base;
  // Use indexGenerator to find unchanged nodes(LIS algorithm)
  final unchangedSet = _findUnchangedNodes(oldMap, flatTarget, indexGenerator);

  return _findOperations(flatTarget, flatBase, newMap, oldMap, unchangedSet);
}

/// Find operations transform from flatTarget to flatBase
/// For each node in target list(flatTarget)
/// 1. If the node is unchanged
///   1.1 If the node's data is different, it's modified
///   1.2 If the node's parent(only check the parent is adequate) is different, it's moved
///   1.3 Otherwise, it's unchanged
/// 2. If the node is not in base list(flatBase), it's added
/// 3. If the node is in base list(flatBase)
///   3.1 If the node's data is different, it's modified
///   3.2 If the node's parent or previous node is different, it's moved
/// 4. Find the deleted nodes(in the base list but not in the target list)
List<TreeOperation> _findOperations(List<FlatResource> flatTarget, flatBase, Map<String, FlatResource> newMap, oldMap, Set<String> unchanged) {
  List<TreeOperation> result = [];
  for(var item in flatTarget) {
    final oldItem = oldMap[item.id];
    // 1. Unchanged nodes are skipped
    if(unchanged.contains(item.id)) {
      if(oldItem != null) {
        if(oldItem.content != item.content) {
          _addModifiedOperation(result, item);
        }
        if(oldItem.parentId != item.parentId) {
          _addMovedOperation(result, item);
        }
      }
      continue;
    }
    if(!oldMap.containsKey(item.id)) {
      // 2. If the node is not in base list, it's added
      _addAddedOperation(result, item);
    } else {
      if(oldItem == null) {
        continue;
      }
      // 3.1 Modified node
      if(oldItem.content != item.content) {
        _addModifiedOperation(result, item);
      }
      // 3.2 Moved node
      if(oldItem.parentId != item.parentId || oldItem.previousId != item.previousId) {
        _addMovedOperation(result, item);
      }
      // If the node is moved, but the parent and previous node are not changed, it could have a move operation, but not necessary.
      // It depends on the original architecture: tree or flat.
      // 1. For tree node, this node may moved with the parent node, so move operation is not necessary.
      // 2. For flat node, this node will have same the parent id and order, so move operation is necessary either.
    }
  }
  // 4. Deleted nodes
  _addDeletedOperations(result, oldMap, newMap);
  return result;
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

void _addDeletedOperations(List<TreeOperation> result, Map<String, FlatResource> oldMap, Map<String, FlatResource> newMap) {
  for(final e in oldMap.entries) {
    if(!newMap.containsKey(e.key)) {
      _addDeletedOperation(result, e.value);
    }
  }
}

void _addAddedOperation(List<TreeOperation> result, FlatResource item) {
  result.add(TreeOperation(
    type: TreeOperationType.add,
    id: item.id,
    parentId: item.parentId,
    previousId: item.previousId,
    newData: item.content,
    timestamp: item.updatedAt,
  ));
}

void _addModifiedOperation(List<TreeOperation> result, FlatResource item) {
  result.add(TreeOperation(
    type: TreeOperationType.modify,
    id: item.id,
    newData: item.content,
    timestamp: item.updatedAt,
  ));
}

void _addMovedOperation(List<TreeOperation> result, FlatResource item) {
  result.add(TreeOperation(
    type: TreeOperationType.move,
    id: item.id,
    parentId: item.parentId,
    previousId: item.previousId,
    timestamp: item.updatedAt,
  ));
}

void _addDeletedOperation(List<TreeOperation> result, FlatResource item) {
  result.add(TreeOperation(
    type: TreeOperationType.del,
    id: item.id,
    timestamp: item.updatedAt,
  ));
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