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

  group('findDifferences', () {
    test('empty input returns empty list', () {
      final (added, deleted, moved, modified) = findDifferences([], []);
      expect(added, equals([]));
      expect(deleted, equals([]));
      expect(moved, equals([]));
      expect(modified, equals([]));
    });

    test('flat list of elements: add element', () {
      final list1 = _buildFlatList(['a', 'b', 'c', 'd', 'e']);
      final list2 = _buildFlatList(['a', 'f', 'b', 'c', 'd', 'e', 'g']);
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added, equals(['f', 'g']));
      expect(deleted, equals([]));
      expect(moved, equals([]));
      expect(modified, equals([]));
    });

    test('flat list of elements: delete element', () {
      final list1 = _buildFlatList(['a', 'b', 'c', 'd', 'e']);
      final list2 = _buildFlatList(['b', 'c', 'd', 'e']);
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added, equals([]));
      expect(deleted, equals(['a']));
      expect(moved, equals([]));
      expect(modified, equals([]));
    });

    test('flat list of elements: move element', () {
      final list1 = _buildFlatList(['a', 'b', 'c', 'd', 'e']);
      final list2 = _buildFlatList(['a', 'e', 'b', 'd', 'c']);
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added, equals([]));
      expect(deleted, equals([]));
      expect(moved.contains('d'), isTrue);
      expect(moved.contains('e'), isTrue);
      expect(modified, equals([]));
    });

    test('flat list of elements: modify element', () {
      final list1 = _buildFlatListWithContent([['a'], ['b', 'b1'], ['c'], ['d'], ['e']]);
      final list2 = _buildFlatListWithContent([['a'], ['b', 'b2'], ['c'], ['d'], ['e', 'e2']]);
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added, equals([]));
      expect(deleted, equals([]));
      expect(moved, equals([]));
      expect(modified.contains('b'), isTrue);
      expect(modified.contains('e'), isTrue);
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
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added.contains('f'), isTrue);
      expect(added.contains('g'), isTrue);
      expect(added.contains('h'), isTrue);
      expect(deleted, equals([]));
      expect(moved, equals([]));
      expect(modified, equals([]));
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
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added, equals([]));
      expect(deleted.contains('c'), isTrue);
      expect(deleted.contains('f'), isTrue);
      expect(moved, equals([]));
      expect(modified, equals([]));
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
      final (added, deleted, moved, modified) = findDifferences(list1, list2);
      expect(added, equals([]));
      expect(deleted, equals([]));
      expect(moved.contains('c'), isTrue); // reparent
      expect(moved.contains('d'), isTrue); // move
      expect(modified, equals([]));
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
    result.add(FlatResource(id: tag, content: tag, parentId: null, previousId: previous));
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
    result.add(FlatResource(id: key, content: content, parentId: null, previousId: previous));
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
    result.add(FlatResource(id: key, content: key, parentId: parentId, previousId: previousId));
  }
  return result;
}
