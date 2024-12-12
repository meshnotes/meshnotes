import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:mesh_note/util/ui_widgets.dart';

class FloatingStackView extends StatefulWidget {
  const FloatingStackView({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => FloatingStackViewState();
}
class FloatingStackViewState extends State<FloatingStackView> {
  List<Widget> views = [];

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      children: views,
    );
    return WidgetTemplate.buildKeyboardResizableContainer(stack);
  }

  void addLayers(Widget _w1, Widget _w2) {
    setState(() {
      views.addAll([_w1, _w2]);
    });
  }
  void addLayer(Widget _w) {
    setState(() {
      views.add(_w);
    });
  }
  void clearLayer() {
    setState(() {
      views.clear();
    });
  }
  void removeLayer(Widget _w) {
    setState(() {
      views.remove(_w);
    });
  }
}