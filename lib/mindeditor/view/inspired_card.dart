import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:my_log/my_log.dart';
import '../controller/controller.dart';
import '../document/inspired_seed.dart';
import '../document/paragraph_desc.dart';
import '../setting/constants.dart';
import 'mind_edit_block.dart';

class InspiredCardView extends StatefulWidget {
  final InspiredSeed seed;
  const InspiredCardView({
    super.key,
    required this.seed,
  });

  @override
  State<StatefulWidget> createState() => _InspiredCardViewState();
}

class _InspiredCardViewState extends State<InspiredCardView> {
  final listKey = GlobalKey();
  final controller = InspiredCardController(controller: ScrollController());
  Offset dragStart = Offset.infinite;
  Offset dragUpdate = Offset.infinite;
  int itemIndex = 0;
  double _step = 0;

  @override
  void initState() {
    itemIndex = 0;
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var layoutBuilder = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        _step = width;
        var listView = _buildListView(context, listKey, width, height);
        var gesture = GestureDetector(
          child: listView,
          onPanDown: (DragDownDetails e) {
            dragStart = e.localPosition;
          },
          onPanUpdate: (DragUpdateDetails e) {
            var _newOffset = e.localPosition;
            if(dragUpdate == Offset.infinite && dragStart != Offset.infinite) {
              dragUpdate = dragStart;
            }
            if(dragUpdate != Offset.infinite) {
              var horizontalOffset = _newOffset.dx - dragUpdate.dx;
              MyLogger.debug('efantest: horizontalOffset=$horizontalOffset');
              dragUpdate = _newOffset;
              controller.moveTo(horizontalOffset);
            }
          },
          onPanEnd: (DragEndDetails e) {
            var horizontalDelta = dragUpdate.dx - dragStart.dx;
            MyLogger.debug('efantest: InspiredCard gesture: start=$dragStart, end=$dragUpdate, delta=$horizontalDelta');
            if(horizontalDelta > Constants.cardViewDragThreshold) {
              _jumpPrevious();
            } else if(horizontalDelta < - Constants.cardViewDragThreshold) {
              _jumpNext();
            } else {
              _returnNormal();
            }
            dragUpdate = Offset.infinite;
            dragStart = Offset.infinite;
          },
        );
        return gesture;
      }
    );
    return layoutBuilder;
  }

  Widget _buildListView(BuildContext context, Key key, double maxWidth, double maxHeight) {
    var listView = ListView.builder(
      shrinkWrap: true,
      key: key,
      scrollDirection: Axis.horizontal,
      controller: controller.getController(),
      itemCount: widget.seed.ids.length,
      itemBuilder: (context, index) {
        return FutureBuilder<ParagraphDesc?>(
          future: Controller.instance.docManager.getContentOfInspiredSeed(widget.seed, index),
          builder: (BuildContext context, AsyncSnapshot<ParagraphDesc?> snapshot) {
            Widget _child;
            if(snapshot.hasData) {
              // 有数据
              if(snapshot.data != null) {
                var para = snapshot.data!;
                Widget block = Center(
                  child: MindEditBlock(
                    texts: para,
                    controller: Controller.instance,
                    readOnly: true,
                  ),
                );
                if(Controller.instance.environment.isDesktop()) {
                  final padding = Constants.cardViewDesktopInnerPadding.toDouble();
                  block = Padding(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, 0),
                    child: block,
                  );
                }
                _child = SizedBox(
                  width: maxWidth,
                  height: maxHeight,
                  child: block,
                );
              } else {
                // 无数据
                _child = const Center(
                  child: Text('No data found'),
                );
              }
            } else if(snapshot.hasError) { // 出错
              MyLogger.err('Error occurred while loading block(id=${widget.seed.ids[index]} data');
              _child = const Center(
                child: Text('Error occurred while loading data...'),
              );
            } else { // 等待中，转圈圈
              _child = const SpinKitCircle(
                color: Colors.grey,
              );
            }
            return SizedBox(
              width: maxWidth,
              height: maxHeight,
              child: Center(
                child: _child,
              ),
            );
          },
        );

      },
    );
    return listView;
  }

  void _jumpPrevious() {
    itemIndex -= 1;
    if(itemIndex < 0) {
      itemIndex = 0;
    }
    controller.jumpTo(itemIndex * _step);
  }
  void _jumpNext() {
    itemIndex += 1;
    if(itemIndex >= widget.seed.ids.length) {
      itemIndex = widget.seed.ids.length - 1;
    }
    controller.jumpTo(itemIndex * _step);
  }
  void _returnNormal() {
    controller.jumpTo(itemIndex * _step);
  }
}

class InspiredCardController {
  final ScrollController controller;

  InspiredCardController({
    required this.controller,
  });

  ScrollController getController() => controller;

  void moveTo(double offset) {
    final newOffset = controller.offset - offset;
    controller.jumpTo(newOffset);
  }
  void jumpTo(double pos) {
    controller.animateTo(
      pos,
      duration: const Duration(milliseconds: Constants.cardViewScrollAnimationDuration),
      curve: Curves.ease,
    );
  }
  void dispose() {
    controller.dispose();
  }
}