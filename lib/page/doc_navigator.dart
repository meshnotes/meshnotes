import 'dart:async';
import 'dart:math';
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
import '../mindeditor/document/doc_title_node.dart';
import '../mindeditor/setting/constants.dart';
import 'users_page/user_info_setting_menu.dart';
import 'sync_progress_widget.dart';

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
  static const double indentWidth = 20.0;
  static const double dropLineHeight = 3.0;
  static const double dropLineSegmentWidth = 15.0;
  static const double dropLineGapWidth = indentWidth - dropLineSegmentWidth;
  static const Color dropLineColor = Colors.blueGrey;

  List<DocTitleFlat> totalList = []; // Total document list, including collapsed documents
  List<DocTitleFlat> docList = []; // Document list, only including visible documents
  int? selected;
  _NetworkStatus _networkStatus = _NetworkStatus.lost;
  int _peerCount = 0;
  final controller = Controller();
  bool _isSyncing = false;
  int _syncProgress = 0;
  final userInfoSettingLayerKey = GlobalKey<FloatingStackViewState>();
  bool _isUserInfoPopupVisible = false;

  // Drag and drop state
  int? _draggingIndex; // The index of the document title being dragged
  int? _dragTargetIndex; // The index of the document title being dragged to
  _DropPosition? _dropPosition;

  // Collapse/expand state
  final Set<String> _collapsedDocIds = {};

  // Auto-scroll state
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  final GlobalKey _listViewKey = GlobalKey();
  double _currentScrollDelta = 0.0;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerDocumentChangedWatcher(watcherKey, refreshDocumentList);
    CallbackRegistry.registerNetworkStatusWatcher(_onNetworkStatusChanged);
    CallbackRegistry.registerPeerNodesChangedWatcher(_onPeerNodesChanged);
    totalList = controller.docManager.getFlattenedDocumentList();
    docList = _getFilteredDocumentList(totalList);
    final _netStatus = controller.network.getNetworkStatus();
    _networkStatus = _convertStatus(_netStatus);
    controller.eventTasksManager.addSyncingTask(_updateSyncing);
    controller.eventTasksManager.addUserInfoChangedTask(_onUserInfoChanged);
  }

  @override
  void dispose() {
    super.dispose();
    CallbackRegistry.unregisterDocumentChangedWatcher(watcherKey);
    CallbackRegistry.unregisterNetworkStatusWatcher(_onNetworkStatusChanged);
    CallbackRegistry.unregisterPeerNodesChangedWatcher(_onPeerNodesChanged);
    controller.eventTasksManager.removeSyncingTask(_updateSyncing);
    controller.eventTasksManager.removeUserInfoChangedTask(_onUserInfoChanged);
    _scrollController.dispose();
    _autoScrollTimer?.cancel();
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
      // Build list with an extra drop zone at the end
      var list = ListView.builder(
        key: _listViewKey,
        controller: _scrollController,
        itemCount: docList.length + 1, // +1 for the end drop zone
        itemBuilder: (BuildContext context, int index) {
          if (index < docList.length) {
            return _buildDraggableDocItem(context, index);
          } else {
            // End drop zone
            return _buildEndDropZone(context);
          }
        },
      );

      // Wrap ListView with MouseRegion to track drag position
      titleListView = Expanded(
        child: Listener(
          onPointerMove: (event) {
            // Only handle auto-scroll when dragging
            if (_draggingIndex != null) {
              _handleAutoScroll(event.position);
            }
          },
          child: list,
        ),
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

  AppBar _buildAppBar(UserPrivateInfo userInfo) {
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
            _isSyncing ? SyncProgressWidget(
              progress: _syncProgress,
              size: 32,
            ) : const SizedBox(width: 16, height: 16),
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

  /// Build a draggable document item with drag target zones
  Widget _buildDraggableDocItem(BuildContext context, int index) {
    final docNode = docList[index];
    final indentWidth = docNode.level * DocumentNavigatorState.indentWidth;
    final isTargeted = _dragTargetIndex == index;
    final itemKey = GlobalKey();

    // Wrap in DragTarget for accepting drops
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final draggedIndex = details.data;
        return draggedIndex != index;
      },
      onAcceptWithDetails: (details) {
        final draggedIndex = details.data;
        _handleDrop(draggedIndex, index);
      },
      onMove: (details) {
        // Determine drop position based on vertical and horizontal position
        final RenderBox? renderBox = itemKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) {
          // Fallback to simple "above" position if we can't get the render box
          if (_dragTargetIndex != index || _dropPosition != _DropPosition.above) {
            setState(() {
              _dragTargetIndex = index;
              _dropPosition = _DropPosition.above;
            });
          }
          return;
        }

        final localPosition = renderBox.globalToLocal(details.offset);
        final itemHeight = renderBox.size.height;
        // Make the calculated position upper than the actual position, in order to avoid covered by finger or mouse cursor
        final relativeY = localPosition.dy - 15.0;

        // Use local X position to determine hierarchy level
        // localPosition.dx is relative to the item's left edge (which is already indented)
        // So we need to add back the indent to get the absolute position from sidebar's left edge
        final absoluteXFromSidebarLeft = localPosition.dx + indentWidth;

        // Calculate target level based on absolute X position from sidebar's left edge
        // Each level is 20px wide, and clamp to the global depth cap
        final maxIndentLevel = min(docNode.level + 1, Constants.maxDocumentDepth - 1);
        final calculatedLevel = min((absoluteXFromSidebarLeft / DocumentNavigatorState.indentWidth).floor(), maxIndentLevel);

        _DropPosition newDropPosition;

        // Determine vertical position (above/below/asChild)
        if (relativeY < itemHeight * 0.33) {
          // Top third: insert above as sibling
          newDropPosition = _DropPosition.above;
        } else if (relativeY > itemHeight * 0.67) {
          // Bottom third: check if should be child or sibling
          if (calculatedLevel > docNode.level) {
            // User dragged to the right beyond target's level -> insert as child
            newDropPosition = _DropPosition.asChild;
          } else {
            // Insert below as sibling
            newDropPosition = _DropPosition.below;
          }
        } else {
          // Middle third: check horizontal position
          if (calculatedLevel > docNode.level) {
            // User dragged to the right beyond target's level -> insert as child
            newDropPosition = _DropPosition.asChild;
          } else {
            // Insert above as sibling
            newDropPosition = _DropPosition.above;
          }
        }

        if (_dragTargetIndex != index || _dropPosition != newDropPosition) {
          setState(() {
            _dragTargetIndex = index;
            _dropPosition = newDropPosition;
          });
        }
      },
      onLeave: (details) {
        setState(() {
          _dragTargetIndex = null;
          _dropPosition = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        // Show drop indicator when hovering
        final isHovering = candidateData.isNotEmpty;
        void _onDragCompleted() { // Reset drag and drop state, reused by onDragEnd and onDragCompleted
          _stopAutoScroll();
          setState(() {
            _draggingIndex = null;
            _dragTargetIndex = null;
            _dropPosition = null;
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show line above when drop position is "above"
            if (isTargeted && isHovering && _dropPosition == _DropPosition.above)
              _buildDropLine(indentWidth, isAsChild: false),

            Container(
              key: itemKey,
              child: LongPressDraggable<int>(
                data: index,
                hapticFeedbackOnStart: true,
                // Offset the feedback downward so it doesn't block the drop indicator
                feedbackOffset: const Offset(0, -50),
                feedback: Material(
                  elevation: 6.0,
                  child: Container(
                    width: 300,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4.0),
                      border: Border.all(color: Colors.blue, width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 18.0,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            docNode.title,
                            style: const TextStyle(fontSize: 15.0, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Container(
                  color: Colors.grey.withOpacity(0.1),
                  child: Opacity(
                    opacity: 0.3,
                    child: _buildDocListTile(context, index, docNode, indentWidth: indentWidth),
                  ),
                ),
                onDragStarted: () {
                  setState(() {
                    _draggingIndex = index;
                  });
                },
                onDragEnd: (_) => _onDragCompleted(),
                onDragCompleted: _onDragCompleted,
                child: _buildDocListTile(context, index, docNode, indentWidth: indentWidth),
              ),
            ),

            // Show line below when drop position is "below"
            if (isTargeted && isHovering && _dropPosition == _DropPosition.below)
              _buildDropLine(indentWidth, isAsChild: false),

            // Show line below with extra indent when dropping as child
            if (isTargeted && isHovering && _dropPosition == _DropPosition.asChild)
              _buildDropLine(indentWidth, isAsChild: true),
          ],
        );
      },
    );
  }

  /// Build a horizontal line to indicate drop position
  /// [indentWidth] - the base indentation of the target item
  /// [isAsChild] - whether dropping as a child (adds extra indentation)
  Widget _buildDropLine(double indentWidth, {bool isAsChild = false}) {
    // Calculate number of segments based on indent level
    final targetLevel = (indentWidth / DocumentNavigatorState.indentWidth).floor();
    final numSegments = isAsChild ? targetLevel + 1 : targetLevel;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0), // Add vertical spacing for visibility
      height: dropLineHeight,
      child: Row(
        children: [
          // Show segments for hierarchy levels
          ...List.generate(numSegments, (index) {
            return Row(
              children: [
                Container(
                  width: dropLineSegmentWidth,
                  height: dropLineHeight,
                  decoration: BoxDecoration(
                    color: dropLineColor,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: dropLineGapWidth), // Gap between segments
              ],
            );
          }),
          // The main line
          Expanded(
            child: Container(
              height: dropLineHeight,
              decoration: BoxDecoration(
                color: dropLineColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the drop zone at the end of the list
  Widget _buildEndDropZone(BuildContext context) {
    const endZoneIndex = -1; // Special index to identify end zone
    final isTargeted = _dragTargetIndex == endZoneIndex;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final draggedIndex = details.data;
        _handleDropAtEnd(draggedIndex);
      },
      onMove: (details) {
        if (_dragTargetIndex != endZoneIndex) {
          setState(() {
            _dragTargetIndex = endZoneIndex;
            _dropPosition = _DropPosition.below;
          });
        }
      },
      onLeave: (details) {
        setState(() {
          _dragTargetIndex = null;
          _dropPosition = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        return Container(
          height: isHovering && isTargeted ? 50 : 20,
          child: Column(
            children: [
              if (isHovering && isTargeted)
                _buildDropLine(0), // No indentation for root level
              Expanded(child: Container()),
            ],
          ),
        );
      },
    );
  }

  /// Build the list tile content for a document
  Widget _buildDocListTile(BuildContext context, int index, DocTitleFlat docNode, {double indentWidth = 0}) {
    final isCollapsed = _collapsedDocIds.contains(docNode.docId);

    return ListTile(
      selected: index == selected,
      selectedTileColor: Colors.black12,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      visualDensity: VisualDensity.compact,
      minLeadingWidth: 14.0,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: indentWidth),
          GestureDetector(
            onTap: docNode.hasChild()
                ? () => _toggleCollapse(docNode.docId)
                : null,
            child: SizedBox(
              width: 16.0,
              child: docNode.hasChild()
                  ? Icon(
                      isCollapsed ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_down,
                      size: 16.0,
                      color: Colors.grey[600],
                    )
                  : null,
            ),
          ),
          Icon(
            Icons.description_outlined,
            size: 18.0,
            color: Colors.grey[600],
          ),
        ],
      ),
      title: Text(
        docNode.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15.0),
      ),
      trailing: _buildDocumentActions(context, docNode),
      onTap: () {
        var docId = docNode.docId;
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
  }

  /// Build action buttons for each document item
  Widget? _buildDocumentActions(BuildContext context, DocTitleFlat docNode) {
    return GestureDetector(
      onTapDown: (details) {
        _showDocumentMenu(context, details.globalPosition, docNode);
      },
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: Icon(
          Icons.more_vert,
          size: 16,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  int _getSubtreeRelativeDepth(String docId) {
    final startIndex = totalList.indexWhere((doc) => doc.docId == docId);
    if (startIndex == -1) {
      return 0;
    }
    final baseLevel = totalList[startIndex].level;
    var maxLevel = baseLevel;
    for (var i = startIndex + 1; i < totalList.length; i++) {
      final doc = totalList[i];
      if (doc.level <= baseLevel) {
        break;
      }
      if (doc.level > maxLevel) {
        maxLevel = doc.level;
      }
    }
    return maxLevel - baseLevel;
  }

  int _calculateTargetLevel(DocTitleFlat targetDoc, _DropPosition dropPos) {
    switch (dropPos) {
      case _DropPosition.above:
      case _DropPosition.below:
        return targetDoc.level;
      case _DropPosition.asChild:
        return targetDoc.level + 1;
    }
  }

  bool _wouldExceedDepthLimit(String docId, int targetLevel) {
    final subtreeDepth = _getSubtreeRelativeDepth(docId);
    final deepestLevel = targetLevel + subtreeDepth;
    return deepestLevel >= Constants.maxDocumentDepth;
  }

  void _showDepthLimitWarning() {
    CallbackRegistry.showToast('Document nesting cannot exceed ${Constants.maxDocumentDepth} levels');
  }

  /// Handle the drop operation
  void _handleDrop(int draggedIndex, int targetIndex) {
    if (draggedIndex == targetIndex) return;

    final draggedDoc = docList[draggedIndex];
    final targetDoc = docList[targetIndex];

    String? newParentDocId;
    int newOrderId;

    // Default to inserting above if no position is set
    final dropPos = _dropPosition ?? _DropPosition.above;
    final targetLevel = _calculateTargetLevel(targetDoc, dropPos);

    if (_wouldExceedDepthLimit(draggedDoc.docId, targetLevel)) {
      _showDepthLimitWarning();
      return;
    }

    switch (dropPos) {
      case _DropPosition.above:
        // Insert as sibling above target
        newParentDocId = targetDoc.parentDocId;
        newOrderId = targetDoc.orderId;
        break;
      case _DropPosition.below:
        // Insert as sibling below target
        newParentDocId = targetDoc.parentDocId;
        newOrderId = targetDoc.orderId + 1;
        break;
      case _DropPosition.asChild:
        // Insert as first child of target
        newParentDocId = targetDoc.docId;
        newOrderId = 0;
        break;
    }

    // Prevent moving a document to be its own descendant
    if (newParentDocId != null && _isAncestor(draggedDoc.docId, newParentDocId)) {
      CallbackRegistry.showToast('Cannot move document to its own descendant');
      return;
    }

    // When moving within the same parent and moving downward,
    // we need to adjust the newOrderId because the backend will first remove
    // the dragged item, which shifts all subsequent items up by one position
    if (draggedDoc.parentDocId == newParentDocId &&
        draggedDoc.orderId < newOrderId) {
      newOrderId--;
    }

    // Perform the move operation
    controller.docManager.moveDocument(draggedDoc.docId, newParentDocId, newOrderId);

    setState(() {
      _dragTargetIndex = null;
      _dropPosition = null;
    });
  }

  /// Handle dropping at the end of the list
  void _handleDropAtEnd(int draggedIndex) {
    final draggedDoc = docList[draggedIndex];
    const newLevel = 0;

    if (_wouldExceedDepthLimit(draggedDoc.docId, newLevel)) {
      _showDepthLimitWarning();
      return;
    }

    // Find the maximum orderId among root-level documents
    int maxOrderId = -1;
    for (var doc in docList) {
      if (doc.parentDocId == null && doc.orderId > maxOrderId) {
        maxOrderId = doc.orderId;
      }
    }

    // Insert at the end as a root-level document
    const newParentDocId = null;
    int newOrderId = maxOrderId + 1;

    // If the dragged document is already a root-level document,
    // we need to adjust the orderId because the backend will remove it first
    if (draggedDoc.parentDocId == null) {
      // After removal, the max orderId will be one less
      newOrderId--;
    }

    // Perform the move operation
    controller.docManager.moveDocument(draggedDoc.docId, newParentDocId, newOrderId);

    setState(() {
      _dragTargetIndex = null;
      _dropPosition = null;
    });
  }

  /// Check if ancestorId is an ancestor of docId
  bool _isAncestor(String ancestorId, String docId) {
    String? currentParent = docId;
    while (currentParent != null) {
      if (currentParent == ancestorId) return true;
      final parentNode = docList.firstWhere(
        (doc) => doc.docId == currentParent,
        orElse: () => docList.first,
      );
      currentParent = parentNode.parentDocId;
    }
    return false;
  }

  /// Show context menu for document
  void _showDocumentMenu(BuildContext context, Offset position, DocTitleFlat docNode) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        if(docNode.level + 1 < Constants.maxDocumentDepth) const PopupMenuItem<String>(
          value: 'create_child',
          child: Row(
            children: [
              Icon(Icons.add, size: 16),
              SizedBox(width: 8),
              Text('Create Child Document'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        switch (value) {
          case 'create_child':
            final parentLevel = docNode.level;
            if (parentLevel + 1 >= Constants.maxDocumentDepth) {
              _showDepthLimitWarning();
              return;
            }
            controller.newDocument(parentDocId: docNode.docId);
            if(widget.smallView && widget.jumpAction != null) {
              widget.jumpAction!();
            } else {
              _routeDocumentViewInSmallView(context);
            }
            break;
          case 'delete':
            _showDeleteConfirmation(context, docNode);
            break;
        }
      }
    });
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(BuildContext context, DocTitleFlat docNode) {
    final hasChildren = docNode.hasChild();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text(hasChildren 
          ? 'This will delete "${docNode.title}" and all its child documents. This action cannot be undone.'
          : 'Delete "${docNode.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (hasChildren) {
                controller.docManager.deleteDocumentWithChildren(docNode.docId);
              } else {
                controller.docManager.deleteDocument(docNode.docId);
              }
              refreshDocumentList();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void refreshDocumentList() {
    setState(() {
      totalList = controller.docManager.getFlattenedDocumentList();
      docList = _getFilteredDocumentList(totalList);
    });
  }

  /// Get filtered document list (respecting collapsed state)
  List<DocTitleFlat> _getFilteredDocumentList(List<DocTitleFlat> fullList) {
    if (_collapsedDocIds.isEmpty) {
      return fullList;
    }

    // Filter out children of collapsed documents
    final result = <DocTitleFlat>[];
    final skipUntilLevel = <int>[];

    for (var doc in fullList) {
      // Check if we should skip this document
      if (skipUntilLevel.isNotEmpty && doc.level > skipUntilLevel.last) {
        continue;
      }

      // Clear skip levels that no longer apply
      while (skipUntilLevel.isNotEmpty && doc.level <= skipUntilLevel.last) {
        skipUntilLevel.removeLast();
      }

      // Add this document to the result
      result.add(doc);

      // If this document is collapsed, skip its children
      if (_collapsedDocIds.contains(doc.docId) && doc.hasChild()) {
        skipUntilLevel.add(doc.level);
      }
    }

    return result;
  }

  /// Toggle collapse/expand state of a document
  void _toggleCollapse(String docId) {
    setState(() {
      if (_collapsedDocIds.contains(docId)) {
        _collapsedDocIds.remove(docId);
      } else {
        _collapsedDocIds.add(docId);
      }
      docList = _getFilteredDocumentList(totalList);
    });
  }

  /// Handle auto-scroll when dragging near edges
  void _handleAutoScroll(Offset globalPosition) {
    if (!_scrollController.hasClients) return;

    // Get the render box of the ListView
    final RenderBox? renderBox = _listViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      MyLogger.debug('Auto-scroll: renderBox is null');
      return;
    }

    // Convert global position to local (relative to ListView)
    final localPosition = renderBox.globalToLocal(globalPosition);
    final viewportHeight = renderBox.size.height;

    // Define scroll zones (top and bottom 80px)
    const scrollZoneSize = 80.0;
    const maxScrollSpeed = 20.0;

    double? scrollDelta;

    // Check if in top scroll zone
    if (localPosition.dy >= 0 && localPosition.dy < scrollZoneSize) {
      // Scroll up (negative delta)
      final proximity = 1.0 - (localPosition.dy / scrollZoneSize);
      scrollDelta = -proximity * maxScrollSpeed;
      MyLogger.debug('Auto-scroll: top zone, dy=${localPosition.dy}, delta=$scrollDelta');
    }
    // Check if in bottom scroll zone
    else if (localPosition.dy > viewportHeight - scrollZoneSize && localPosition.dy <= viewportHeight) {
      // Scroll down (positive delta)
      final proximity = (localPosition.dy - (viewportHeight - scrollZoneSize)) / scrollZoneSize;
      scrollDelta = proximity * maxScrollSpeed;
      MyLogger.debug('Auto-scroll: bottom zone, dy=${localPosition.dy}, delta=$scrollDelta');
    }

    // Start or update auto-scroll
    if (scrollDelta != null) {
      _startAutoScroll(scrollDelta);
    } else {
      _stopAutoScroll();
    }
  }

  /// Start auto-scrolling with the given speed
  void _startAutoScroll(double delta) {
    _currentScrollDelta = delta;

    // If already scrolling, just update the delta
    if (_autoScrollTimer?.isActive ?? false) {
      return;
    }

    // Start a new timer
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_scrollController.hasClients) {
        timer.cancel();
        _autoScrollTimer = null;
        return;
      }
      final currentOffset = _scrollController.offset;
      final newOffset = (currentOffset + _currentScrollDelta).clamp(0.0, _scrollController.position.maxScrollExtent,);

      if (newOffset != currentOffset) {
        _scrollController.jumpTo(newOffset);
      }
    });
  }

  /// Stop auto-scrolling
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _currentScrollDelta = 0.0;
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

  void _updateSyncing(bool isSyncing, int progress) {
    if(isSyncing == _isSyncing && progress == _syncProgress) {
      return;
    }
    setState(() {
      _isSyncing = isSyncing;
      _syncProgress = progress;
    });
  }
  void _onUserInfoChanged() {
    setState(() {});
  }

  Widget _buildUserInfoSettingLayer() {
    return FloatingStackView(
      key: userInfoSettingLayerKey,
    );
  }
  void _toggleUserInfoSettingPopup(UserPrivateInfo userInfo) {
    if (_isUserInfoPopupVisible) {
      _hideUserInfoSettingPopup();
    } else {
      _showUserInfoSettingPopup(userInfo);
    }
  }
  void _showUserInfoSettingPopup(UserPrivateInfo userInfo) {
    if(_isUserInfoPopupVisible) return;

    userInfoSettingLayerKey.currentState?.addLayer(UserInfoSettingMenu(
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
enum _DropPosition {
  above,    // Drop above the target item (as sibling)
  below,    // Drop below the target item (as sibling)
  asChild,  // Drop as child of the target item
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

