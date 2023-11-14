import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';

class InspiredSeed {
  List<(String, String)> ids;
  Map<String, ParagraphDesc> cache = {};

  InspiredSeed({
    required this.ids,
  });
}
