typedef OnHandleNewVersion = Function(String versionHash, String versionStr, Map<String, String> objects);
typedef OnHandleNewVersionTree = Function(List<VersionNode> dag);
typedef OnHandleRequireVersions = Function(List<String> requiredVersions);
typedef OnHandleSendVersions = Function(List<SendVersionsNode> versions);

const String VersionTreeAppType = 'version_tree';
const String RequireVersionsAppType = 'require_versions';
const String SendVersionsAppType = 'send_versions';

class VillageMessageHandler {
  OnHandleNewVersionTree? handleNewVersion;
  OnHandleNewVersionTree? handleNewVersionTree;
  OnHandleRequireVersions? handleRequireVersions;
  OnHandleSendVersions? handleSendVersions;
}

class VersionNode {
  String versionHash;
  int createdAt;
  List<String> parents;

  VersionNode({
    required this.versionHash,
    required this.createdAt,
    required this.parents,
  });

  VersionNode.fromJson(Map<String, dynamic> map):
    versionHash = map['hash'],
    createdAt = map['created_at'],
    parents = _recursiveList(map['parents']);

  Map<String, dynamic> toJson() {
    return {
      'hash': versionHash,
      'created_at': createdAt,
      'parents': parents,
    };
  }

  static List<String> _recursiveList(List<dynamic> list) {
    final result = <String>[];
    for(var item in list) {
      result.add(item as String);
    }
    return result;
  }
}
class VersionChain {
  List<VersionNode> versionDag;

  VersionChain({
    required this.versionDag,
  });

  VersionChain.fromJson(Map<String, dynamic> map): versionDag = _recursiveList(map['dag']);

  Map<String, dynamic> toJson() {
    return {
      'dag': versionDag,
    };
  }

  static List<VersionNode> _recursiveList(List<dynamic> list) {
    final result = <VersionNode>[];
    for(var item in list) {
      result.add(VersionNode.fromJson(item));
    }
    return result;
  }
  static Map<String, String> _recursiveMap(Map<String, dynamic> map) {
    final result = <String, String>{};
    for(var entry in map.entries) {
      result[entry.key] = entry.value as String;
    }
    return result;
  }
}

class RequireVersions {
  List<String> requiredVersions;

  RequireVersions({
    required this.requiredVersions,
  });

  RequireVersions.fromJson(Map<String, dynamic> map): requiredVersions = _recursiveList(map['versions']);

  Map<String, dynamic> toJson() {
    return {
      'versions': requiredVersions,
    };
  }

  static List<String> _recursiveList(List<dynamic> list) {
    final result = <String>[];
    for(var item in list) {
      result.add(item as String);
    }
    return result;
  }
}

class SendVersionsNode {
  String versionHash;
  String versionContent;
  int createdAt;
  String parents;
  Map<String, String> requiredObjects;

  SendVersionsNode({
    required this.versionHash,
    required this.versionContent,
    required this.requiredObjects,
    required this.createdAt,
    required this.parents,
  });

  SendVersionsNode.fromJson(Map<String, dynamic> map):
        versionHash = map['hash'],
        versionContent = map['content'],
        createdAt = map['created_at'],
        parents = map['parents'],
        requiredObjects = _recursiveMap(map['required_objects']);

  Map<String, dynamic> toJson() {
    return {
      'hash': versionHash,
      'content': versionContent,
      'created_at': createdAt,
      'parents': parents,
      'required_objects': requiredObjects,
    };
  }

  static Map<String, String> _recursiveMap(Map<String, dynamic> map) {
    Map<String, String> result = {};
    for(var e in map.entries) {
      String key = e.key;
      String value = e.value as String;
      result[key] = value;
    }
    return result;
  }

  @override
  String toString() {
    return '$versionHash: $requiredObjects';
  }
}

class SendVersions {
  List<SendVersionsNode> versions;

  SendVersions({
    required this.versions,
  });

  SendVersions.fromJson(Map<String, dynamic> map): versions = _recursiveList(map['versions']);

  Map<String, dynamic> toJson() {
    return {
      'versions': versions,
    };
  }

  static List<SendVersionsNode> _recursiveList(List<dynamic> list) {
    final result = <SendVersionsNode>[];
    for(var item in list) {
      var node = SendVersionsNode.fromJson(item);
      result.add(node);
    }
    return result;
  }
}