import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:flutter/material.dart';

import '../mindeditor/controller/controller.dart';

class DocumentTitleBar extends StatefulWidget {
  final Controller controller;

  const DocumentTitleBar({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => DocumentTitleBarState();
}

class DocumentTitleBarState extends State<DocumentTitleBar> {
  List<String>? titles;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerTitleBar(this);
  }

  @override
  void dispose() {
    CallbackRegistry.unregisterTitleBar(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildTitleBar(titles);
  }

  Widget _buildTitleBar(List<String>? texts) {
    if(texts == null || texts.isEmpty) {
      return Container();
    }
    var widgets = <Widget>[];
    for(var str in texts) {
      var child = TextButton(
        child: Text(str),
        onPressed: () {},
        style: TextButton.styleFrom(
          padding: widget.controller.setting.titleTextPadding,
          minimumSize: const Size(0, 0),
        ),
      );
      widgets.add(child);
      var slash = Text(
        '/',
        style: TextStyle(
          color: widget.controller.setting.titleSlashColor,
        ),
      );
      widgets.add(slash);
    }
    widgets.removeLast();
    return Row(
      children: widgets,
    );
  }

  void setTitles(List<String> _titles) {
    setState(() {
      titles = _titles;
    });
  }
}