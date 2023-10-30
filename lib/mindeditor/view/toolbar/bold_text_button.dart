import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/switch_button_state.dart';
import 'package:flutter/material.dart';
import '../../document/paragraph_desc.dart';
import 'appearance_setting.dart';

class BoldTextButton extends StatelessWidget {
  final AppearanceSetting appearance;
  final Controller controller;

  const BoldTextButton({
    Key? key,
    required this.controller,
    required this.appearance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ToolbarSwitchButton(
      icon: Icon(Icons.format_bold, size: appearance.iconSize),
      appearance: appearance,
      controller: controller,
      tip: 'Bold',
      initCallback: (Function(bool) _setOn) {
        CallbackRegistry.registerSelectionChangedWatcher('bold', (TextSpansStyle? style) {
          if(style == null) {
            MyLogger.debug('efantest: style is null');
            _setOn(false);
            return;
          }
          if(style.isAllBold) {
            MyLogger.debug('efantest: bold is on');
            _setOn(true);
          } else {
            MyLogger.debug('efantest: bold is off');
            _setOn(false);
          }
        });
      },
      destroyCallback: () {
        CallbackRegistry.unregisterDocumentChangedWatcher('bold');
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        var isBold = blockState?.triggerSelectedBold();
        CallbackRegistry.requestFocus();
        return isBold?? false;
      },
    );
  }
}