import 'db_helper.dart';
import 'doc_data.dart';

class FakeDbHelper implements DbHelper {
  @override
  Future<void> init() async {}
  @override
  void storeDocHash(String docId, String hash, int timestamp) {}
  @override
  void storeDocContent(String docId, String docContent, int timestamp) {}
  @override
  void storeDocBlock(String docId, String blockId, String data, int timestamp) {}
  @override
  void updateDocBlockExtra(String docId, String blockId, String extra) {}
  @override
  Future<void> dropDocBlock(String docId, String id) async {}
  @override
  DocContentData? getDoc(String docId) { return null; }
  @override
  Map<String, BlockData> getBlockMapOfDoc(String docId) { return {}; }
  @override
  Future<void> updateParagraphType(String docId, String id, String type) async {}
  @override
  Future<void> updateParagraphListing(String docId, String id, String listing) async {}
  @override
  Future<void> updateParagraphLevel(String docId, String id, int level) async {}
  @override
  Future<void> updateDoc(String docId, int timestamp) async {}
  @override
  VersionData? getVersionData(String versionHash) { return null; }
  @override
  List<VersionData> getAllVersions() { return <VersionData>[]; }
  @override
  List<String> getAllValidVersionHashes() { return []; }
  @override
  Map<String, String> getAllTitles() { return <String, String>{}; }
  @override
  List<DocData> getAllDocuments() { return <DocData>[]; }
  @override
  ObjectData? getObject(String hash) { return null; }
  @override
  void storeObject(String hash, String data, int updatedAt) {}
  @override
  void storeVersion(String hash, String parents, int timestamp) {}
  @override
  String getFlag(String name) { return ''; }
  @override
  void setFlag(String name, String value) {}
  @override
  String newDocument(int timestamp) { return ''; }
  @override
  void insertOrUpdateDoc(String docId, String docHash, int timestamp) {}
  @override
  List<(String, String)> getAllBlocks() { return []; }
  @override
  BlockData? getRawBlockById(String docId, String blockId) { return null; }
  @override
  Map<String, String> getSettings() { return {}; }
  @override
  bool saveSettings(Map<String, String> settings) { return true; }
}