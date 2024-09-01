import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/version_manager.dart';

import 'test_utils.dart';

const String _versionTag1 = 'n1';
const String _versionTag2 = 'n2';
const String _commonTag = 'here';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Finding common ancestor node in DAG with null parent node', () {
    // MyLogger.initForConsoleTest(name: 'test');
    var map = _genSimpleLinearDagWithNullParent();
    final vm = VersionManager();
    DagNode n1 = map[_versionTag1]!;
    DagNode n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result, null);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2, null);
  });

  test('Finding common ancestor node in forked DAG with missing nodes', () {
    var map = _genDagWithMissingNodes();
    final vm = VersionManager();
    var n1 = map[_versionTag1]!;
    var n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result != null, true);
    expect(result!.versionHash, _commonTag);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2 != null, true);
    expect(result2!.versionHash, _commonTag);
  });

  // Notice: this is not a normal case, for the deprecated node should be removed from DAG map before calling this method
  test('Finding common ancestor node in forked DAG with deprecated nodes', () {
    var map = _genDagWithDeprecatedNodes();
    final vm = VersionManager();
    var n1 = map[_versionTag1]!;
    var n2 = map[_versionTag2]!;
    var result = vm.findNearestCommonAncestor([n1, n2], map);
    expect(result != null, true);
    expect(result!.versionHash, _commonTag);

    var result2 = vm.findNearestCommonAncestor([n2, n1], map);
    expect(result2 != null, true);
    expect(result2!.versionHash, _commonTag);
  });
}

/// root--r1--n1
///     null--n2
Map<String, DagNode> _genSimpleLinearDagWithNullParent() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [r1]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: []);
  return buildDagByNodes([root, r1, n1, n2]);
}

/// root--r1--common--missing1--n1
///             \-----r2----n2
Map<String, DagNode> _genDagWithMissingNodes() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var common = DagNode(versionHash: _commonTag, createdAt: 0, parents: [r1]);
  var missing1 = DagNode(versionHash: 'missing1', createdAt: 0, parents: [common]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [missing1]);
  var r2 = DagNode(versionHash: 'r2', createdAt: 0, parents: [common]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [r2]);
  return buildDagByNodes([root, r1, common, missing1, n1, r2, n2]);
}

/// root--r1--common--missing1--n1
///             \-----r2---deprecated1---n2
Map<String, DagNode> _genDagWithDeprecatedNodes() {
  var root = DagNode(versionHash: 'root', createdAt: 0, parents: []);
  var r1 = DagNode(versionHash: 'r1', createdAt: 0, parents: [root]);
  var common = DagNode(versionHash: _commonTag, createdAt: 0, parents: [r1]);
  var missing1 = DagNode(versionHash: 'missing1', createdAt: 0, parents: [common]);
  var n1 = DagNode(versionHash: _versionTag1, createdAt: 0, parents: [missing1]);
  var r2 = DagNode(versionHash: 'r2', createdAt: 0, parents: [common]);
  var deprecated1 = DagNode(versionHash: 'deprecated', createdAt: 0, parents: [r2]);
  var n2 = DagNode(versionHash: _versionTag2, createdAt: 0, parents: [deprecated1]);
  return buildDagByNodes([root, r1, common, missing1, n1, r2, n2]);
}