import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/mind_editor.dart';
import 'package:mesh_note/page/menu.dart';
import 'package:mesh_note/page/resizable_view.dart';
import 'package:mesh_note/page/title_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../mindeditor/controller/controller.dart';

class DocumentView extends StatelessWidget with ResizableViewMixin {
  final Function()? jumpAction;
  @override
  bool get expectedSmallView => smallView;
  @override
  String get loggingClassName => "DocumentView";

  static bool lastSmallView = false;
  final bool smallView;
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey();
  final controller = Controller();

  DocumentView({
    Key? key,
    this.jumpAction,
    this.smallView = false,
  }) : super(key: key) {
    CallbackRegistry.registerMessengerKey(messengerKey);
  }

  @override
  Widget build(BuildContext context) {
    if(smallView && jumpAction == null) {
      routeIfResize(context);
    }
    Widget editor = getMindEditor();
    // editor = ScaffoldMessenger(
    //   key: messengerKey,
    //   child: editor,
    // );
    final view = Scaffold(
      appBar: _buildAppBar(context, smallView),
      body: editor,
    );
    // if(lastSmallView != smallView) { // Refresh UI if window size changed
    //   // if (controller.document != null) {
    //   //   controller.openDocumentForUi();
    //   // }
    // }
    lastSmallView = smallView;
    return view;
  }

  Widget getMindEditor() {
    return const Center(
      child: MindEditor(),
    );
  }

  AppBar _buildAppBar(BuildContext context, bool smallView) {
    var titleBar = DocumentTitleBar(controller: controller);
    var actionBar = <Widget>[
      MainMenu(controller: controller, menuType: MenuType.editor),
    ];
    final leading = smallView? Center(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        child: const Icon(Icons.arrow_back_ios),
        onPressed: () {
          if(jumpAction != null) {
            jumpAction!();
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
    ) : null;
    final titleSpacing = smallView? 0.0 : null; // On small view, there will be an icon on the left, so spacing is not necessary
    
    return AppBar(
      titleSpacing: titleSpacing,
      backgroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 48,
      leading: leading, 
      title: titleBar,
      actions: actionBar,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: Colors.grey.withOpacity(0.2),
          height: 1.0,
        )
      ),
    );
  }
}
