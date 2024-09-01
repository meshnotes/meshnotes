import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/version_manager.dart';

const String _versionTag1 = 'n1';
const String _versionTag2 = 'n2';
const String _commonTag = 'here';
const String _commonTag2 = 'here2';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Finding common ancestor node in linear DAG with null parent node', () {
    // MyLogger.initForConsoleTest(name: 'test');
    var map = _genSimpleLinearDagWithNullParent();
    VersionManager vm = VersionManager();
    DagNode n1 = map[_versionTag1]!;
    DagNode n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result, null);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2, null);
  });
}

Map<String, DagNode> _genSimpleLinearDagWithNullParent() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [r1]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: []);
  return {
    'root': root,
    'r1': r1,
    _versionTag1: n1,
    _versionTag2: n2,
  };
}

/// root--r1--common--n1
///             \-----n2
Map<String, DagNode> _genForkedDagMapWithOneCommonParent() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var common = DagNode(versionHash: _commonTag, createdAt: 0, parents: [r1]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [common]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [common]);
  return {
    'root': root,
    'r1': r1,
    _commonTag: common,
    _versionTag1: n1,
    _versionTag2: n2,
  };
}

///                 n2
///                /
/// root--f1--common--cross--n1
///  \----f2 --f2_2---/
Map<String, DagNode> _genForkedDagMapWithCommonNodeInOnePath() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var forked1 = DagNode(versionHash: 'f1', createdAt: 0, parents: [root]);
  var forked2 = DagNode(versionHash: 'f2', createdAt: 0, parents: [root]);
  var common = DagNode(versionHash: _commonTag, createdAt: 0, parents: [forked1]);
  var forked2_2 = DagNode(versionHash: 'f2_2', createdAt: 0, parents: [forked2]);
  var crossNode = DagNode(versionHash: 'cross', createdAt: 0, parents: [common, forked2_2]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [crossNode]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [common]);
  return {
    'root': root,
    'f1': forked1,
    'f2': forked2,
    _commonTag: common,
    'f2_2': forked2_2,
    'cross': crossNode,
    _versionTag1: n1,
    _versionTag2: n2,
  };
}

/// root--f1--p1_1--p1_2--common1----crossed1---n1
///  \                      \        /
///   \---f2--common2--------+---p2_1
///               \-----------\
///                           crossed2--r2--n2
Map<String, DagNode> _genForkedDagMapWithTwoCommonNodes() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var forked1 = DagNode(versionHash: 'f1', createdAt: 0, parents: [root]);
  var forked2 = DagNode(versionHash: 'f2', createdAt: 0, parents: [root]);
  var p1_1 = DagNode(versionHash: 'p1_1', createdAt: 0, parents: [forked1]);
  var p1_2 = DagNode(versionHash: 'p1_2', createdAt: 0, parents: [p1_1]);
  var common1 = DagNode(versionHash: _commonTag, createdAt: 0, parents: [p1_2]);
  var common2 = DagNode(versionHash: _commonTag2, createdAt: 0, parents: [forked2]);
  var p2_1 = DagNode(versionHash: 'p2_1', createdAt: 0, parents: [common2]);
  var crossed1 = DagNode(versionHash: 'crossed1', createdAt: 0, parents: [common1, p2_1]);
  var crossed2 = DagNode(versionHash: 'crossed2', createdAt: 0, parents: [common1, common2]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [crossed1]);
  var r2 = DagNode(versionHash: 'r2', createdAt: 0, parents: [crossed2]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [r2]);
  return {
    'root': root,
    'f1': forked1,
    'f2': forked2,
    'p1_1': p1_1,
    'p1_2': p1_2,
    _commonTag: common1,
    _commonTag2: common2,
    'p2_1': p2_1,
    'crossed1': crossed1,
    'crossed2': crossed2,
    _versionTag1: n1,
    'r2': r2,
    _versionTag2: n2,
  };
}