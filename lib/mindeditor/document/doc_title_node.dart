import 'dal/doc_data_model.dart';

/// Tree node for hierarchical document structure
class DocTitleMeta {
  String docId;
  String title;
  String hash;
  int isPrivate;
  int timestamp;
  int orderId;
  String? parentDocId;
  DocTitleMeta? parent;
  List<DocTitleMeta> children = [];

  DocTitleMeta({
    required this.docId,
    required this.title,
    required this.isPrivate,
    required this.timestamp,
    required this.orderId,
    this.hash = ModelConstants.hashEmpty,
    this.parentDocId,
    this.parent,
  });

  /// Convert tree to flat list for UI display
  List<DocTitleFlat> toFlatList(int level) {
    List<DocTitleFlat> result = [];
    result.add(DocTitleFlat(
      docId: docId,
      title: title,
      isPrivate: isPrivate,
      timestamp: timestamp,
      hash: hash,
      orderId: orderId,
      parentDocId: parentDocId,
      level: level,
      hasChild: hasChild(),
    ));
    for (var child in children) {
      result.addAll(child.toFlatList(level + 1));
    }
    return result;
  }

  // void recursivelyUpdateLevel(int newLevel) {
  //   level = newLevel;
  //   for (var child in children) {
  //     child.recursivelyUpdateLevel(newLevel + 1);
  //   }
  // }

  bool hasChild() => children.isNotEmpty;

  void recursivelySortChildren() {
    children.sort((a, b) => a.orderId.compareTo(b.orderId));
    for (var child in children) {
      child.recursivelySortChildren();
    }
  }
}

class DocTitleFlat {
  String docId;
  String title;
  String hash;
  int isPrivate;
  int timestamp;
  int orderId;
  String? parentDocId;
  int level;
  final bool _hasChild;

  DocTitleFlat({
    required this.docId,
    required this.title,
    required this.isPrivate,
    required this.timestamp,
    required this.orderId,
    this.hash = ModelConstants.hashEmpty,
    this.parentDocId,
    this.level = 0,
    bool hasChild = false,
  }): _hasChild = hasChild;

  bool hasChild() => _hasChild;
}