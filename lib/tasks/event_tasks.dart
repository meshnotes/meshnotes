import 'dart:async';
import 'package:mesh_note/util/util.dart';

class EvenTasksManager {
  final List<Function()> _afterInitTasks = [];
  final List<Function()> _idleTasks = [];
  final List<Function()> _userClickTasks = [];
  final List<Function()> _userInputTasks = [];
  final Map<String, _TimerTask> _timerTaskMap = {};
  Timer? _timer;

  void addAfterInitTask(Function() task) {
    if(!_afterInitTasks.contains(task)) {
      _afterInitTasks.add(task);
    }
  }
  triggerAfterInit() {
    for(final task in _afterInitTasks) {
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
}

class _TimerTask {
  final Function() task;
  final int intervalMillis;
  int lastTriggerTimeMillis = 0;

  _TimerTask(this.task, this.intervalMillis);
}
