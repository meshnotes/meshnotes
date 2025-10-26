import 'package:mesh_note/mindeditor/document/collaborate/find_operation_types.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/find_operations.dart';

void main() {
  group('LIS', () {
    test('empty input returns empty list', () {
      expect(findLongestIncreasingSubsequence([]), equals([]));
    });

    test('single element', () {
      expect(findLongestIncreasingSubsequence([5]), equals([5]));
    });

    test('strictly increasing sequence returns itself', () {
      final seq = [1, 2, 3, 4, 5];
      expect(findLongestIncreasingSubsequence(seq), equals(seq));
    });

    test('strictly decreasing sequence returns length 1 subsequence', () {
      final seq = [5, 4, 3, 2, 1];
      final lis = findLongestIncreasingSubsequence(seq);
      expect(lis.length, equals(1));
      expect(seq.contains(lis.first), isTrue);
    });

    test('typical mixed sequence', () {
      final seq = [10, 9, 2, 5, 3, 7, 101, 18];
      final lis = findLongestIncreasingSubsequence(seq);
      expect(lis.length, equals(4));
      expect(_isStrictlyIncreasing(lis), isTrue);
      expect(_isSubsequence(lis, seq), isTrue);
    });

    test('with duplicates', () {
      final seq = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9];
      final lis = findLongestIncreasingSubsequence(seq);
      expect(_isStrictlyIncreasing(lis), isTrue);
      expect(_isSubsequence(lis, seq), isTrue);
      expect(lis.length, equals(4));
    });

    test('all equal elements -> length 1', () {
      final seq = [7, 7, 7, 7, 7];
      final lis = findLongestIncreasingSubsequence(seq);
      expect(lis.length, equals(1));
      expect(seq.contains(lis.first), isTrue);
    });
  });

  group('findOperations', () {
    test('empty input returns empty list', () {
      final operations = findOperationsByFlat(<FlatResource>[], <FlatResource>[], 0);
      expect(operations.length, equals(0));
    });

    test('flat list of elements: add element', () {
      final list1 = _buildFlatList(['a', 'b', 'c', 'd', 'e']);
      final list2 = _buildFlatList(['a', 'f', 'b', 'c', 'd', 'e', 'g']);
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(2));
      expect(result[0].type, equals(TreeOperationType.add));
      expect(result[0].id, equals('f'));
      expect(result[1].type, equals(TreeOperationType.add));
      expect(result[1].id, equals('g'));
    });

    test('flat list of elements: delete element', () {
      final list1 = _buildFlatList(['a', 'b', 'c', 'd', 'e']);
      final list2 = _buildFlatList(['b', 'c', 'd', 'e']);
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(1));
      expect(result[0].type, equals(TreeOperationType.del));
      expect(result[0].id, equals('a'));
    });

    test('flat list of elements: move element', () {
      final list1 = _buildFlatList(['a', 'b', 'c', 'd', 'e']);
      final list2 = _buildFlatList(['a', 'e', 'b', 'd', 'c']);
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(2));
      expect(result[0].type, equals(TreeOperationType.move));
      expect(result[0].id, equals('d'));
      expect(result[1].type, equals(TreeOperationType.move));
      expect(result[1].id, equals('e'));
    });

    test('flat list of elements: modify element', () {
      final list1 = _buildFlatListWithContent([['a'], ['b', 'b1'], ['c'], ['d'], ['e']]);
      final list2 = _buildFlatListWithContent([['a'], ['b', 'b2'], ['c'], ['d'], ['e', 'e2']]);
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(2));
      expect(result[0].type, equals(TreeOperationType.modify));
      expect(result[0].id, equals('b'));
      expect(result[1].type, equals(TreeOperationType.modify));
      expect(result[1].id, equals('e'));
    });

    test('tree list of elements: add element', () {
      final list1 = _buildTreeListWithContent({
        'a': {
          'parent': null,
          'previous': null,
        },
        'b': {
          'parent': 'a',
          'previous': null,
        },
        'c': {
          'parent': 'a',
          'previous': 'b',
        },
        'd': {
          'parent': null,
          'previous': 'a',
        },
        'e': {
          'parent': null,
          'previous': 'd',
        },
      });
      final list2 = _buildTreeListWithContent({
        'a': {
          'parent': null,
          'previous': null,
        },
        'b': {
          'parent': 'a',
          'previous': null,
        },
        'h': {
          'parent': 'b',
          'previous': null,
        },
        'c': {
          'parent': 'a',
          'previous': 'b',
        },
        'g': {
          'parent': 'a',
          'previous': 'c',
        },
        'd': {
          'parent': null,
          'previous': 'a',
        },
        'e': {
          'parent': null,
          'previous': 'd',
        },
        'f': {
          'parent': null,
          'previous': 'e',
        }
      });
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(3));
      final expectedNodes = ['f', 'g', 'h'];
      for(var expectedNode in expectedNodes) {
        expect(result.any((operation) => operation.id == expectedNode && operation.type == TreeOperationType.add), isTrue);
      }
    });

    test('tree list of elements: delete element', () {
      final list1 = _buildTreeListWithContent({
        'a': {
          'parent': null,
          'previous': null,
        },
        'b': {
          'parent': 'a',
          'previous': null,
        },
        'f': {
          'parent': 'b',
          'previous': null,
        },
        'c': {
          'parent': 'a',
          'previous': 'b',
        },
        'd': {
          'parent': null,
          'previous': 'a',
        },
        'e': {
          'parent': null,
          'previous': 'd',
        },
      });
      final list2 = _buildTreeListWithContent({
        'a': {
          'parent': null,
          'previous': null,
        },
        'b': {
          'parent': 'a',
          'previous': null,
        },
        'd': {
          'parent': null,
          'previous': 'a',
        },
        'e': {
          'parent': null,
          'previous': 'd',
        },
      });
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(2));
      final expectedNodes = ['c', 'f'];
      for(var expectedNode in expectedNodes) {
        expect(result.any((operation) => operation.id == expectedNode && operation.type == TreeOperationType.del), isTrue);
      }
    });

   test('tree list of elements: move element', () {
      final list1 = _buildTreeListWithContent({
        'a': {
          'parent': null,
          'previous': null,
        },
        'b': {
          'parent': 'a',
          'previous': null,
        },
        'f': {
          'parent': 'b',
          'previous': null,
        },
        'c': {
          'parent': 'a',
          'previous': 'b',
        },
        'd': {
          'parent': null,
          'previous': 'a',
        },
        'e': {
          'parent': null,
          'previous': 'd',
        },
        'g': {
          'parent': null,
          'previous': 'e',
        }
      });
      final list2 = _buildTreeListWithContent({
        'a': {
          'parent': null,
          'previous': null,
        },
        'b': {
          'parent': 'a',
          'previous': null,
        },
        'f': {
          'parent': 'b',
          'previous': null,
        },
        'c': {
          'parent': 'b',
          'previous': 'f',
        },
        'e': {
          'parent': null,
          'previous': 'a',
        },
        'g': {
          'parent': null,
          'previous': 'e',
        },
        'd': {
          'parent': null,
          'previous': 'g',
        },
      });
      final result = findOperationsByFlat(list1, list2, 0);
      expect(result.length, equals(2));
      final expectedNodes = ['c', 'd'];
      for(var expectedNode in expectedNodes) {
        expect(result.any((operation) => operation.id == expectedNode && operation.type == TreeOperationType.move), isTrue);
      }
    });
  });
}

bool _isStrictlyIncreasing(List<int> seq) {
  for (int i = 1; i < seq.length; i++) {
    if (seq[i] <= seq[i - 1]) return false;
  }
  return true;
}

bool _isSubsequence(List<int> sub, List<int> seq) {
  int j = 0;
  for (int i = 0; i < seq.length && j < sub.length; i++) {
    if (seq[i] == sub[j]) j++;
  }
  return j == sub.length;
}

List<FlatResource> _buildFlatList(List<String> tags) {
  List<FlatResource> result = [];
  String? previous;
  for(var tag in tags) {
    result.add(FlatResource(id: tag, content: tag, parentId: null, previousId: previous, updatedAt: 0));
    previous = tag;
  }
  return result;
}

List<FlatResource> _buildFlatListWithContent(List<List<String>> content) {
  List<FlatResource> result = [];
  String? previous;
  for(var item in content) {
    final key = item[0];
    var content = key;
    if(item.length > 1) {
      content = item[1];
    }
    result.add(FlatResource(id: key, content: content, parentId: null, previousId: previous, updatedAt: 0));
    previous = key;
  }
  return result;
}

List<FlatResource> _buildTreeListWithContent(Map<String, Map<String, String?>> content) {
  List<FlatResource> result = [];
  for(var item in content.entries) {
    final key = item.key;
    final subMap = item.value;
    var parentId = subMap['parent'];
    var previousId = subMap['previous'];
    result.add(FlatResource(id: key, content: key, parentId: parentId, previousId: previousId, updatedAt: 0));
  }
  return result;
}
