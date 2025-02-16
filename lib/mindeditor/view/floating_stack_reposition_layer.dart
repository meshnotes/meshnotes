import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:mesh_note/page/widget_templates.dart';

class FloatingStackRepositionView extends StatefulWidget {
  const FloatingStackRepositionView({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => FloatingStackRepositionViewState();
}
class FloatingStackRepositionViewState extends State<FloatingStackRepositionView> {
  Map<String, (Offset, Widget)> views = {};

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    for(var entry in views.entries) {
      final (position, widget) = entry.value;
      children.add(Positioned(
        left: position.dx,
        top: position.dy,
        child: widget,
      ));
    }
    final stack = Stack(
      children: children,
    );
    return WidgetTemplate.buildKeyboardResizableContainer(stack);
  }

  void addLayer(String id, Offset position, Widget _w) {
    setState(() {
      views[id] = (position, _w);
    });
  }
  void updatePosition(String id, Offset position) {
    if(views.containsKey(id)) {
      final (_, widget) = views[id]!;
      setState(() {
        views[id] = (position, widget);
      });
    }
  }
  void clearLayer() {
    setState(() {
      views.clear();
    });
  }
  void removeLayer(String id) {
    setState(() {
      views.remove(id);
    });
  }
}