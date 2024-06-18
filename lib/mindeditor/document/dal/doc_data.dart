class BlockData {
  final String blockId;
  final String blockData;
  final int updatedAt;

  BlockData({
    required this.blockId,
    required this.blockData,
    required this.updatedAt,
  });
}

class DocData {
  String docId;
  String title;
  String hash;
  int timestamp;

  DocData({
    required this.docId,
    required this.title,
    required this.hash,
    required this.timestamp,
  });
}

class DocContentData {
  String docId;
  String docContent;
  int timestamp;

  DocContentData({
    required this.docId,
    required this.docContent,
    required this.timestamp,
  });
}

class VersionData {
  String versionHash;
  String parents;
  int createdAt;

  VersionData({
    required this.versionHash,
    required this.parents,
    required this.createdAt,
  });
}

class ObjectData {
  String key;
  String data;
  int timestamp;

  ObjectData({
    required this.key,
    required this.data,
    required this.timestamp,
  });
}