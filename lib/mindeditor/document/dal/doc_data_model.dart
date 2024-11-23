class BlockDataModel {
  final String blockId;
  final String blockData;
  final int updatedAt;
  final String blockExtra;

  BlockDataModel({
    required this.blockId,
    required this.blockData,
    required this.updatedAt,
    required this.blockExtra,
  });
}

class DocDataModel {
  String docId;
  String title;
  String hash;
  int timestamp;

  DocDataModel({
    required this.docId,
    required this.title,
    required this.hash,
    required this.timestamp,
  });
}

class DocContentDataModel {
  String docId;
  String docContent;
  int timestamp;

  DocContentDataModel({
    required this.docId,
    required this.docContent,
    required this.timestamp,
  });
}

class VersionDataModel {
  String versionHash;
  String parents;
  int createdAt;
  int createdFrom;
  int status;
  int syncStatus;

  VersionDataModel({
    required this.versionHash,
    required this.parents,
    required this.createdAt,
    required this.createdFrom,
    required this.status,
    required this.syncStatus,
  });
}

class ObjectDataModel {
  String key;
  String data;
  int timestamp;
  int createdFrom;
  int status;

  ObjectDataModel({
    required this.key,
    required this.data,
    required this.timestamp,
    required this.createdFrom,
    required this.status,
  });
}