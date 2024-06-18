import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:flutter/material.dart';

class ToolbarButton extends StatefulWidget {
  final Widget icon;
  final Controller controller;
  final VoidCallback? onPressed;
  final AppearanceSetting appearance;
  final String tip;
  final double? width;
  final double? height;
  final bool isOn;
  final bool isActive;

  const ToolbarButton({
    Key? key,
    required this.icon,
    required this.appearance,
    required this.tip,
    required this.controller,
    required this.onPressed,
    this.isOn = false,
    this.isActive = false,
    this.width,
    this.height,
  }): super(key: key);

  @override
  _ToolbarButtonState createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  late Color backgroundColor;
  late final Color _defaultBackgroundColor;
  late final Color _hoveredBackgroundColor;
  late final Color _triggeredBackgroundColor;

  @override
  void initState() {
    super.initState();
    _defaultBackgroundColor = widget.controller.setting.toolbarButtonDefaultBackgroundColor;
    _hoveredBackgroundColor = widget.controller.setting.toolbarButtonHoverBackgroundColor;
    _triggeredBackgroundColor = widget.controller.setting.toolBarButtonTriggerOnColor;
    backgroundColor = _defaultBackgroundColor;
  }

  @override
  Widget build(BuildContext context) {
    var container = Container(
      constraints: BoxConstraints(
        minWidth: widget.appearance.size,
        minHeight: widget.appearance.size,
      ),
      alignment: Alignment.center,
      color: widget.isOn? _triggeredBackgroundColor: backgroundColor,
      padding: const EdgeInsets.all(4),
      child: widget.icon,
    );
    var mouseRegion = MouseRegion(
      onEnter: (_) {
        setState(() {
          backgroundColor = _hoveredBackgroundColor;
        });
      },
      onExit: (_) {
        setState(() {
          backgroundColor = _defaultBackgroundColor;
        });
      },
      child: container,
    );
    var gesture = GestureDetector(
      child: mouseRegion,
      onTap: widget.onPressed,
    );
    var toolTip = Tooltip(
      message: widget.tip,
      child: gesture,
    );
    return toolTip;
    // return ConstrainedBox(
    //   constraints: BoxConstraints.tightFor(
    //     width: width?? appearance.iconSize + (appearance.size - appearance.iconSize) / 2,
    //     height: height?? appearance.size
    //   ),
    //   child: toolTip,
    // );
  }
}
