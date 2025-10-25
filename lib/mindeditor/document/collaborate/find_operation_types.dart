class TreeResource {
  String id;
  String content;
  List<TreeResource> children;

  TreeResource({
    required this.id,
    required this.content,
    this.children = const [],
  });
}

enum TreeOperationType {
  add,
  del,
  move,
  modify,
}

class TreeOperation {
  TreeOperationType type;
  String id;
  String? parentId;
  String? previousId;
  String? originalData;
  String? newData;

  TreeOperation({
    required this.type,
    required this.id,
    this.parentId,
    this.previousId,
    this.originalData,
    this.newData,
  });
}
