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
  bool _isSyncing = false;
  List<String>? titles;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerTitleBar(this);
    widget.controller.eventTasksManager.addSyncingTask(_updateSyncing);
  }

  @override
  void dispose() {
    CallbackRegistry.unregisterTitleBar(this);
    widget.controller.eventTasksManager.removeSyncingTask(_updateSyncing);
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
    
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          if (_isSyncing && widget.controller.environment.isSmallView(context))
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                ),
              ),
            ),
          Expanded(
            child: Text(
              texts.last,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontStyle: FontStyle.normal,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.normal,
                // fontFamily: 'Yuanti SC',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void setTitles(List<String> _titles) {
    setState(() {
      titles = _titles;
    });
  }

  void clearTitles() {
    setState(() {
      titles = null;
    });
  }

  void _updateSyncing(bool syncing) {
    if(syncing == _isSyncing) {
      return;
    }
    setState(() {
      _isSyncing = syncing;
    });
  }
}