import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:flutter/material.dart';
import '../mindeditor/controller/controller.dart';
import 'sync_progress_widget.dart';
import '../tasks/event_tasks.dart';

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
  int _syncProgress = 0;
  SyncDirection _syncDirection = SyncDirection.download;
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
              child: SyncProgressWidget(
                progress: _syncProgress,
              direction: _syncDirection,
                size: 32,
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

  void _updateSyncing(bool syncing, int progress, SyncDirection direction) {
    if(syncing == _isSyncing && progress == _syncProgress && direction == _syncDirection) {
      return;
    }
    setState(() {
      _isSyncing = syncing;
      _syncProgress = progress;
      _syncDirection = direction;
    });
  }
}
