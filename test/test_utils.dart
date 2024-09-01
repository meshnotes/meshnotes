import 'package:mesh_note/mindeditor/document/collaborate/version_manager.dart';

Map<String, DagNode> buildDagByNodes(List<DagNode> list) {
  var map = <String, DagNode>{};
  for (var item in list) {
    map[item.versionHash] = item;
  }
  return map;
}