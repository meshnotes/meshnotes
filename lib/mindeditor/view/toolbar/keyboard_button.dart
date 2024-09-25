import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';

import 'base/multi_states_button.dart';


enum KeyboardButtonActionState {
  unavailable,
  showKeyboard,
  hideKeyboard,
}

class ShowOrHideKeyboardButton extends StatefulWidget {
  final AppearanceSetting appearance;
  final Controller controller;
  final bool initallyShowOrNot;

  const ShowOrHideKeyboardButton({
    Key? key,
    required this.controller,
    required this.appearance,
    this.initallyShowOrNot = true,
  }): super(key: key);

  @override
  State<StatefulWidget> createState() => _ShowOrHideKeyboardButtonState();
}

class _ShowOrHideKeyboardButtonState extends State<ShowOrHideKeyboardButton> {
  final Map<KeyboardButtonActionState, String> tips = {
    KeyboardButtonActionState.unavailable: 'Keyboard unavailable',
    KeyboardButtonActionState.showKeyboard: 'Show keyboard',
    KeyboardButtonActionState.hideKeyboard: 'Hide keyboard',
  };
  final Map<KeyboardButtonActionState, IconData> icons = {
    KeyboardButtonActionState.unavailable: Icons.keyboard,
    KeyboardButtonActionState.showKeyboard: Icons.keyboard,
    KeyboardButtonActionState.hideKeyboard: Icons.keyboard_hide,
  };
  final Map<KeyboardButtonActionState, Function()?> handlers = {};
  final StateNotifier<KeyboardButtonActionState> keyboardStateNotifier = StateNotifier<KeyboardButtonActionState>(KeyboardButtonActionState.showKeyboard);

  @override
  void initState() {
    super.initState();
    handlers[KeyboardButtonActionState.unavailable] = null;
    handlers[KeyboardButtonActionState.showKeyboard] = _onShowKeyboard;
    handlers[KeyboardButtonActionState.hideKeyboard] = _onHideKeyboard;
    widget.controller.uiEventManager.addKeyboardStateOpenTask((isOpen) {
      if(isOpen) {
        keyboardStateNotifier.setValue(KeyboardButtonActionState.hideKeyboard);
      } else {
        keyboardStateNotifier.setValue(KeyboardButtonActionState.showKeyboard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiStatesButton<KeyboardButtonActionState>(
      states: keyboardStateNotifier,
      tips: tips,
      icons: icons,
      handlers: handlers,
      appearance: widget.appearance,
      controller: widget.controller,
    );
  }

  void _onShowKeyboard() {
    MyLogger.info('show keyboard pressed');
    CallbackRegistry.showKeyboard();
  }

  void _onHideKeyboard() {
    MyLogger.info('hide keyboard pressed');
    CallbackRegistry.hideKeyboard();
  }
}