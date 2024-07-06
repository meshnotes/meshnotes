import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/view/toolbar/toolbar.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
// import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:my_log/my_log.dart';
import 'document/document.dart';
import 'view/mind_edit_field.dart';

class MindEditor extends StatefulWidget {

  const MindEditor({
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => MindEditorState();
}

class MindEditorState extends State<MindEditor> {
  final GlobalKey screenShotKey = GlobalKey();
  Controller controller = Controller.instance;
  Document? document;
  final GlobalKey _toolBarKey = GlobalKey();

  @override
  void initState() {
    MyLogger.info('Widget: MindEditorState initialized');
    super.initState();
    document = controller.document;
    CallbackRegistry.registerEditorState(this);
    CallbackRegistry.registerScreenShotHandler(_takeScreenShot);
  }

  @override
  void dispose() {
    MyLogger.info('Widget: MindEditorState disposed');
    CallbackRegistry.unregisterEditorState(this);
    CallbackRegistry.unregisterScreenShotHandler(_takeScreenShot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if(document == null) {
      return const Text("Empty");
    }
    List<Widget> childViews = _buildEditorAndToolbarView();
    var editorArea = Center(
      child: Column(
        children: childViews
      ),
    );
    var totalView = Row(
      children: [
        Expanded(
          child: editorArea,
          // 这里用来放侧边区域，如引用线
        ),
      ],
    );
    return totalView;
  }

  List<Widget> _buildEditorAndToolbarView() {
    var childViews = <Widget>[
      _buildEditField(),
      _buildToolbar(),
    ];
    return childViews;
  }

  Widget _buildToolbar() {
    var toolbarView = MindToolBar.basic(
      key: _toolBarKey,
      controller: controller,
      context: context,
    );
    var padding = const EdgeInsets.all(1.0);
    if(Controller.instance.environment.isMobile()) {
      padding = const EdgeInsets.fromLTRB(1.0, 1.0, 1.0, 12.0); // Leave a little space for mobile phone's controller bar
    }
    var container = Container(
      padding: padding,
      width: double.infinity,
      child: toolbarView,
    );
    return container;
  }

  Widget _buildEditField() {
    var editFieldView = MindEditField(
      key: ObjectKey(document!),
      controller: controller,
      focusNode: controller.globalFocusNode,
      document: document!,
    );
    var columnWrapper = Column(
      children: <Widget>[
        editFieldView,
      ],
    );
    var withPadding = Container(
      padding: const EdgeInsets.fromLTRB(10.0, 0.0, 0.0, 0.0),
      child: columnWrapper,
    );
    var expanded = Expanded(
      child: withPadding,
    );
    return expanded;
  }

  void open(Document doc) {
    MyLogger.debug('efantest: refresh document');
    setState(() {
      document = doc;
    });
  }

  double get paddingSize => Controller.instance.environment.isDesktop()? 0.0: 10.0;

  void _takeScreenShot() async {
    MyLogger.info('Taking screen shot');
    var pixels = await _getPixelsFromReadOnlyWidget();
    if(pixels == null) {
      MyLogger.debug('efantest: pixels is null');
      return;
    }
    MyLogger.info('efantest: Get permission');
    bool permission = await promote();

    if(permission) {
      MyLogger.info('efantest: Save image');
      _saveImage(pixels);
    }
  }
  // 从后台构造一个新的Block List，生成截图
  Future<Uint8List?> _getPixelsFromReadOnlyWidget() async {
    List<Widget> blocks = CallbackRegistry.getReadOnlyBlocks();

    Widget widget = Container(
      color: Colors.white,
      padding: EdgeInsets.all(paddingSize),
      child: SingleChildScrollView(
        child: Column(
          children: blocks,
        ),
      ),
    );
    ui.Size imageSize = ui.Size(Controller.instance.device.safeWidth, 2000);
    var devicePixelRation = Controller.instance.device.pixelRatio;
    final RenderRepaintBoundary repaintBoundary = RenderRepaintBoundary();
    final RenderView renderView = RenderView(
      view: ui.PlatformDispatcher.instance.views.single,
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaintBoundary,
      ),
      configuration: ViewConfiguration(
          size: imageSize,
          devicePixelRatio: devicePixelRation
      ),
    );

    final PipelineOwner pipelineOwner = PipelineOwner();
    final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());

    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();
    final RenderObjectToWidgetElement<RenderBox> rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: widget,
      ),
    ).attachToRenderTree(buildOwner);
    // await Future.delayed(Duration(milliseconds: 500));
    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();

    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();
    final ui.Image image = await repaintBoundary.toImage(pixelRatio: devicePixelRation);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if(byteData == null) {
      MyLogger.info('efantest: byteData is null');
    }
    return byteData?.buffer.asUint8List();
  }

  // Get screen shot from activated widget
  // Future<Uint8List?> _getPixels() async {
  //   var boundary = snapShotKey.currentContext!.findRenderObject() as RenderRepaintBoundary?;
  //   double dpr = ui.window.devicePixelRatio;
  //   var image = await boundary!.toImage(pixelRatio: dpr);
  //   ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  //   return byteData?.buffer.asUint8List();
  // }
  Future<bool> promote() async {
    if(Controller.instance.environment.isIos()) {
      var status = await Permission.photos.status;
      if(status.isDenied) {
        Map<Permission, PermissionStatus> _ = await [
          Permission.photos,
        ].request();
      }
      return status.isGranted;
    } else if(Controller.instance.environment.isAndroid()){
      var status = await Permission.storage.status;
      if(status.isDenied) {
        Map<Permission, PermissionStatus> _ = await [
          Permission.storage,
        ].request();
      }
      return status.isGranted;
    }
    return false;
  }
  _saveImage(Uint8List pixels) async {
    var status = await Permission.photos.status;
    if(Controller.instance.environment.isIos()) {
      if(status.isGranted) {
        // final result = await ImageGallerySaver.saveImage(pixels, quality: 60, name: 'mesh_note');
        // if(result != null) {
        //   MyLogger.info('iOS save success');
        // } else {
        //   MyLogger.info('iOS save failed');
        // }
      // } else if(status.isDenied) {
        MyLogger.info('iOS permission denied');
      }
    } else if(Controller.instance.environment.isAndroid()) {
      if(status.isGranted) {
        // final result = await ImageGallerySaver.saveImage(pixels, quality: 60);
        // if(result != null) {
        //   MyLogger.info('Android save success');
        // } else {
        //   MyLogger.info('Android save failed');
        // }
      } else if(status.isDenied) {
        MyLogger.info('Android permission denied');
      }
    }
  }
}