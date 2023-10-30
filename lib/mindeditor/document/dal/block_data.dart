class BlockData {
  final String docId;
  final String id;
  final String? nextId;
  final String data;
  final String type;
  final String listing;
  final int level;

  BlockData({
    required this.docId,
    required this.id,
    required this.nextId,
    required this.data,
    required this.type,
    required this.listing,
    required this.level,
  });
}

class BlockItem {
  final String blockId;
  final String data;
  final int updatedAt;

  BlockItem({
    required this.blockId,
    required this.data,
    required this.updatedAt,
  });
}