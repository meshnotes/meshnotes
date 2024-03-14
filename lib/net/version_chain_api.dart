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
}

class SendVersions {
  String versionHash;
  String versionContent;
  int createdAt;
  String parents;
  Map<String, RelatedObject> requiredObjects;

  SendVersions({
    required this.versionHash,
    required this.versionContent,
    required this.requiredObjects,
    required this.createdAt,
    required this.parents,
  });

  SendVersions.fromJson(Map<String, dynamic> map):
        versionHash = map['hash'],
        versionContent = map['content'],
        createdAt = map['created_at'],
        parents = map['parents'],
        requiredObjects = _recursiveMap(map['objects']);

  Map<String, dynamic> toJson() {
    return {
      'hash': versionHash,
      'content': versionContent,
      'created_at': createdAt,
      'parents': parents,
      'objects': requiredObjects,
    };
  }

  static Map<String, RelatedObject> _recursiveMap(Map<String, dynamic> map) {
    Map<String, RelatedObject> result = {};
    for(var e in map.entries) {
      final key = e.key;
      var object = RelatedObject.fromJson(e.value);
      result[key] = object;
    }
    return result;
  }

  @override
  String toString() {
    return '$versionHash: $requiredObjects';
  }
}

class RelatedObject {
  String objHash;
  String objContent;
  int createdAt;

  RelatedObject({
    required this.objHash,
    required this.objContent,
    required this.createdAt,
  });

  RelatedObject.fromJson(Map<String, dynamic> map):
        objHash = map['hash'],
        objContent = map['content'],
        createdAt = map['created_at'];

  Map<String, dynamic> toJson() {
    return {
      'hash': objHash,
      'content': objContent,
      'created_at': createdAt,
    };
  }

  @override
  String toString() {
    return '$objHash/$createdAt';
  }
}