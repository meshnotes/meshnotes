import 'dart:convert';

typedef OnHandleStringWithPublicKeyFunction = void Function(String senderPublicKey, String data, TimeCostStatistics stats);
typedef OnHandleStringWithPublicKeyAndTransactionIdFunction = void Function(String senderPublicKey, String data, TimeCostStatistics stats, String transactionId);

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
  OnHandleStringWithPublicKeyAndTransactionIdFunction? handleQueryFromNode;
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

enum TransactionStatus { request, partial, completed, failed }
enum TransactionContentType { cipher, uncipher }

/// Signed transaction envelope. The payload keeps its own original signature contract.
class TransactionMessage {
  final String transactionId;
  final TransactionStatus status;
  final TransactionContentType contentType;
  final String data;
  final int? objectCount;
  final String userPublicId;
  String signature;

  TransactionMessage({required this.transactionId, required this.status, required this.contentType,
    required this.data, required this.userPublicId, required this.signature, this.objectCount}) {
    if(transactionId.isEmpty || userPublicId.isEmpty || (objectCount != null && objectCount! < 0) ||
        (status == TransactionStatus.request && objectCount != null)) {
      throw FormatException('Invalid transaction metadata');
    }
  }

  factory TransactionMessage.fromJson(Map<String, dynamic> map) {
    final status = TransactionStatus.values.where((value) => value.name == map[_statusKey]).firstOrNull;
    final contentType = TransactionContentType.values.where((value) => value.name == map[_contentTypeKey]).firstOrNull;
    if(status == null || contentType == null) {
      throw FormatException('Unknown transaction status/content type');
    }

    return TransactionMessage(
      transactionId: map[_transactionIdKey] as String,
      status: status,
      contentType: contentType,
      data: map[_dataKey] as String,
      userPublicId: map[_userKey] as String,
      signature: map[_signatureKey] as String,
      objectCount: map[_objectCountKey] as int?,
    );
  }

  CipherMessages parseCipher() {
    if(contentType != TransactionContentType.cipher) throw FormatException('Expected cipher payload');
    return CipherMessages.fromJson(jsonDecode(data));
  }

  UncipherMessage parseUncipher() {
    if(contentType != TransactionContentType.uncipher) throw FormatException('Expected uncipher payload');
    return UncipherMessage.fromJson(jsonDecode(data));
  }

  Map<String, dynamic> _signableJson() => {
    _transactionIdKey: transactionId,
    _statusKey: status.name,
    _contentTypeKey: contentType.name,
    _dataKey: data,
    if(objectCount != null) _objectCountKey: objectCount,
    _userKey: userPublicId,
  };

  String toSignableString() => jsonEncode(_signableJson());

  Map<String, dynamic> toJson() => {..._signableJson(), _signatureKey: signature};

  static bool isTransaction(Map<String, dynamic> m) => m.containsKey(_transactionIdKey);
  
  static const String _transactionIdKey = 'transaction_id';
  static const String _statusKey = 'status';
  static const String _contentTypeKey = 'content_type';
  static const String _dataKey = 'data';
  static const String _objectCountKey = 'object_count';
  static const String _userKey = 'user';
  static const String _signatureKey = 'sign';
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

  /// Reuses the caller-deduplicated list, without copying or changing batch granularity.
  static CipherMessages queryResponse(String userPublicId, List<CipherMessage> resources) {
    return CipherMessages(userPublicId: userPublicId, resources: resources, signature: '');
  }

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

  String getSignableFeature() => getFeature(resources);

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
