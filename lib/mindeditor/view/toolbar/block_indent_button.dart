import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/block_format_button.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';

class BlockIndentIncreaseButton extends StatelessWidget {
  final Controller controller;
  final AppearanceSetting appearance;
  final IconData icon;
  final String tips;
  static const int maxLevel = 5;

  const BlockIndentIncreaseButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tips,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlockFormatButton(
      controller: controller,
      appearance: appearance,
      iconData: icon,
      tip: tips,
      availableOrNot: (String? _type, String? _listing, int? _level) { // Available only when level is less than maxLevel
        return _level == null || _level < maxLevel; // null means level 0
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        if(blockState == null) {
          MyLogger.debug('Unable to increase block level: current editing block state is null!');
          return;
        }
        var currentLevel = blockState.getBlockLevel();
        var newLevel = currentLevel + 1;
        if(newLevel >= maxLevel) {
          newLevel = maxLevel;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s level to: $newLevel');
        var ok = blockState.setBlockLevel(newLevel);
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
      buttonKey: 'increase_indent',
    );
  }
}

class BlockIndentDecreaseButton extends StatelessWidget {
  final Controller controller;
  final AppearanceSetting appearance;
  final IconData icon;
  final String tips;
  static const int maxLevel = 5;

  const BlockIndentDecreaseButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tips,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlockFormatButton(
      controller: controller,
      appearance: appearance,
      iconData: icon,
      tip: tips,
      availableOrNot: (String? _type, String? _listing, int? _level) { // Available only when level is greater than 0
        return _level != null && _level > 0; // null means level 0
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        if(blockState == null) {
          MyLogger.debug('Unable to increase block level: current editing block state is null!');
          return;
        }
        var currentLevel = blockState.getBlockLevel();
        var newLevel = currentLevel - 1;
        if(newLevel <= 0) {
          newLevel = 0;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s level to: $newLevel');
        var ok = blockState.setBlockLevel(newLevel);
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
      buttonKey: 'decrease_indent',
    );
  }
}