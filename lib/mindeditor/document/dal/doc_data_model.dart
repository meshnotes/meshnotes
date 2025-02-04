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
  int isPrivate;
  int timestamp;

  DocDataModel({
    required this.docId,
    required this.title,
    this.hash = ModelConstants.hashEmpty,
    this.isPrivate = ModelConstants.isPrivateNo,
    required this.timestamp,
  });
}

class DocContentDataModel {
  String docId;
  String docContent;
  String docHash;
  int isPrivate;
  int timestamp;

  DocContentDataModel({
    required this.docId,
    required this.docContent,
    required this.docHash,
    required this.isPrivate,
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

  List<String> getParentsList() => parents.split(',');
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

class ModelConstants {
  // Place holder for empty hash
  static const String hashEmpty = '';

  // private field for documents table
  static const int isPrivateNo = 0;
  static const int isPrivateYes = 1;

  // Status in objects table and versions table(including sync_objects and sync_versions)
  static const int statusAvailable = 0; // data is available, created from local or already sync from peer
  static const int statusWaiting = -1; // meta data is sync from peer in a short time, but waiting detail data
  static const int statusDeprecated = -2; // data is deprecated from local or peer, all its parents will be deprecated
  static const int statusMissing = -3; // data sync failed for several times, so it is considered to be missing, will try later
}