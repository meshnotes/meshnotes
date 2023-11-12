typedef OnHandleNewVersion = Function(String versionHash, String versionStr, Map<String, String> objects);

const String VersionTreeAppType = 'version_tree';


class VersionChain {
  String versionHash;
  String versionStr;
  List<String> parents;
  Map<String, String> requiredObjects;

  VersionChain({
    required this.versionHash,
    required this.versionStr,
    required this.parents,
    required this.requiredObjects,
  });

  VersionChain.fromJson(Map<String, dynamic> map):
        versionHash = map['hash'],
        versionStr = map['value'],
        parents = _recursiveList(map['parents']),
        requiredObjects = _recursiveMap(map['objects']);

  Map<String, dynamic> toJson() {
    return {
      'hash': versionHash,
      'value': versionStr,
      'parents': parents,
      'objects': requiredObjects,
    };
  }

  static List<String> _recursiveList(List<dynamic> list) {
    final result = <String>[];
    for(var item in list) {
      result.add(item as String);
    }
    return result;
  }
  static Map<String, String> _recursiveMap(Map<String, dynamic> map) {
    final result = <String, String>{};
    for(var entry in map.entries) {
      result[entry.key] = entry.value as String;
    }
    return result;
  }
}