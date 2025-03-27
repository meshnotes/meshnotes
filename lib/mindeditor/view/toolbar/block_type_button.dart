import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/block_format_button.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';

class BlockTypeButton extends StatelessWidget {
  final Controller controller;
  final AppearanceSetting appearance;
  final Widget icon;
  final String tips;
  final String type;

  const BlockTypeButton({
    super.key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tips,
    required this.type,
  });

  BlockTypeButton.fromTitle({
    super.key,
    required this.controller,
    required this.appearance,
    required this.tips,
    required this.type,
    required String title,
  }): icon = Text(
    title,
    style: TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: appearance.iconSize,
    )
  );

  @override
  Widget build(BuildContext context) {
    return BlockFormatButton(
      controller: controller,
      appearance: appearance,
      iconWidget: icon,
      tip: tips,
      activeOrNot: (String? _type, String? _listing, int? _level) {
        return type == _type;
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        if(blockState == null) {
          MyLogger.debug('Unable to set block type: current editing block state is null!');
          return;
        }
        var newType = type;
        var currentType = blockState.getBlockType();
        if(currentType == type) { // Clear the block type if selected again
          newType = Constants.blockTypeTextTag;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s type to: $newType');
        var ok = blockState.setBlockType(newType);
        if(ok) {
          var block = blockState.widget.texts;
          var blockId = block.getBlockId();
          var pos = 0;
          if(block.getTextSelection() != null) {
            pos = block.getTextSelection()!.extentOffset;
          }
          CallbackRegistry.refreshDoc(activeBlockId: blockId, position: pos);
        }
      },
      buttonKey: type,
    );
  }

}