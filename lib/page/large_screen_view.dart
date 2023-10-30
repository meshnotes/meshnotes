import 'package:flutter/material.dart';
import 'package:mesh_note/page/resizable_view.dart';
import 'doc_navigator.dart';
import 'doc_view.dart';

class LargeScreenView extends StatelessWidget with ResizableViewMixin {
  @override
  bool get expectedSmallView => false;
  @override
  String get loggingClassName => "LargeScreenView";

  const LargeScreenView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    routeIfResize(context);
    return Row(
      children: [
        const SizedBox(
          width: 240,
          child: DocumentNavigator(smallView: false),
        ),
        Container(
          width: 2,
          color: Colors.grey[100],
        ),
        Expanded(
          child: DocumentView(smallView: false),
        )
      ],
    );
  }
}
