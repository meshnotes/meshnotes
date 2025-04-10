import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/block_listing_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/coloring_text_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/icon_and_text_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/strikethrough_text_button.dart';
import 'package:mesh_note/mindeditor/view/toolbar/underline_text_button.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import 'base/movable_button.dart';
import 'block_indent_button.dart';
import 'block_type_button.dart';
import 'bold_text_button.dart';
import 'copy_paste_button.dart';
import 'keyboard_button.dart';
import 'italic_text_button.dart';

class MindEditorToolBar extends StatelessWidget {
  final Controller controller;
  final double toolBarHeight;
  final List<Widget> children;
  final AppearanceSetting appearance;

  const MindEditorToolBar({
    Key? key,
    required this.controller,
    this.toolBarHeight = 36,
    required this.children,
    required this.appearance,
  }): super(key: key);

  factory MindEditorToolBar.basic({
    Key? key,
    required Controller controller,
    required BuildContext context,
  }) {
    AppearanceSetting defaultAppearance = _buildDefaultAppearance(context);
    var buttons = <Widget>[
      IconAndTextButton(
        appearance: defaultAppearance,
        controller: controller,
        text: 'Comment',
        tip: 'Comment',
        onPressed: () {
          MyLogger.debug('IconAndTextButton: Comment pressed');
        },
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
      StrikeThroughTextButton(
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
      BlockIndentDecreaseButton(
        controller: controller,
        appearance: defaultAppearance,
        icon: Icons.format_indent_decrease,
        tips: 'Decrease level',
      ),
      BlockIndentIncreaseButton(
        controller: controller,
        appearance: defaultAppearance,
        icon: Icons.format_indent_increase,
        tips: 'Increase level',
      ),
      BlockListingButton(
        controller: controller,
        appearance: defaultAppearance,
        listing: const [Constants.blockListTypeBulleted],
        targetListing: Constants.blockListTypeBulleted,
        icon: Icons.format_list_bulleted,
        tips: 'Bulleted List',
      ),
      // BlockTypeButton2.fromTitle(
      //   controller: controller,
      //   appearance: defaultAppearance,
      //   type: Constants.blockTypeTextTag,
      //   title: 'T',
      //   tips: 'Text'
      // ),
      BlockListingButton(
        controller: controller,
        appearance: defaultAppearance,
        icon: Icons.check_box_rounded,
        listing: const [Constants.blockListTypeChecked, Constants.blockListTypeCheckedConfirm],
        targetListing: Constants.blockListTypeChecked,
        tips: 'Checked list',
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
    return MindEditorToolBar(
      key: key,
      controller: controller,
      children: buttons,
      appearance: defaultAppearance,
    );
  }

  static AppearanceSetting _buildDefaultAppearance(BuildContext context) {
    // For mobile environment, make the button bigger
    double iconSize = 18;
    double size = 36;
    if(Controller().environment.isMobile()) {
      iconSize = 28;
      size = 32;
    }
    return AppearanceSetting(
      iconSize: iconSize,
      size: size,
      fillColor: Theme.of(context).canvasColor,
      hoverColor: Theme.of(context).colorScheme.surface,
      disabledColor: Theme.of(context).disabledColor,
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
