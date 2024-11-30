import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:keygen/keygen.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:my_log/my_log.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../mindeditor/controller/controller.dart';
import '../mindeditor/document/dal/doc_data_model.dart';

const double nodeContainerWidth = 100.0;
const double nodeContainerHeight = 60.0;
const double nodeContainerXSpace = 50.0;
const double nodeContainerYSpace = 20.0;
const double selectedBorderWidth = 3.0;
const double parentSelectedBorderWidth = 2.0;

class VersionPageLargeScreen extends StatefulWidget {
  const VersionPageLargeScreen({
    super.key,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return const VersionPageLargeScreen();
      },
      fullscreenDialog: true,
    ));
  }

  @override
  State<StatefulWidget> createState() => _VersionPageLargeScreenState();
}

class _VersionPageLargeScreenState extends State<VersionPageLargeScreen> {
  bool showAll = false;
  final controller = Controller();
  late Map<String, Node> versionMap;
  late List<List<Node>> levelNodes;
  final sheetController = DraggableScrollableController();
  late String currentVersion;
  int maxColumn = 0;
  int maxRow = 0;
  final horizontalScrollController = ScrollController();
  final verticalScrollController = ScrollController();
  String? selectedVersion;
  final linesKey = GlobalKey();
  final activeLinesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _generateVersionTreeData();
  }

  @override
  Widget build(BuildContext context) {
    final container = _buildGraph();
    final buttons = Row(
      children: [
        Expanded(child: Container()),
        Row(
          children: [
            const Text(
              'Show All',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 8),  // 文字和开关之间的间距
            CupertinoSwitch(
              value: showAll,
              onChanged: (value) {
                setState(() {
                  showAll = value;
                  _generateVersionTreeData();
                });
              },
            ),
          ],
        ),
        IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close),
        ),
      ],
    );
    final body = Column(
      children: [
        buttons,
        Expanded(
          child: Container(
            alignment: Alignment.center,
            child: container,
          ),
        ),
      ],
    );
    return Scaffold(
      body: body,
    );
  }

  Widget _buildGraph() {
    final canvasWidth = maxColumn * (nodeContainerWidth + nodeContainerXSpace) + nodeContainerXSpace;
    final canvasHeight = maxRow * (nodeContainerHeight + nodeContainerYSpace) + nodeContainerYSpace;
    final nodeWidgets = _buildNodeWidgets();
    final allLines = _buildLines(canvasWidth, canvasHeight);
    final activeLines = _buildActiveLines(canvasWidth, canvasHeight);
    final sizedBox = SizedBox(
      width: canvasWidth,
      height: canvasHeight,
      child: Stack(
        children: [
          allLines,
          ...nodeWidgets,
          IgnorePointer(
            child: activeLines,
          ),
        ],
      ),
    );
    final horizontalScrollView = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: horizontalScrollController,
      child: sizedBox,
    );
    final verticalScrollView = SingleChildScrollView(
      scrollDirection: Axis.vertical,
      controller: verticalScrollController,
      child: horizontalScrollView,
    );
    final layout = LayoutBuilder(
      builder: (context, constraints) {
        MyLogger.debug('_buildGraph: constraints=$constraints');
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final gestureDetector = GestureDetector(
          onPanUpdate: (details) {
            var newX = horizontalScrollController.offset - details.delta.dx;
            var newY = verticalScrollController.offset - details.delta.dy;
            newX = newX.clamp(0, math.max(0, canvasWidth - maxWidth));
            newY = newY.clamp(0, math.max(0, canvasHeight - maxHeight));
            horizontalScrollController.jumpTo(newX);
            verticalScrollController.jumpTo(newY);
          },
          child: verticalScrollView,
        );
        return gestureDetector;
      },
    );
    return layout;
  }

  List<Widget> _buildNodeWidgets() {
    final selectedBorder = Border.all(color: Colors.blue, width: selectedBorderWidth, strokeAlign: BorderSide.strokeAlignOutside);
    final childSelectedBorder = Border.all(color: Colors.green, width: parentSelectedBorderWidth, strokeAlign: BorderSide.strokeAlignOutside);
    final validBorder = Border.all(color: Colors.black, strokeAlign: BorderSide.strokeAlignOutside);
    final invalidBorder = Border.all(color: const Color.fromARGB(255, 193, 193, 193), strokeAlign: BorderSide.strokeAlignOutside);
    const validColor = Colors.white;
    const currentVersionColor =  Color(0xFFE3F2FD);
    const invalidColor = Color.fromARGB(255, 245, 245, 245);
    const deprecatedTextDecoration = TextDecoration.lineThrough;
    const defaultTextDecoration = TextDecoration.none;

    final widgets = <Widget>[];
    for(final column in levelNodes) {
      for(final node in column) {
        final isSelected = node.name == selectedVersion;
        final isChildSelected = node.children.any((child) => child.name == selectedVersion);

        final color = node.name == currentVersion ? currentVersionColor : node.status == Constants.statusAvailable ? validColor : invalidColor;
        final textDecoration = node.status == Constants.statusDeprecated ? deprecatedTextDecoration : defaultTextDecoration;
        final border = isSelected ? selectedBorder : isChildSelected ? childSelectedBorder : node.status == Constants.statusAvailable ? validBorder : invalidBorder;
        final container = Container(
          padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(8),
            color: color,
          ),
          width: nodeContainerWidth,
          height: nodeContainerHeight,
          child: Column(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    HashUtil.formatHash(node.name),
                    style: TextStyle(
                      color: const Color(0xFF424242),
                      decoration: textDecoration,
                    ),
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  node.createdAt,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBDBDBD),
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  node.isLocal ? 'Local' : 'Remote',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBDBDBD),
                  ),
                ),
              ),
            ],
          ),
        );
        final gestureDetector = GestureDetector(
          onTap: () {
            setState(() {
              selectedVersion = node.name;
            });
          },
          child: container,
        );
        final widget = Positioned(
          left: node._getLeft(),
          top: node._getTop(),
          child: gestureDetector,
        );
        widgets.add(widget);
      }
    }
    return widgets;
  }

  Widget _buildLines(double canvasWidth, double canvasHeight) {
    final paint = CustomPaint(
      key: linesKey,
      painter: _LinesPainter(canvasWidth: canvasWidth, canvasHeight: canvasHeight, versionMap: versionMap),
      size: Size(canvasWidth, canvasHeight),
    );
    return paint;
  }
  Widget _buildActiveLines(double canvasWidth, double canvasHeight) {
    if(selectedVersion == null) {
      return const SizedBox();
    }
    final selectNode = versionMap[selectedVersion];
    if(selectNode == null) {
      return const SizedBox();
    }
    final activeNodes = <String, Node>{};
    activeNodes[selectNode.name] = selectNode;

    final myPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.red
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final paint = CustomPaint(
      key: activeLinesKey,
      painter: _LinesPainter(
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        versionMap: activeNodes,
        myPaint: myPaint,
        selectedBorderWidth: selectedBorderWidth,
        parentSelectedBorderWidth: parentSelectedBorderWidth,
      ),
      size: Size(canvasWidth, canvasHeight),
    );
    return paint;
  }

  void _generateVersionTreeData() {
    levelNodes = [];
    versionMap = _getVersionTreeData();
    currentVersion = controller.docManager.getLatestVersion();
    final heads = _findHeads(versionMap);
    int maxDepth = 1;
    for(final head in heads) {
      final depth = _findDepth(head, versionMap);
      if(depth > maxDepth) {
        maxDepth = depth;
      }
      head.level = 0;
    }
    for(final head in heads) {
      _updateLevel(head, versionMap);
    }
    MyLogger.debug('_generateVersionTreeData: maxDepth=$maxDepth');

    for(int i = 0; i <= maxDepth; i++) {
      levelNodes.add([]);
    }
    for(final node in versionMap.values) {
      final level = node.level;
      levelNodes[level].add(node);
      node.column = level;
      node.row = levelNodes[level].length - 1;
    }
    maxRow = 0;
    maxColumn = maxDepth;
    for(final level in levelNodes) {
      if(level.length > maxRow) {
        maxRow = level.length;
      }
    }
  }

  Map<String, Node> _getVersionTreeData() {
    final versions = showAll ? controller.docManager.getCurrentRawVersionTree() : controller.docManager.getCurrentValidVersionTree();
    return _convertToNode(versions);
  }

  Map<String, Node> _convertToNode(List<VersionDataModel> versions) {
    // 1. Build a map with version hash as key
    // 2. Build the parent-child relationship
    final map = <String, Node>{};
    for(final version in versions) {
      final node = Node(name: version.versionHash, createdAt: DateFormat('yyyy-MM-dd hh:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(version.createdAt)));
      node.status = version.status;
      node.syncStatus = version.syncStatus;
      node.isLocal = version.createdFrom == Constants.createdFromLocal;
      map[version.versionHash] = node;
    }
    for(final version in versions) {
      final key = version.versionHash;
      final node = map[key];
      if(node == null) { // Impossible
        MyLogger.warn('_convertToNode: version $key not found');
        continue;
      }
      final parents = version.getParentsList();
      for(final parent in parents) {
        if(parent.isEmpty) continue;
        final parentNode = map[parent];
        if(parentNode == null) { // Impossible
          MyLogger.warn('_convertToNode: parent $parent of $key not found');
          continue;
        }
        parentNode.children.add(node);
        node.parents.add(parentNode);
      }
    }
    return map;
  }

  /// Find all nodes has no child
  List<Node> _findHeads(Map<String, Node> versionMap) {
    return versionMap.values.where((node) => node.children.isEmpty).toList();
  }
  int _findDepth(Node node, Map<String, Node> versionMap) {
    if(node.depth > 0) {
      return node.depth;
    }
    int maxDepth = 1;
    for(final parent in node.parents) {
      final depth = 1 + _findDepth(parent, versionMap);
      if(depth > maxDepth) {
        maxDepth = depth;
      }
    }
    node.depth = maxDepth;
    return maxDepth;
  }
  void _updateLevel(Node node, Map<String, Node> versionMap) {
    for(final parent in node.parents) {
      var level = node.level + 1;
      if(parent.level < level) {
        parent.level = level;
        _updateLevel(parent, versionMap);
      }
    }
  }
}

class Node {
  String name;
  String createdAt;
  List<Node> parents = [];
  List<Node> children = [];
  int status = 0;
  int syncStatus = 0;
  int level = -1;
  int depth = -1;
  int row = 0;
  int column = 0;
  bool isLocal = true;

  Node({
    required this.name,
    required this.createdAt,
  });

  
  double _getLeft() {
    return column * (nodeContainerWidth + nodeContainerXSpace) + nodeContainerXSpace;
  }
  double _getRight() {
    return _getLeft() + nodeContainerWidth;
  }
  double _getTop() {
    return row * (nodeContainerHeight + nodeContainerYSpace) + nodeContainerYSpace;
  }
  double _getCenter() {
    return _getTop() + nodeContainerHeight / 2;
  }
}

class _LinesPainter extends CustomPainter {
  double canvasWidth;
  double canvasHeight;
  Map<String, Node> versionMap;
  Paint? myPaint;
  double? selectedBorderWidth;
  double? parentSelectedBorderWidth;
  static const int arrowLength = 10;
  static const double arrowAngle = math.pi / 6;

  _LinesPainter({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.versionMap,
    this.myPaint,
    this.selectedBorderWidth = 1,
    this.parentSelectedBorderWidth = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    MyLogger.debug('paint canvasWidth=$canvasWidth, canvasHeight=$canvasHeight');
    Paint paint = myPaint ?? (Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 2);
    for(final node in versionMap.values) {
      for(final parent in node.parents) {
        _drawLine(canvas, node, parent, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    final oldPainter = oldDelegate as _LinesPainter;
    return canvasWidth != oldPainter.canvasWidth || canvasHeight != oldPainter.canvasHeight || versionMap != oldPainter.versionMap;
  }

  void _drawLine(Canvas canvas, Node node, Node parent, Paint paint) {
    final path = Path();
    final x0 = node._getRight() + selectedBorderWidth! + paint.strokeWidth / 2;
    final y0 = node._getCenter();
    var xn = parent._getLeft() - parentSelectedBorderWidth!;
    final yn = parent._getCenter();
    path.moveTo(x0, y0);
    if(node.column == parent.column - 1) {
      final angle = _getAngle(x0, y0, xn, yn);
      xn += paint.strokeWidth * math.cos(angle); // Adjust to not overlap with the border
      path.lineTo(xn, yn);
      _drawArrow(path, x0, y0, xn, yn, angle);
    } else {
      double x1 = (x0 + xn) / 2;
      double y1 = 0;
      double x2 = (x0 + xn) / 2;
      double y2 = canvasHeight;
      final angle = _getAngle(x2, y2, xn, yn);
      xn += paint.strokeWidth * math.cos(angle);
      path.cubicTo(x1, y1, x2, y2, xn, yn);
      _drawArrow(path, x2, y2, xn, yn, angle);
    }
    canvas.drawPath(path, paint);
  }

  double _getAngle(double x0, double y0, double xn, double yn) {
    final dx = x0 - xn;
    final dy = y0 - yn;
    final angle = math.atan2(dy, dx);
    return angle;
  }

  void _drawArrow(Path path, double x0, double y0, double xn, double yn, double angle) {
    final p1x = xn + arrowLength * math.cos(angle + arrowAngle);
    final p1y = yn + arrowLength * math.sin(angle + arrowAngle);
    final p2x = xn + arrowLength * math.cos(angle - arrowAngle);
    final p2y = yn + arrowLength * math.sin(angle - arrowAngle);
    path.moveTo(p1x, p1y);
    path.lineTo(xn, yn);
    path.lineTo(p2x, p2y);
    // path.lineTo(p1x, p1y);
  }
}
