import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/block_format_button.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';

class BlockIndentIncreaseButton extends StatelessWidget {
  final Controller controller;
  final AppearanceSetting appearance;
  final IconData icon;
  final String tips;

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
        return _level == null || _level < controller.setting.blockMaxLevel; // null means level 0
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        if(blockState == null) {
          MyLogger.debug('Unable to increase block level: current editing block state is null!');
          return;
        }
        var currentLevel = blockState.getBlockLevel();
        var newLevel = currentLevel + 1;
        if(newLevel > controller.setting.blockMaxLevel) {
          return;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s level to: $newLevel');
        blockState.setBlockLevel(newLevel);
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
        if(newLevel < 0) {
          return;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s level to: $newLevel');
        blockState.setBlockLevel(newLevel);
      },
      buttonKey: 'decrease_indent',
    );
  }
}