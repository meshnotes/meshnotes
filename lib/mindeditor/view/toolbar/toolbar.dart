import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/mindeditor/view/toolbar/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/block_checked_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/block_listing_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/coloring_text_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/icon_and_text_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/strikethrough_text_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/underline_text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:my_log/my_log.dart';
import 'block_type_button.dart';
import 'bold_text_button.dart';
import 'copy_paste_button.dart';
import 'keyboard_button.dart';
import 'italic_text_button.dart';

class MindToolBar extends StatelessWidget {
  final Controller controller;
  final double toolBarHeight;
  final List<Widget> children;
  final AppearanceSetting appearance;

  const MindToolBar({
    Key? key,
    required this.controller,
    this.toolBarHeight = 36,
    required this.children,
    required this.appearance,
  }): super(key: key);

  factory MindToolBar.basic({
    Key? key,
    required Controller controller,
    required BuildContext context,
  }) {
    AppearanceSetting defaultAppearance = _buildDefaultAppearance(context);
    var buttons = <Widget>[
      IconAndTextButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      BoldTextButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      ItalicTextButton(
        appearance: defaultAppearance,
        controller: controller
      ),
      UnderlineTextButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      StrikethroughTextButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      CopyButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      CutButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      PasteButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
      BlockListingButton(
        controller: controller,
        appearance: defaultAppearance,
        listing: Constants.blockListTypeBulleted,
        icon: const Icon(Icons.format_list_bulleted),
        tips: 'Bulleted List',
      ),
      // BlockTypeButton2.fromTitle(
      //   controller: controller,
      //   appearance: defaultAppearance,
      //   type: Constants.blockTypeTextTag,
      //   title: 'T',
      //   tips: 'Text'
      // ),
      BlockCheckedButton(
        controller: controller,
        appearance: defaultAppearance,
        icon: const Icon(Icons.check_box_rounded),
        tips: 'Checked list',
        listing: Constants.blockListTypeChecked,
      ),
      BlockTypeButton.fromTitle(
        controller: controller,
        appearance: defaultAppearance,
        type: Constants.blockTypeHeadline1,
        title: 'H1',
        tips: 'Headline 1',
      ),
      BlockTypeButton.fromTitle(
        controller: controller,
        appearance: defaultAppearance,
        type: Constants.blockTypeHeadline2,
        title: 'H2',
        tips: 'Headline 2'
      ),
      BlockTypeButton.fromTitle(
        controller: controller,
        appearance: defaultAppearance,
        type: Constants.blockTypeHeadline3,
        title: 'H3',
        tips: 'Headline 3'
      ),
      ColoringTextButton(
        appearance: defaultAppearance,
        controller: controller,
      ),
    ];
    return MindToolBar(
      key: key,
      controller: controller,
      children: buttons,
      appearance: defaultAppearance,
    );
  }

  static AppearanceSetting _buildDefaultAppearance(BuildContext context) {
    if(Controller().environment.isMobile()) {
      return AppearanceSetting(
        iconSize: 28,
        size: 32,
        fillColor: Theme.of(context).canvasColor,
        hoverColor: Theme.of(context).colorScheme.background,
      );
    }
    return AppearanceSetting(
      iconSize: 18,
      size: 36,
      fillColor: Theme.of(context).canvasColor,
      hoverColor: Theme.of(context).colorScheme.background,
    );
  }

  @override
  Widget build(BuildContext context) {
    // var toolbar = Wrap(
    //   // alignment: WrapAlignment.center,
    //   runSpacing: 4,
    //   spacing: 4,
    //   children: children,
    // );
    Widget toolbar = Row(
      children: children,
    );
    if(controller.isDebugMode) {
      toolbar = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.green,
            width: 2,
          ),
        ),
        child: toolbar,
      );
    }
    Widget scroll = _buildScrollable(toolbar);
    List<Widget> pluginButtons = _buildPluginButtons();
    List<Widget> allButtons = [
      Expanded(child: scroll),
      VerticalDivider(
        indent: 8.0,
        endIndent: 8.0,
        width: 1.0,
        thickness: 1.0,
        color: Colors.grey[350],
      ),
      ...pluginButtons,
    ];
    if(controller.environment.isMobile()) {
      Widget hideKeyboardButton = ShowOrHideKeyboardButton(
        appearance: appearance,
        controller: controller,
      );
      allButtons.add(hideKeyboardButton);
      return IntrinsicHeight(
        child: Row(
          children: allButtons,
        ),
      );
    }
    return Row(
      children: allButtons,
    );
  }

  Widget _buildScrollable(Widget toolbar) {
    // 移动端SingleChildScrollView可以直接用手指拖动，桌面端不行，所以桌面端需要加上左右按钮
    if(controller.environment.isDesktop()) {
      return MovableToolbar(child: toolbar, height: toolBarHeight, appearance: appearance,);
    } else {
      Widget scroll = SingleChildScrollView(
        child: toolbar,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(1.0),
      );
      return scroll;
    }
  }

  List<Widget> _buildPluginButtons() {
    var pluginButton = Controller().pluginManager.buildButtons(
      appearance: appearance,
      controller: controller,
    );
    return pluginButton;
  }
}

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

/// 当屏幕空间不够时，显示左右移动按钮，使工具栏可左右滚动
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