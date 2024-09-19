import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/view/inspired_card.dart';

import '../mindeditor/controller/controller.dart';
import '../mindeditor/document/inspired_seed.dart';
import '../mindeditor/setting/constants.dart';

class InspiredCardPage extends StatefulWidget {
  const InspiredCardPage({super.key});

  @override
  State<InspiredCardPage> createState() => _InspiredCardPageState();
}

class _InspiredCardPageState extends State<InspiredCardPage> {
  late Future<InspiredSeed> seedFuture;

  @override
  void initState() {
    super.initState();
    _initInspiredSeed();
  }

  @override
  Widget build(BuildContext context) {
    var futureBuilder = FutureBuilder<InspiredSeed>(
      future: seedFuture,
      builder: (BuildContext context, AsyncSnapshot<InspiredSeed> snapshot) {
        if(snapshot.hasData) {
          // 有数据
          if(snapshot.data != null && snapshot.data!.ids.isNotEmpty) {
            var seed = snapshot.data!;
            var cards = _buildCards(context, seed);
            return cards;
          }
          // 无数据
          return const Center(
            child: Text('No data found'),
          );
        } else if(snapshot.hasError) { // 出错
          MyLogger.err('Error occurred while loading InspiredSeed data');
          return const Center(
            child: Text('Error occurred while loading data...'),
          );
        } else { // 等待中，转圈圈
          return const Center(
            child: SpinKitCircle(
              color: Colors.grey,
            ),
          );
        }
      },
    );
    var buttons = _buildButtons(context);
    var column = Column(
      children: [
        buttons,
        Expanded(
          child: futureBuilder,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        var paddingHorizontal = Constants.cardMinimalPaddingHorizontal;
        var paddingVertical = Constants.cardMinimalPaddingVertical;

        final screenWidth = constraints.maxWidth;
        if(screenWidth > Constants.cardMaximumWidth + 2 * paddingHorizontal) {
          paddingHorizontal = (screenWidth - Constants.cardMaximumWidth) / 2;
        }

        // final screenHeight = constraints.maxHeight;
        // if(screenHeight > Constants.cardMaximumHeight + 2 * paddingVertical) {
        //   paddingVertical = (screenHeight - Constants.cardMaximumHeight) / 2;
        // }
        //
        return Padding(
          padding: EdgeInsets.fromLTRB(paddingHorizontal, paddingVertical, paddingHorizontal, paddingVertical),
          child: Material(
            child: column,
          ),
        );
      }
    );
  }

  Widget _buildCards(BuildContext context, InspiredSeed seed) {
    return InspiredCardView(seed: seed);
  }

  Widget _buildButtons(BuildContext context) {
    var buttons = Row(
      children: [
        const Spacer(),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            child: const Icon(Icons.close),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
    var container = Container(
      alignment: Alignment.center,
      child: buttons,
    );
    return container;
  }

  void _initInspiredSeed() {
    seedFuture = Controller().docManager.getInspiredSeed();
  }
}