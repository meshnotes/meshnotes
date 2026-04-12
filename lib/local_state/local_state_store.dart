import 'package:shared_preferences/shared_preferences.dart';

class LocalStateStore {
  static const String _collapsedDocIdsKey = 'navigator.collapsed_doc_ids';

  final SharedPreferences _preferences;

  LocalStateStore._(this._preferences);

  static Future<LocalStateStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    return LocalStateStore._(preferences);
  }

  Set<String> getCollapsedDocIds() {
    final ids = _preferences.getStringList(_collapsedDocIdsKey) ?? const <String>[];
    return ids.where((item) => item.isNotEmpty).toSet();
  }

  Future<void> setCollapsedDocIds(Set<String> docIds) async {
    final ids = docIds.where((item) => item.isNotEmpty).toList()..sort();
    await _preferences.setStringList(_collapsedDocIdsKey, ids);
  }
}
