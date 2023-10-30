import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../document/paragraph_desc.dart';
import 'controller.dart';

class DocControlNode {
  // 结构性成员
  DocControlNode? firstChild, lastChild;
  DocControlNode? parent;
  DocControlNode? previous;
  DocControlNode? next;
  // 内容性成员
  final String blockId;
  TextSelection? _editingPosition;

  DocControlNode(String _id): blockId = _id;





}
//
// class EditingPosition {
//   TextSelection textSelection;
//   int index = 0;
//   int offset = 0;
//
//   EditingPosition(int _pos): textSelection = TextSelection.collapsed(offset: _pos);
// }