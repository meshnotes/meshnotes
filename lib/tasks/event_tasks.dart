import 'dart:async';
import 'package:mesh_note/util/util.dart';

enum SyncDirection { download, upload }

class EvenTasksManager {
  bool _downloading = false;
  int _downloadProgress = 0;
  final Map<int, (int, int)> _uploads = {};
  final List<Function()> _afterReadyTasks = [];
  final List<Function()> _idleTasks = [];
  final List<Function()> _userClickTasks = []; // Tasks when user clicks in the editor area
  final List<Function()> _userInputTasks = []; // Tasks when user input using keyboard or soft keyboard
  final List<Function()> _userSwitchToNavigator = []; // Tasks when user switches to navigator(in small screen mode)
  final List<Function()> _settingChangedTasks = []; // Tasks when user changes settings
  final List<Function()> _userInfoChangedTasks = []; // Tasks when user changes user info
  final List<Function(bool isSyncing, int progress, SyncDirection direction)> _syncingTasks = []; // Tasks when syncing
  final List<Function()> _afterDocumentOpenedOnceTasks = []; // Tasks when document is opened, which should be triggered only once
  final Map<String, _TimerTask> _timerTaskMap = {};
  Timer? _timer;

  void addAfterReadyTask(Function() task) {
    if(!_afterReadyTasks.contains(task)) {
      _afterReadyTasks.add(task);
    }
  }
  void triggerAfterReady() {
    for(final task in _afterReadyTasks) {
      task.call();
    }
  }
  
  void addIdleTask(Function() task) {
    if(!_idleTasks.contains(task)) {
      _idleTasks.add(task);
    }
  }
  void triggerIdle() {
    for(final task in _idleTasks) {
      task.call();
    }
  }

  void addTimerTask(String taskId, Function() task, int intervalMillis) {
    _timer ??= Timer.periodic(const Duration(milliseconds: 5000), (timer) {
        _triggerTimerTasks();
    });
    if(!_timerTaskMap.containsKey(taskId)) {
      _timerTaskMap[taskId] = _TimerTask(task, intervalMillis);
    }
  }
  void _triggerTimerTasks() {
    final now = Util.getTimeStamp();
    for(final task in _timerTaskMap.values) {
      if(now - task.lastTriggerTimeMillis > task.intervalMillis) {
        task.task.call();
        task.lastTriggerTimeMillis = now;
      }
    }
  }

  void addUserClickTask(Function() task) {
    if(!_userClickTasks.contains(task)) {
      _userClickTasks.add(task);
    }
  }
  void triggerUserClickEvent() {
    for(final task in _userClickTasks) {
      task.call();
    }
  }

  void addUserInputTask(Function() task) {
    if(!_userInputTasks.contains(task)) {
      _userInputTasks.add(task);
    }
  }
  void triggerUserInputEvent() {
    for(final task in _userInputTasks) {
      task.call();
    }
  }

  void addUserSwitchToNavigatorTask(Function() task) {
    if(!_userSwitchToNavigator.contains(task)) {
      _userSwitchToNavigator.add(task);
    }
  }
  void triggerUserSwitchToNavigatorEvent() {
    for(final task in _userSwitchToNavigator) {
      task.call();
    }
  }

  void addSettingChangedTask(Function() task) {
    if(!_settingChangedTasks.contains(task)) {
      _settingChangedTasks.add(task);
    }
  }
  void triggerSettingChanged() {
    for(final task in _settingChangedTasks) {
      task.call();
    }
  }

  void addSyncingTask(Function(bool isSyncing, int progress, SyncDirection direction) task) {
    if(!_syncingTasks.contains(task)) {
      _syncingTasks.add(task);
    }
  }
  void removeSyncingTask(Function(bool isSyncing, int progress, SyncDirection direction) task) {
    _syncingTasks.remove(task);
  }
  void triggerUpdateSyncing(bool isSyncing, int progress) {
    _downloading = isSyncing;
    _downloadProgress = progress;
    _notifySyncing();
  }

  void triggerUpdateUploading(int transferId, int sent, int total, bool finished) {
    if(finished) {
      _uploads.remove(transferId);
    } else {
      _uploads[transferId] = (sent, total);
    }
    _notifySyncing();
  }

  void _notifySyncing() {
    final uploading = !_downloading && _uploads.isNotEmpty;
    final sent = _uploads.values.fold(0, (sum, item) => sum + item.$1);
    final total = _uploads.values.fold(0, (sum, item) => sum + item.$2);
    final progress = uploading && total > 0 ? sent * 100 ~/ total : _downloadProgress;
    for(final task in _syncingTasks) {
      task.call(_downloading || uploading, progress, uploading ? SyncDirection.upload : SyncDirection.download);
    }
  }

  void addUserInfoChangedTask(Function() task) {
    if(!_userInfoChangedTasks.contains(task)) {
      _userInfoChangedTasks.add(task);
    }
  }
  void removeUserInfoChangedTask(Function() task) {
    _userInfoChangedTasks.remove(task);
  }
  void triggerUserInfoChanged() {
    for(final task in _userInfoChangedTasks) {
      task.call();
    }
  }

  void addAfterDocumentOpenedOnceTask(Function() task) {
    if(!_afterDocumentOpenedOnceTasks.contains(task)) {
      _afterDocumentOpenedOnceTasks.add(task);
    }
  }
  void triggerAfterDocumentOpenedOnce() {
    for(final task in _afterDocumentOpenedOnceTasks) {
      task.call();
    }
    _afterDocumentOpenedOnceTasks.clear();
  }
}

class _TimerTask {
  final Function() task;
  final int intervalMillis;
  int lastTriggerTimeMillis = 0;

  _TimerTask(this.task, this.intervalMillis);
}
