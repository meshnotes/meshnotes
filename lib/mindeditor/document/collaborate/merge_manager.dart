import 'package:mesh_note/mindeditor/document/collaborate/diff_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';

class MergeManager {
  VersionContent? baseVersion;

  MergeManager({
    required this.baseVersion,
  });

  VersionContent merge(DiffOperation op1, DiffOperation op2) {
    return VersionContent(table: [], timestamp: 0, parentsHash: []);
  }
}