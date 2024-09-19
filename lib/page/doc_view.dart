import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/mind_editor.dart';
import 'package:mesh_note/page/resizable_view.dart';
import 'package:mesh_note/page/title_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../mindeditor/controller/controller.dart';

class DocumentView extends StatelessWidget with ResizableViewMixin {
  static const screenShotKey = 'screenshot';
  static const searchKey = 'search';
  static const syncKey = 'sync';

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
    Widget? view;
    var titleBar = DocumentTitleBar(controller: controller);
    var actionBar = <Widget>[
      PopupMenuButton(
        onSelected: (value) {
          switch(value) {
            case screenShotKey:
              CallbackRegistry.triggerScreenShot();
              break;
            case searchKey:
              //TODO add search code here
              break;
            case syncKey:
              controller.tryToSaveAndSendVersionTree();
              break;
          }
        },
        itemBuilder: (BuildContext ctx) {
          return [
            const PopupMenuItem(
              child: Text('ScreenShot'),
              value: screenShotKey,
            ),
            const PopupMenuItem(
              child: Row(
                children: [
                  Icon(CupertinoIcons.doc_text_search),
                  Text('Search'),
                ],
              ),
              value: searchKey,
            ),
            const PopupMenuItem(
              child: Text('Sync'),
              value: syncKey,
            ),
          ];
        },
      ),
    ];
    if(smallView) {
      view = Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          backgroundColor: Colors.white,
          elevation: 0,
          leading: Builder(
            builder: (BuildContext context) {
              return CupertinoButton(
                alignment: Alignment.centerLeft,
                child: const Icon(CupertinoIcons.bars),
                onPressed: () {
                  if(jumpAction != null) {
                    jumpAction!();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              );
            },
          ),
          title: titleBar,
          actions: actionBar,
        ),
        body: editor,
      );
    } else {
      view = Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: 48,
          title: titleBar,
          actions: actionBar,
        ),
        body: editor,
      );
    }
    if(lastSmallView != smallView) { // 如果窗口大小刚刚发生了变化，那么与文档相关的UI都要刷新一遍
      // if (controller.document != null) {
      //   controller.openDocumentForUi();
      // }
    }
    lastSmallView = smallView;
    return view;
  }

  Widget getMindEditor() {
    return const Center(
      child: MindEditor(),
    );
  }
}
