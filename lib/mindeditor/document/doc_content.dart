import 'dart:convert';
import 'package:keygen/keygen.dart';

import 'text_desc.dart';

class VersionTreeItem {
  String versionHash;
  List<VersionTreeItem> parents;

  VersionTreeItem({
    required this.versionHash,
    required this.parents,
  });
}

class VersionContent {
  List<VersionContentItem> table;
  int timestamp;
  List<String> parentsHash;

  VersionContent({
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
  VersionContent.fromJson(Map<String, dynamic> map):
        table = _recursiveNodes(map['doc_table']),
        timestamp = map['timestamp'],
        parentsHash = _recursiveStrings(map['parents']);

  String getHash() {
    var jsonStr = jsonEncode(this);
    return HashUtil.hashText(jsonStr);
  }
  static List<VersionContentItem> _recursiveNodes(List<dynamic> list) {
    if(list.isEmpty) return [];
    List<VersionContentItem> result = [];
    for(var l in list) {
      var item = VersionContentItem.fromJson(l);
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

class VersionContentItem {
  String docId;
  String docHash;
  int updatedAt;

  VersionContentItem({
    required this.docId,
    required this.docHash,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'doc_id': docId,
      'doc_hash': docHash,
      'updated_at': updatedAt,
    };
  }
  VersionContentItem.fromJson(Map<String, dynamic> map):
        docId = map['doc_id'],
        docHash = map['doc_hash'],
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

class BlockContent {
  String type;
  String listing;
  int level;
  List<TextDesc> text;

  BlockContent({
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
  BlockContent.fromJson(Map<String, dynamic> map):
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