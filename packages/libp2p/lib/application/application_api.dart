import 'dart:convert';

typedef OnHandleStringFunction = Function(String data);

enum AppMessageType {
  provideAppType('provide'), // Provider other nodes the version tree
  queryAppType('query'), // Query other nodes for version
  // searchAppType('search'), // Ask for the location of resource
  publishAppType('publish'); // Publish newest resource to other nodes

  final String value;
  const AppMessageType(this.value);
}

class VillageMessageHandler {
  OnHandleStringFunction? handleProvide;
  OnHandleStringFunction? handleQuery;
  OnHandleStringFunction? handlePublish;
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

  @override
  String toString() {
    return 'URes($key)';
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

  @override
  String toString() {
    return 'SRes($key)';
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

  @override
  String toString() {
    return '$resources';
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

class UserPublicInfo {
  String publicKey;
  String userName;
  int timestamp;
  String signature;

  UserPublicInfo({
    required this.publicKey,
    required this.userName,
    required this.timestamp,
    this.signature = '',
  });

  String getFeature() {
    return 'public_key: $publicKey\n'
        'name: $userName\n'
        'timestamp: $timestamp\n';
  }

  UserPublicInfo.fromJson(Map<String, dynamic> map):
        publicKey = map['public_key'],
        userName = map['name'],
        timestamp = map['timestamp'],
        signature = map['sign'];

  Map<String, dynamic> toJson() {
    return {
      'public_key': publicKey,
      'name': userName,
      'timestamp': timestamp,
      'sign': signature,
    };
  }
}

class SimpleUserPrivateInfo {
  String publicKey;
  String userName;
  String privateKey;
  int timestamp;

  SimpleUserPrivateInfo({
    required this.publicKey,
    required this.userName,
    required this.privateKey,
    required this.timestamp,
  });
}
