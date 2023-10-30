import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../net/status.dart';
import '../controller/controller.dart';
import '../setting/constants.dart';

class NetworkDetailView extends StatelessWidget {
  List<NodeInfo> nodes;

  NetworkDetailView({
    super.key,
    required this.nodes,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return NetworkDetailView(nodes: Controller.instance.network.getNetworkDetails());
      },
      fullscreenDialog: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    double padding = Constants.settingViewPhonePadding.toDouble();
    if(Controller.instance.environment.isDesktop()) {
      padding = Constants.settingViewDesktopPadding.toDouble();
    }
    var topButtons = _buildTopButtons(context);
    var viewBody = _buildNetworkDetails(context);
    return Scaffold(
        body: Column(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(0, 10, 0, 0)),
            topButtons,
            Expanded(
              child: Container(
                padding: EdgeInsets.all(padding),
                child: viewBody,
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 10),),
          ],
        )
    );
  }

  Widget _buildTopButtons(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        TextButton(
          child: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildNetworkDetails(BuildContext context) {
    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (ctx, idx) {
        final item = nodes[idx];
        return Column(
          children: [
            Text(item.id),
            Text(item.name),
            Text(item.status.toString()),
          ],
        );
      },
    );
  }
}