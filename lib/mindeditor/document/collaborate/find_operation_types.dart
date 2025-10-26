// Flat means no recursive structure, only a list. The hierarchy relationship is described by parentId and previousId.
class FlatResource {
  final String id;
  final String content;
  final String? parentId;
  final String? previousId;
  final int updatedAt;

  const FlatResource({
    required this.id,
    required this.content,
    required this.parentId,
    required this.previousId,
    required this.updatedAt,
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
  // String? originalData;
  String? newData;
  int timestamp;
  // Traverse status
  bool _finished = false;

  TreeOperation({
    required this.type,
    required this.id,
    this.parentId,
    this.previousId,
    // this.originalData,
    this.newData,
    required this.timestamp,
  });

  bool isFinished() => _finished;
  void setFinished() {
    _finished = true;
  }
}
