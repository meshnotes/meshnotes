import 'villager_node.dart';

typedef OnNodeChangedCallbackType = Function(VillagerNode node);

class AppData {
  String app;
  String type;
  String data;

  AppData(this.app, this.type, this.data);

  AppData.fromJson(Map<String, dynamic> json): app = json['app'], type = json['type'], data = json['data'];

  Map<String, dynamic> toJson() => {
    'app': app,
    'type': type,
    'data': data,
  };
}