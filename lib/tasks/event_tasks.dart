import 'dart:async';
import 'package:mesh_note/util/util.dart';

class EvenTasksManager {
  final List<Function()> _afterInitTasks = [];
  final List<Function()> _idleTasks = [];
  final List<Function()> _userClickTasks = []; // Tasks when user clicks in the editor area
  final List<Function()> _userInputTasks = []; // Tasks when user input using keyboard or soft keyboard
  final List<Function()> _userSwitchToNavigator = []; // Tasks when user switches to navigator(in small screen mode)
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
}

class _TimerTask {
  final Function() task;
  final int intervalMillis;
  int lastTriggerTimeMillis = 0;

  _TimerTask(this.task, this.intervalMillis);
}
