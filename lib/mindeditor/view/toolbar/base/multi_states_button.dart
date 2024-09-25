import 'package:flutter/widgets.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:my_log/my_log.dart';

import '../appearance_setting.dart';
import 'toolbar_button.dart';

class StateNotifier<T> {
  T? _value;

  StateNotifier(T value): _value = value;

  Function(T)? listener;

  void addListener(Function(T) listener) {
    this.listener = listener;
  }

  void setValue(T value) {
    _value = value;
    listener?.call(value);
  }

  T? getValue() => _value;
}

class MultiStatesButton<T> extends StatefulWidget {
  final StateNotifier<T> states;
  final Map<T, Function()?> handlers;
  final Map<T, IconData> icons;
  final Map<T, String> tips;
  final AppearanceSetting appearance;
  final Controller controller;

  const MultiStatesButton({
    super.key,
    required this.states,
    required this.handlers,
    required this.icons,
    required this.tips,
    required this.appearance,
    required this.controller,
  });

  @override
  State<MultiStatesButton<T>> createState() => _MultiStatesButtonState<T>();  
}

class _MultiStatesButtonState<T> extends State<MultiStatesButton<T>> {
  T? currentState;

  @override
  void initState() {
    super.initState();
    widget.states.addListener(_onStateChange);
    currentState = widget.states.getValue();
  }

  @override
  Widget build(BuildContext context) {
    if(currentState == null) return _buildEmptyButton();

    final iconData = widget.icons[currentState];
    final onPressed = widget.handlers[currentState];
    final tip = widget.tips[currentState];
    if(iconData == null || tip == null) return _buildEmptyButton();
    
    return ToolbarButton(
      icon: Icon(iconData),
      appearance: widget.appearance,
      controller: widget.controller,
      tip: tip,
      onPressed: onPressed,
    );
  }

  Widget _buildEmptyButton() => Container();

  void _onStateChange(T value) {
    MyLogger.info('state change to $value');
    setState(() {
      currentState = value;
    });
  }
}
