import 'package:mesh_note/mindeditor/document/dal/doc_data_model.dart';
import 'package:mesh_note/mindeditor/document/document_manager.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:test/test.dart';

void main() {
  test('filter unreachable versions', () {
    /// n1-->n2-->n3-->n4-->newest
    ///      |   ^     |
    ///      |  /      +-->n6
    ///      n5
    var newestHash = 'newest';
    List<VersionDataModel> versions = [
      VersionDataModel(versionHash: newestHash, parents: 'n4', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
      VersionDataModel(versionHash: 'n4', parents: 'n3', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
      VersionDataModel(versionHash: 'n3', parents: 'n2,n5', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
      VersionDataModel(versionHash: 'n2', parents: 'n1', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
      VersionDataModel(versionHash: 'n5', parents: 'n2', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
      VersionDataModel(versionHash: 'n1', parents: '', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
      VersionDataModel(versionHash: 'n6', parents: 'n4', createdAt: 0, createdFrom: Constants.createdFromLocal, status: Constants.statusAvailable, syncStatus: Constants.syncStatusNew),
    ];
    final result = DocumentManager.filterUnreachableVersions(versions, newestHash);
    expect(result.length, 6);
    for(final node in result) {
      expect(node.versionHash != 'n6', true);
    }
  });
}