import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/view/floating_stack_layer.dart';
import 'package:mesh_note/mindeditor/view/network_view.dart';
import 'package:mesh_note/page/widget_templates.dart';
import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/net/status.dart';
import 'setting_page_large_screen.dart';
import 'menu.dart';
import 'setting_page_small_screen.dart';
import 'inspired_page.dart';
import 'resizable_view.dart';
import '../mindeditor/document/dal/doc_data_model.dart';
import '../mindeditor/setting/constants.dart';
import 'users_page/user_info_setting_page.dart';

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
  int _peerCount = 0;
  final controller = Controller();
  bool _isSyncing = false;
  final userInfoSettingLayerKey = GlobalKey<FloatingStackViewState>();
  bool _isUserInfoPopupVisible = false;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerDocumentChangedWatcher(watcherKey, refreshDocumentList);
    CallbackRegistry.registerNetworkStatusWatcher(_onNetworkStatusChanged);
    CallbackRegistry.registerPeerNodesChangedWatcher(_onPeerNodesChanged);
    docList = controller.docManager.getAllDocuments();
    final _netStatus = controller.network.getNetworkStatus();
    _networkStatus = _convertStatus(_netStatus);
    controller.eventTasksManager.addSyncingTask(_updateSyncing);
  }

  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterDocumentChangedWatcher(watcherKey);
    CallbackRegistry.unregisterNetworkStatusWatcher(_onNetworkStatusChanged);
    CallbackRegistry.unregisterPeerNodesChangedWatcher(_onPeerNodesChanged);
    controller.eventTasksManager.removeSyncingTask(_updateSyncing);
  }

  @override
  Widget build(BuildContext context) {
    final userInfo = controller.getUserPrivateInfo()!;
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
    final column = Column(
      children: [
        titleListView,
        Container(
          color: Colors.white, // To eliminate the transparent background of the padding of button
          child: createButton,
        ),
        systemButtons,
      ],
    );
    final userInfoSettingLayer = _buildUserInfoSettingLayer();
    final stack = Stack(
      children: [
        column,
        userInfoSettingLayer,
      ],
    );
    return Scaffold(
      appBar: _buildAppBar(userInfo),
      body: SizedBox(
        width: double.infinity,
        child: stack,
      ),
    );
  }

  AppBar _buildAppBar(SimpleUserPrivateInfo userInfo) {
    List<Widget>? actions;
    if(widget.smallView) {
      actions = [
        MainMenu(controller: controller, menuType: MenuType.navigator),
      ];
    }
    final userName = userInfo.userName;
    return AppBar(
      title: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: _isSyncing ? const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
              ) : null,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleUserInfoSettingPopup(userInfo),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(userName),
                  const SizedBox(width: 4),
                  Icon(
                    _isUserInfoPopupVisible ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final showDebug = controller.setting.getSetting(Constants.settingKeyShowDebugMenu)?.toLowerCase() == 'true';
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: Row(
        children: [
          const Spacer(),
          if(showDebug) _buildSearchIcon(),
          if(showDebug) const Spacer(),
          if(showDebug) _buildCardIcon(context),
          if(showDebug) const Spacer(),
          _buildSettingIcon(context),
          const Spacer(),
          _buildNetworkIcon(context),
          const Spacer(),
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
      child: const Icon(CupertinoIcons.gear, color: Colors.black, size: 24),
      onPressed: () {
        if(controller.environment.isSmallView(context)) {
          SettingPageSmallScreen.route(context);
        } else {
          SettingPageLargeScreen.route(context);
        }
      },
    );
  }
  Widget _buildNetworkIcon(BuildContext context) {
    return NetworkStatusIcon(
      networkStatus: _networkStatus,
      dataStatus: _DataStatus.notSynced,
      peerCount: _peerCount,
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

  void _onPeerNodesChanged(Map<String, NodeInfo> nodes) {
    final newCount = nodes.values.where((node) => node.status == NodeStatus.inContact).length;
    if(newCount == _peerCount) {
      return;
    }
    setState(() {
      _peerCount = newCount;
    });
  }

  void _updateSyncing(bool isSyncing) {
    if(isSyncing == _isSyncing) {
      return;
    }
    setState(() {
      _isSyncing = isSyncing;
    });
  }

  Widget _buildUserInfoSettingLayer() {
    return FloatingStackView(
      key: userInfoSettingLayerKey,
    );
  }
  void _toggleUserInfoSettingPopup(SimpleUserPrivateInfo userInfo) {
    if (_isUserInfoPopupVisible) {
      _hideUserInfoSettingPopup();
    } else {
      _showUserInfoSettingPopup(userInfo);
    }
  }
  void _showUserInfoSettingPopup(SimpleUserPrivateInfo userInfo) {
    if(_isUserInfoPopupVisible) return;

    userInfoSettingLayerKey.currentState?.addLayer(UserInfoSettingPage(
      userInfo: userInfo,
      closeCallback: _hideUserInfoSettingPopup,
    ));
    setState(() {
      _isUserInfoPopupVisible = true;
    });
  }
  void _hideUserInfoSettingPopup() {
    if(!_isUserInfoPopupVisible) return;

    userInfoSettingLayerKey.currentState?.clearLayer();
    setState(() {
      _isUserInfoPopupVisible = false;
    });
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
  final int peerCount;

  const NetworkStatusIcon({
    required this.networkStatus,
    required this.dataStatus,
    required this.peerCount,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final networkIcon = _buildNetworkIcon();
    final syncedIcon = _buildSyncedIcon();
    final peerCountWidget = _buildPeerCount();
    final stacks = Stack(
      children: [
        Container(
          child: networkIcon,
          padding: const EdgeInsets.all(2.0),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: Visibility(
            visible: false,
            child: syncedIcon,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: peerCountWidget,
        ),
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
  Widget _buildPeerCount() {
    if(peerCount <= 0) {
      return const SizedBox.shrink();
    }
    String text = peerCount.toString();
    if(peerCount > 10) {
      text = '9+';
    }
    return Container(
      constraints: const BoxConstraints(
        minWidth: 15,
        minHeight: 15,
      ),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF3CB371),
        shape: BoxShape.circle,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showNetworkDetails(BuildContext context) {
    final myPublicKey = Controller().getUserPrivateInfo()?.publicKey?? '';
    showDialog(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(0, 50, 0, 0),
          child: Material(
            child: NetworkDetailView(nodes: Controller().network.getNetworkDetails(), myPublicKey: myPublicKey),
          ),
        );
      },
    );
    // NetworkDetailView.route(context);
  }
}