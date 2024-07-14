class EvenTasksManager {
  final List<Function()> _afterInitTasks = [];

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
}