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

class BlockStructure {
  String blockId;
  List<BlockStructure>? children;

  BlockStructure({
    required this.blockId,
    this.children,
  });

  Map<String, dynamic> toJson() {
    return {
      'block_id': blockId,
      'children': children,
    };
  }
  BlockStructure.fromJson(Map<String, dynamic> map): blockId = map['block_id'], children = recursiveBuild(map['children']);

  static List<BlockStructure>? recursiveBuild(List<dynamic>? list) {
    if(list == null) {
      return null;
    }
    var result = <BlockStructure>[];
    for(final item in list) {
      BlockStructure block = BlockStructure.fromJson(item);
      result.add(block);
    }
    return result;
  }
}