import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/version_manager.dart';

import 'test_utils.dart';

const String _versionTag1 = 'n1';
const String _versionTag2 = 'n2';
const String _commonTag = 'here';
const String _commonTag2 = 'here2';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Finding common ancestor node in linear DAG', () {
    // MyLogger.initForConsoleTest(name: 'test');
    var map = _genSimpleLinearDag();
    VersionManager vm = VersionManager();
    DagNode n1 = map[_versionTag1]!;
    DagNode n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result != null, true);
    expect(result, n1);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2 != null, true);
    expect(result2, n1);
    // MyLogger.shutdown();
  });

  test('Find common ancestor node in simple forked DAG, the common node is the crossed node', () {
    var map = _genForkedDagMapWithOneCommonParent();
    VersionManager vm = VersionManager();
    DagNode n1 = map[_versionTag1]!;
    DagNode n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result != null, true);
    expect(result!.versionHash, _commonTag);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2 != null, true);
    expect(result2!.versionHash, _commonTag);
  });

  test('Find common ancestor node in forked DAG, the common node is in one sub-path', () {
    var map = _genForkedDagMapWithCommonNodeInOnePath();
    VersionManager vm = VersionManager();
    DagNode n1 = map[_versionTag1]!;
    DagNode n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result != null, true);
    expect(result!.versionHash, _commonTag);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2 != null, true);
    expect(result2!.versionHash, _commonTag);
  });

  test('Find common ancestor node in complex DAG, with two common nodes in two paths', () {
    var map = _genForkedDagMapWithTwoCommonNodes();
    VersionManager vm = VersionManager();
    DagNode n1 = map[_versionTag1]!;
    DagNode n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result != null, true);
    expect(result!.versionHash, 'root');

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2 != null, true);
    expect(result2!.versionHash, 'root');
  });

  test('Find common ancestor node in two DAG, with no common root', () {
    var map1 = _genSimpleLinearDag();
    var map2 = _genSimpleLinearDag();
    var n1 = map1[_versionTag1]!;
    var n2 = map2[_versionTag2]!;
    VersionManager vm = VersionManager();
    var result = vm.findNearestCommonAncestor([n1, n2], map1);
    expect(result == null, true);
  });
}

Map<String, DagNode> _genSimpleLinearDag() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [r1]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [n1]);
  return buildDagByNodes([root, r1, n1, n2]);
}

/// root--r1--common--n1
///             \-----n2
Map<String, DagNode> _genForkedDagMapWithOneCommonParent() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var common = DagNode(versionHash: _commonTag, createdAt: 0, parents: [r1]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [common]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [common]);
  return buildDagByNodes([root, r1, common, n1, n2]);
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
  return buildDagByNodes([root, forked1, forked2, common, forked2_2, crossNode, n1, n2]);
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
  return buildDagByNodes([root, forked1, forked2, p1_1, p1_2, common1, common2, p2_1, crossed1, crossed2, n1, r2, n2]);
}