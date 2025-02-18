import 'package:mesh_note/mindeditor/view/network_view.dart';
import 'package:mesh_note/page/widget_templates.dart';
import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/net/status.dart';
import 'large_screen_setting_page.dart';
import 'menu.dart';
import 'small_screen_setting_page.dart';
import 'inspired_page.dart';
import 'resizable_view.dart';
import '../mindeditor/document/dal/doc_data_model.dart';
import '../mindeditor/setting/constants.dart';

class DocumentNavigator extends StatefulWidget with ResizableViewMixin {
  final Function()? jumpAction;
  @override
  bool get expectedSmallView => smallView;
  @override
  String get loggingClassName => 'DocumentNavigator';

  final bool smallView;
  const DocumentNavigator({
    Key? key,
    this.jumpAction,
    this.smallView = false
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => DocumentNavigatorState();
}

class DocumentNavigatorState extends State<DocumentNavigator> {
  static const String watcherKey = 'doc_navigator';
  List<DocDataModel> docList = [];
  int? selected;
  _NetworkStatus _networkStatus = _NetworkStatus.lost;
  final controller = Controller();

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerDocumentChangedWatcher(watcherKey, refreshDocumentList);
    CallbackRegistry.registerNetworkStatusWatcher(_onNetworkStatusChanged);
    docList = controller.docManager.getAllDocuments();
    final _netStatus = controller.network.getNetworkStatus();
    _networkStatus = _convertStatus(_netStatus);
  }

  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterDocumentChangedWatcher(watcherKey);
    CallbackRegistry.unregisterNetworkStatusWatcher(_onNetworkStatusChanged);
  }

  @override
  Widget build(BuildContext context) {
    if(widget.smallView) {
      widget.routeIfResize(context);
    }
    Widget createButton = WidgetTemplate.buildSmallIconButton(context, Icons.edit_square, 'Add a new note', () {
        MyLogger.info('new document');
        controller.newDocument();
        if(widget.smallView && widget.jumpAction != null) {
          widget.jumpAction!();
        } else {
          _routeDocumentViewInSmallView(context);
        }
    });
    Widget titleListView;
    if(docList.isEmpty) {
      titleListView = Expanded(
        child: Container(
          child: const Text('No Document'),
          alignment: Alignment.center,
        ),
      );
    } else {
      var list = ListView.builder(
        itemCount: docList.length,
        itemBuilder: (BuildContext context, int index) {
          return ListTile(
            selected: index == selected,
            selectedTileColor: Colors.black12,
            title: Text(docList[index].title),
            onTap: () {
              var docId = docList[index].docId;
              controller.openDocument(docId);
              setState(() {
                selected = index;
              });
              if(widget.smallView && widget.jumpAction != null) {
                widget.jumpAction!();
              } else {
                _routeDocumentViewInSmallView(context);
              }
            },
          );
        },
      );
      titleListView = Expanded(
        child: list,
      );
    }
    var systemButtons = _buildSystemButtons(context);
    return Scaffold(
      appBar: _buildAppBar(),
      body: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            titleListView,
            Container(
              color: Colors.white, // To eliminate the transparent background of the padding of button
              child: createButton,
            ),
            systemButtons,
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    List<Widget>? actions;
    if(widget.smallView) {
      actions = [
        MainMenu(controller: controller, menuType: MenuType.navigator),
      ];
    }
    final userName = controller.userPrivateInfo?.userName ?? 'Unknown User';
    return AppBar(
      title: Center(
        child: Text(userName),
      ),
      titleSpacing: 0,
      toolbarHeight: 48,
      backgroundColor: Colors.white,
      elevation: 0,
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: Colors.grey.withOpacity(0.2),
          height: 1.0,
        )
      ),
    );
  }

  void _routeDocumentViewInSmallView(BuildContext context) {
    if(widget.smallView) {
      Navigator.of(context).pushNamed(Constants.documentRouteName);
    }
  }

  Widget _buildSystemButtons(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: Row(
        children: [
          _buildSearchIcon(),
          const Spacer(),
          _buildCardIcon(context),
          const Spacer(),
          _buildSettingIcon(context),
          const Spacer(),
          _buildNetworkIcon(context),
        ],
      ),
    );
  }

  Widget _buildSearchIcon() {
    return CupertinoButton(
      // padding: const EdgeInsets.fromLTRB(20.0, 0, 20.0, 0),
      child: const Icon(CupertinoIcons.search, color: Colors.black),
      onPressed: () {},
    );
  }

  Widget _buildCardIcon(BuildContext context) {
    return CupertinoButton(
      // padding: const EdgeInsets.fromLTRB(20.0, 0, 20.0, 0),
      child: const Icon(CupertinoIcons.lightbulb, color: Colors.black),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return const InspiredCardPage();
          }
        );
      },
    );
  }
  Widget _buildSettingIcon(BuildContext context) {
    return CupertinoButton(
      // padding: const EdgeInsets.fromLTRB(20.0, 0, 20.0, 0),
      child: const Icon(CupertinoIcons.gear, color: Colors.black),
      onPressed: () {
        if(controller.environment.isSmallView(context)) {
          SmallScreenSettingPage.route(context);
        } else {
          LargeScreenSettingPage.route(context);
        }
      },
    );
  }
  Widget _buildNetworkIcon(BuildContext context) {
    return NetworkStatusIcon(
      networkStatus: _networkStatus,
      dataStatus: _DataStatus.notSynced,
    );
  }

  void refreshDocumentList() {
    setState(() {
      docList = controller.docManager.getAllDocuments();
    });
  }

  void _onNetworkStatusChanged(NetworkStatus status) {
    final newStatus = _convertStatus(status);
    if(newStatus == _networkStatus) {
      return;
    }
    setState(() {
      _networkStatus = newStatus;
    });
  }
  _NetworkStatus _convertStatus(NetworkStatus status) {
    switch(status) {
      case NetworkStatus.unknown:
        return _NetworkStatus.lost;
      case NetworkStatus.starting:
        return _NetworkStatus.lost;
      case NetworkStatus.running:
        return _NetworkStatus.connected;
    }
  }
}

enum _NetworkStatus {
  connected,
  lost,
}
enum _DataStatus {
  synced,
  notSynced,
}

class NetworkStatusIcon extends StatelessWidget {
  final _NetworkStatus networkStatus;
  final _DataStatus dataStatus;

  const NetworkStatusIcon({
    required this.networkStatus,
    required this.dataStatus,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final networkIcon = _buildNetworkIcon();
    final syncedIcon = _buildSyncedIcon();
    final stacks = Stack(
      alignment: Alignment.bottomLeft,
      children: [
        Container(
          child: networkIcon,
          padding: const EdgeInsets.all(2.0),
        ),
        syncedIcon,
      ],
    );
    final result = CupertinoButton(
      child: stacks,
      onPressed: () {
        //TODO show network status
        _showNetworkDetails(context);
      },
    );
    return result;
  }

  Icon _buildNetworkIcon() {
    const size = 24.0;
    switch(networkStatus) {
      case _NetworkStatus.connected:
        return const Icon(
          CupertinoIcons.wifi,
          size: size,
          color: Colors.black,
        );
      case _NetworkStatus.lost:
        return const Icon(
          CupertinoIcons.wifi_slash,
          size: size,
          color: Colors.grey,
        );
    }
  }
  Icon _buildSyncedIcon() {
    const size = 12.0;
    switch(dataStatus) {
      case _DataStatus.synced:
        return const Icon(
          CupertinoIcons.check_mark_circled_solid,
          color: Colors.green,
          size: size,
        );
      case _DataStatus.notSynced:
        return const Icon(
          CupertinoIcons.multiply_circle_fill,
          color: Colors.amber,
          size: size,
        );
    }
  }

  void _showNetworkDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(0, 50, 0, 0),
          child: Material(
            child: NetworkDetailView(nodes: Controller().network.getNetworkDetails()),
          ),
        );
      },
    );
    // NetworkDetailView.route(context);
  }
}