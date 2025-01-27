class EvenTasksManager {
  final List<Function()> _afterInitTasks = [];
  final List<Function()> _idleTasks = [];

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
}