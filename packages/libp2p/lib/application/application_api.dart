import 'dart:convert';

typedef OnHandleNewVersion = Function(String versionHash, String versionStr, Map<String, String> objects);
typedef OnHandleNewVersionTree = Function(List<VersionNode> dag);
typedef OnHandleRequireVersions = Function(List<String> requiredVersions);
typedef OnHandleSendVersions = Function(List<SendVersionsNode> versions);
typedef OnHandleStringFunction = Function(String data);

const String ProvideAppType = 'provide';
const String QueryAppType = 'query';

class VillageMessageHandler {
  OnHandleStringFunction? handleProvide;
  OnHandleStringFunction? handleQuery;
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

class SignedMessage {
  String userPublicId;
  String data;
  String signature;

  SignedMessage({
    required this.userPublicId,
    required this.data,
    required this.signature,
  });

  SignedMessage.fromJson(Map<String, dynamic> map):
        userPublicId = map['user'],
        data = map['data'],
        signature = map['sign'];

  Map<String, dynamic> toJson() {
    return {
      'user': userPublicId,
      'data': data,
      'sign': signature,
    };
  }
}

class UnsignedResource {
  String key;
  String subKey;
  int timestamp;
  String data;

  UnsignedResource({
    required this.key,
    required this.subKey,
    required this.timestamp,
    required this.data,
  });

  String getFeature() {
    return 'key: $key\n'
        'sub_key: $subKey\n'
        'timestamp: $timestamp\n'
        'data: $data';
  }
}

class SignedResource {
  String key;
  String subKey;
  int timestamp;
  String data;
  String signature;

  SignedResource({
    required this.key,
    required this.subKey,
    required this.timestamp,
    required this.data,
    required this.signature,
  });

  SignedResource.fromRaw(UnsignedResource raw, String signature):
        key = raw.key,
        subKey = raw.subKey,
        timestamp = raw.timestamp,
        data = raw.data,
        signature = signature;
  SignedResource.fromJson(Map<String, dynamic> map):
        key = map['key'],
        subKey = map['sub_key'],
        timestamp = map['timestamp'],
        data = map['data'],
        signature = map['sign'];

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'sub_key': subKey,
      'timestamp': timestamp,
      'data': data,
      'sign': signature
    };
  }
}

class SignedResources {
  String userPublicId;
  List<SignedResource> resources;
  String signature;

  SignedResources({
    required this.userPublicId,
    required this.resources,
    required this.signature,
  });

  static String getFeature(List<SignedResource> resources) {
    String feature = '';
    for(var r in resources) {
      String json = jsonEncode(r);
      feature += 'resource: $json\n';
    }
    return feature;
  }

  SignedResources.fromJson(Map<String, dynamic> map):
        userPublicId = map['user'],
        resources = _recursiveList(map['resources']),
        signature = map['sign'];

  Map<String, dynamic> toJson() {
    return {
      'user': userPublicId,
      'resources': resources,
      'sign': signature,
    };
  }

  static List<SignedResource> _recursiveList(List<dynamic> list) {
    List<SignedResource> result = [];
    for(var item in list) {
      SignedResource signedResource = SignedResource.fromJson(item);
      result.add(signedResource);
    }
    return result;
  }
}

class ProvideMessage {
  String userPubKey;
  List<String> resources;

  ProvideMessage({
    required this.userPubKey,
    required this.resources,
  });

  ProvideMessage.fromJson(Map<String, dynamic> map): userPubKey = map['user'], resources = map['resources'];

  Map<String, dynamic> toJson() {
    return {
      'user': userPubKey,
      'resources': resources,
    };
  }
}

class EncryptedVersionChain {
  String versionChainEncrypted;
  int timestamp;

  EncryptedVersionChain({
    required this.versionChainEncrypted,
    required this.timestamp,
  });
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
  Map<String, (int, String)> requiredObjects;

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

  static Map<String, (int, String)> _recursiveMap(Map<String, dynamic> map) {
    Map<String, (int, String)> result = {};
    for(var e in map.entries) {
      String key = e.key;
      var (timestamp, value) = e.value as (int, String);
      result[key] = (timestamp, value);
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