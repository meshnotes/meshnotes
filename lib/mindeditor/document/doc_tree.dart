import 'dart:convert';
import 'package:keygen/keygen.dart';

import 'text_desc.dart';
// import 'package:mesh_note/util/util.dart';
//
// class DocTree {
//   String parentVersion;
//   List<DocTreeItem> documents = [];
//   int timestamp;
//
//   DocTree({
//     required this.parentVersion,
//   }): timestamp = Util.getTimeStamp();
//
//   void add(DocTreeItem item) {
//     documents.add(item);
//   }
// }
//
// class DocTreeItem {
//   String docId;
//   String docHash;
//
//   DocTreeItem({
//     required this.docId,
//     required this.docHash,
//   });
//
//   String getDocTreeHash() {
//     return 'doc_tree_hash';
//   }
// }
//
// class DocNode {
//   String title;
//   String contentHash;
//   String parentHash;
//
//   DocNode({
//     required this.title,
//     required this.contentHash,
//     required this.parentHash,
//   });
//
//   String getDocNodeHash() {
//     return 'doc_node_hash';
//   }
// }
//
// class DocContentStructure {
//   String blockHash;
//   List<DocContentStructure> children;
//
//   DocContentStructure({
//     required this.blockHash,
//     this.children = const [],
//   });
//
//   String getDocObjectHash() {
//     return 'doc_object_hash';
//   }
// }

class VersionTree {
  VersionTreeItem root;
  String timestamp;
  String deviceId;

  VersionTree({
    required this.root,
    required this.timestamp,
    required this.deviceId,
  });
}

class VersionTreeItem {
  String versionHash;
  List<VersionTreeItem> parents;

  VersionTreeItem({
    required this.versionHash,
    required this.parents,
  });
}

class DocTreeVersion {
  List<DocTreeNode> table;
  int timestamp;
  List<String> parentsHash;

  DocTreeVersion({
    required this.table,
    required this.timestamp,
    required this.parentsHash,
  });

  Map<String, dynamic> toJson() {
    return {
      'doc_table': table,
      'timestamp': timestamp,
      'parents': parentsHash,
    };
  }
  DocTreeVersion.fromJson(Map<String, dynamic> map):
        table = _recursiveNodes(map['doc_table']),
        timestamp = map['timestamp'],
        parentsHash = _recursiveStrings(map['parents']);

  String getHash() {
    var jsonStr = jsonEncode(this);
    return HashUtil.hashText(jsonStr);
  }
  static List<DocTreeNode> _recursiveNodes(List<dynamic> list) {
    if(list.isEmpty) return [];
    List<DocTreeNode> result = [];
    for(var l in list) {
      var item = DocTreeNode.fromJson(l);
      result.add(item);
    }
    return result;
  }
  static List<String> _recursiveStrings(List<dynamic> list) {
    if(list.isEmpty) return [];
    List<String> result = [];
    for(var l in list) {
      var item = l as String;
      result.add(item);
    }
    return result;
  }
}

class DocTreeNode {
  String docId;
  String docHash;
  String title;
  int updatedAt;

  DocTreeNode({
    required this.docId,
    required this.docHash,
    required this.title,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'doc_id': docId,
      'title': title,
      'doc_hash': docHash,
      'updated_at': updatedAt,
    };
  }
  DocTreeNode.fromJson(Map<String, dynamic> map):
        docId = map['doc_id'],
        docHash = map['doc_hash'],
        title = map['title'],
        updatedAt = map['updated_at'];
}

class DocContent {
  List<DocContentItem> contents;

  DocContent({
    this.contents = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'contents': contents,
    };
  }
  DocContent.fromJson(Map<String, dynamic> map): contents = _recursiveList(map['contents']);

  String getHash() {
    var jsonStr = jsonEncode(this);
    return HashUtil.hashText(jsonStr);
  }

  static List<DocContentItem> _recursiveList(List<dynamic> list) {
    if(list.isEmpty) {
      return [];
    }
    List<DocContentItem> result = [];
    for(var l in list) {
      var item = DocContentItem.fromJson(l);
      result.add(item);
    }
    return result;
  }
}

class DocContentItem {
  String blockId;
  String blockHash;
  List<DocContentItem> children;

  DocContentItem({
    required this.blockId,
    required this.blockHash,
    this.children = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'block_id': blockId,
      'block_hash': blockHash,
      'children': children,
    };
  }
  DocContentItem.fromJson(Map<String, dynamic> map):
        blockId = map['block_id'],
        blockHash = map['block_hash'],
        children = _recursiveList(map['children']);

  static List<DocContentItem> _recursiveList(List<dynamic>? list) {
    if(list == null || list.isEmpty) {
      return [];
    }
    List<DocContentItem> result = [];
    for(var l in list) {
      var item = DocContentItem.fromJson(l);
      result.add(item);
    }
    return result;
  }
}

class ContentBlock {
  String type;
  String listing;
  int level;
  List<TextDesc> text;

  ContentBlock({
    required this.type,
    required this.listing,
    required this.level,
    required this.text,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'listing': listing,
      'level': level,
      'text': text,
    };
  }
  ContentBlock.fromJson(Map<String, dynamic> map):
        type = map['type'],
        listing = map['listing'],
        level = map['level'],
        text = _recursiveList(map['text']);

  String getHash() {
    var jsonStr = jsonEncode(this);
    return HashUtil.hashText(jsonStr);
  }

  static List<TextDesc> _recursiveList(List<dynamic>? list) {
    if(list == null || list.isEmpty) {
      return [];
    }
    var result = <TextDesc>[];
    for(var item in list) {
      TextDesc textDesc = TextDesc.fromJson(item);
      result.add(textDesc);
    }
    return result;
  }
}