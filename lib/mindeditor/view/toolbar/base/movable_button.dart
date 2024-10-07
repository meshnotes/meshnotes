import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:my_log/my_log.dart';
import 'appearance_setting.dart';

class MovableToolbar extends StatefulWidget {
  final Widget child;
  final double height;
  final AppearanceSetting appearance;

  const MovableToolbar({
    Key? key,
    required this.child,
    required this.height,
    required this.appearance,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _MovableToolbarState();
}

/// When the screen width is not adequate, show move buttons to scroll left and right
class _MovableToolbarState extends State<MovableToolbar> {
  double position = 0;
  double windowWidth = 0;
  double toolbarWidth = 0;
  ScrollController scrollController = ScrollController();
  static const double step = 10;

  @override
  Widget build(BuildContext context) {
    Widget measure = MeasureSize(
        child: widget.child,
        onChange: (Size size) {
          MyLogger.verbose('Measure Toolbar size=$size');
          Controller().setToolbarHeight(size.height);
          onToolbarSize(size.width);
        }
    );
    Widget scroll = SingleChildScrollView(
      child: measure,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(1.0),
      controller: scrollController,
    );
    Widget layout = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        MyLogger.verbose('Toolbar constraint width=${constraints.maxWidth}');
        var newWidth = constraints.maxWidth;
        if(windowWidth != newWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onResize(newWidth);
          });
        }
        List<Widget> children = [];
        if(position != 0) {
          Widget leftArrow = Align(
            alignment: Alignment.centerLeft,
            child: _MoveScrollButton(
              child: const Icon(Icons.arrow_left),
              onPressed: () {
                onMove(-step);
              },
              onLongPressed: () {
                onMove(-windowWidth);
              },
              height: widget.height,
              color: widget.appearance.hoverColor,
            ),
          );
          children.add(leftArrow);
        }
        if(windowWidth != 0 && position + windowWidth < toolbarWidth) {
          Widget rightArrow = Align(
            alignment: Alignment.centerRight,
            child: _MoveScrollButton(
              child: const Icon(Icons.arrow_right),
              onPressed: () {
                onMove(step);
              },
              onLongPressed: () {
                onMove(windowWidth);
              },
              height: widget.height,
              color: widget.appearance.hoverColor,
            ),
          );
          children.add(rightArrow);
        }
        children.insert(0, scroll);
        Widget stack = Stack(
          children: children,
        );
        return stack;
      },
    );
    return layout;
  }

  void onResize(double width) {
    setState(() {
      windowWidth = width;
      if(windowWidth >= toolbarWidth) {
        position = 0;
        scrollController.jumpTo(0);
      }
    });
  }
  void onToolbarSize(double width) {
    setState(() {
      toolbarWidth = width;
      if(windowWidth >= toolbarWidth) {
        position = 0;
        scrollController.jumpTo(0);
      }
    });
  }
  void onMove(double step) {
    var pos = scrollController.offset;
    pos += step;
    if(pos + windowWidth > toolbarWidth) {
      pos = toolbarWidth - windowWidth;
    }
    if(pos < 0) {
      pos = 0;
    }
    scrollController.jumpTo(pos);
    setState(() {
      position = pos;
    });
  }
}

class _MoveScrollButton extends StatefulWidget {
  final double height;
  final Function() onPressed;
  final Function() onLongPressed;
  final Widget child;
  final Color color;

  const _MoveScrollButton({
    required this.height,
    required this.onPressed,
    required this.onLongPressed,
    required this.child,
    required this.color,
  });

  @override
  State<StatefulWidget> createState() => _MoveScrollButtonState();
}
class _MoveScrollButtonState extends State<_MoveScrollButton> {
  @override
  Widget build(BuildContext context) {
    var container = Container(
      child: widget.child,
      height: widget.height,
      color: widget.color,
    );
    var gesture = GestureDetector(
      child: container,
      onTap: widget.onPressed,
      onLongPress: widget.onLongPressed,
    );
    return gesture;
  }

}

typedef OnWidgetSizeChange = Function(Size);

class MeasureSizeRenderObject extends RenderProxyBox {
  Size? oldSize;
  final OnWidgetSizeChange onChange;

  MeasureSizeRenderObject(this.onChange);

  @override
  void performLayout() {
    super.performLayout();

    Size newSize = child!.size;
    if(oldSize == newSize) return;

    oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(newSize);
    });
  }
}

class MeasureSize extends SingleChildRenderObjectWidget {
  final OnWidgetSizeChange onChange;

  const MeasureSize({
    Key? key,
    required this.onChange,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return MeasureSizeRenderObject(onChange);
  }
}