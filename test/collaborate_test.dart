import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_note/init.dart';
import 'package:mesh_note/mindeditor/document/collaborate/merge.dart';

const String _versionTag1 = 'n1';
const String _versionTag2 = 'n2';
const String _commonTag = 'here';

void main() {
  // appInit(test: true);
  test('Finding common ancestor node in linear DAG', () {
    var (n1, n2) = _genSimpleLinearDag();
    VersionManager vm = VersionManager();
    var result = vm.findCommonAncestor(n1, n2);
    expect(result != null, true);
    expect(result, n1);

    var result2 = vm.findCommonAncestor(n2, n1);
    expect(result2 != null, true);
    expect(result2, n1);
  });

  test('Finding common ancestor node in forked DAG', () {
    var (n1, n2) = _genForkedDag();
    VersionManager vm = VersionManager();
    var result = vm.findCommonAncestor(n1, n2);
    expect(result != null, true);
    expect(result!.versionHash, _commonTag);
  });
}

(DagNode, DagNode) _genSimpleLinearDag() {
  var root = DagNode(versionHash: 'root', parents: []);
  var r1 = DagNode(versionHash: 'r1', parents: [root]);
  var n1 = DagNode(versionHash: _versionTag1, parents: [r1]);
  var n2 = DagNode(versionHash: _versionTag2, parents: [n1]);
  return (n1, n2);
}

(DagNode, DagNode) _genForkedDag() {
  var root = DagNode(versionHash: 'root', parents: []);
  var r1 = DagNode(versionHash: 'r1', parents: [root]);
  var common = DagNode(versionHash: _commonTag, parents: [r1]);
  var n1 = DagNode(versionHash: _versionTag1, parents: [common]);
  var n2 = DagNode(versionHash: _versionTag2, parents: [common]);
  return (n1, n2);
}