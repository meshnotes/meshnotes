import 'dart:convert';

typedef OnHandleStringWithPublicKeyFunction = Function(String senderPublicKey, String data, TimeCostStatistics stats);

enum AppMessageType {
  provideAppType('provide'), // Provider other nodes the version tree
  queryAppType('query'), // Query other nodes for version
  // searchAppType('search'), // Ask for the location of resource
  publishAppType('publish'), // Publish newest resource to other nodes
  offerAppType('offer'), // Generic offer message, currently used for storage
  applyAppType('apply'); // Client apply for storage to server

  final String value;
  const AppMessageType(this.value);
}

const String offerTypeStorage = 'storage';
const String applyTypeVersion = 'version';
const String applyTypeVersionsKey = 'versions';

class VillageMessageHandler {
  OnHandleStringWithPublicKeyFunction? handleProvide;
  OnHandleStringWithPublicKeyFunction? handleQuery;
  OnHandleStringWithPublicKeyFunction? handlePublish;
  OnHandleStringWithPublicKeyFunction? handleOffer;
  OnHandleStringWithPublicKeyFunction? handleApply;
}

class UncipherMessage {
  String userPublicId;
  String data;
  String signature;

  UncipherMessage({
    required this.userPublicId,
    required this.data,
    required this.signature,
  });

  UncipherMessage.fromJson(Map<String, dynamic> map):
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

class CipherMessage {
  String key;
  String subKey;
  int timestamp;
  String data;
  String signature;

  CipherMessage({
    required this.key,
    required this.subKey,
    required this.timestamp,
    required this.data,
    required this.signature,
  });

  CipherMessage.fromRaw(UnsignedResource raw, String signature):
        key = raw.key,
        subKey = raw.subKey,
        timestamp = raw.timestamp,
        data = raw.data,
        signature = signature;
  CipherMessage.fromJson(Map<String, dynamic> map):
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

class CipherMessages {
  String userPublicId;
  List<CipherMessage> resources;
  String signature;

  CipherMessages({
    required this.userPublicId,
    required this.resources,
    required this.signature,
  });

  static String getFeature(List<CipherMessage> resources) {
    String feature = '';
    for(var r in resources) {
      String json = jsonEncode(r);
      feature += 'resource: $json\n';
    }
    return feature;
  }

  CipherMessages.fromJson(Map<String, dynamic> map):
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

  static List<CipherMessage> _recursiveList(List<dynamic> list) {
    List<CipherMessage> result = [];
    for(var item in list) {
      CipherMessage cipherMessage = CipherMessage.fromJson(item);
      result.add(cipherMessage);
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

class UserPrivateInfo {
  static const String guestKey = 'guest';
  String publicKey;
  String userName;
  String privateKey;
  int timestamp;

  UserPrivateInfo({
    required this.publicKey,
    required this.userName,
    required this.privateKey,
    required this.timestamp,
  });

  UserPrivateInfo.makeGuest({required int timestamp}):
        publicKey = guestKey,
        userName = guestKey,
        privateKey = guestKey,
        timestamp = timestamp;

  bool isGuest() {
    return privateKey == guestKey;
  }
}

class TimeCostStatistics {
  int startTime;
  int transportTime;
  int receiveTime;
  int finishTime;
  int versionTreeCost;
  int requiredVersionsCost;
  int versionCost;

  TimeCostStatistics({
    this.startTime = 0,
    this.transportTime = 0,
    this.receiveTime = 0,
    this.finishTime = 0,
    this.versionTreeCost = 0,
    this.requiredVersionsCost = 0,
    this.versionCost = 0,
  });
}

class Offer {
  String type;
  String target;
  Map<String, dynamic> data;

  Offer({
    required this.type,
    required this.target,
    required this.data,
  });

  Offer.fromJson(Map<String, dynamic> map):
        type = map['type']?? '',
        target = map['target']?? '',
        data = Map<String, dynamic>.from(map['data'] as Map);

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'target': target,
      'data': data,
    };
  }
}

class Apply {
  String type;
  Map<String, dynamic> data;

  Apply({
    required this.type,
    required this.data,
  });

  Apply.fromJson(Map<String, dynamic> map):
        type = map['type']?? '',
        data = Map<String, dynamic>.from(map['data'] as Map);

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
    };
  }
}
