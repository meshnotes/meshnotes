import 'dal/doc_data_model.dart';

/// Tree node for hierarchical document structure
class DocTitleNode {
  DocDataModel document;
  List<DocTitleNode> children;
  DocTitleNode? parent;
  int level;

  DocTitleNode({
    required this.document,
    this.children = const [],
    this.parent,
    this.level = 0,
  }) {
    children = List.from(children); // Make a mutable copy
  }

  /// Get document ID
  String get docId => document.docId;

  /// Get document title
  String get title => document.title;

  /// Check if this node has children
  bool get hasChildren => children.isNotEmpty;

  /// Check if this is a root node
  bool get isRoot => parent == null;

  /// Add a child node
  void addChild(DocTitleNode child) {
    child.parent = this;
    child.level = level + 1;
    children.add(child);
  }

  /// Remove a child node
  void removeChild(DocTitleNode child) {
    child.parent = null;
    children.remove(child);
  }

  /// Get all descendant nodes (recursive)
  List<DocTitleNode> getAllDescendants() {
    List<DocTitleNode> descendants = [];
    for (var child in children) {
      descendants.add(child);
      descendants.addAll(child.getAllDescendants());
    }
    return descendants;
  }

  /// Convert tree to flat list for UI display
  List<DocTitleNode> toFlatList() {
    List<DocTitleNode> result = [this];
    for (var child in children) {
      result.addAll(child.toFlatList());
    }
    return result;
  }

  @override
  String toString() {
    return 'DocTreeNode(docId: $docId, title: $title, level: $level, children: ${children.length})';
  }
}