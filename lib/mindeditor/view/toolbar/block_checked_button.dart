import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/block_format_button.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';

class BlockCheckedButton extends StatelessWidget {
  final Controller controller;
  final AppearanceSetting appearance;
  final IconData icon;
  final String tips;
  final String listing;

  const BlockCheckedButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tips,
    required this.listing,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlockFormatButton(
      controller: controller,
      appearance: appearance,
      iconData: icon,
      tip: tips,
      activeOrNot: (String? _type, String? _listing, int? _level) {
        return listing == _listing;
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        if(blockState == null) {
          MyLogger.debug('Unable to set block listing: current editing block state is null!');
          return;
        }
        var newListing = listing;
        var currentListing = blockState.getBlockListing();
        if(currentListing == listing) { // 重复点击将清除列表
          newListing = Constants.blockListTypeNone;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s listing to: $newListing');
        var ok = blockState.setBlockListing(newListing);
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
      buttonKey: listing,
    );
  }

}