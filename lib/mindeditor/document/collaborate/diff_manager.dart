import 'package:mesh_note/mindeditor/document/doc_content.dart';

class DiffOperation {
  VersionContent versionContent;

  DiffOperation({
    required this.versionContent,
  });
}

class DiffManager {
  DiffOperation findDifferentOperation(VersionContent version1, VersionContent? version2) {
    return DiffOperation(versionContent: version1);
  }
}