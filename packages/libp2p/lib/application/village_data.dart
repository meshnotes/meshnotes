class VillageData {
  String userId;
  String appId;
  String key;
  String version;
  String basedVersion;
  String data;

  VillageData({
    required this.userId,
    required this.appId,
    required this.key,
    required this.version,
    required this.basedVersion,
    required this.data,
  });
}

enum VillageObjectStatus {
  waiting,
  ready,
}

class VillageObject {
  String objHash;
  String? objData;
  VillageObjectStatus status;

  VillageObject({
    required this.objHash,
    this.status = VillageObjectStatus.waiting,
  });

  void setData(String data) {
    objData = data;
  }
}