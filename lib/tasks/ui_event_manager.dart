class UIEventManager {
  final List<Function(bool)> _keyboardStateChangeTasks = [];
  
  void addKeyboardStateOpenTask(Function(bool) task) {
    if(!_keyboardStateChangeTasks.contains(task)) {
      _keyboardStateChangeTasks.add(task);
    }
  }
  void triggerKeyboardStateOpen(bool isOpen) {
    for(final task in _keyboardStateChangeTasks) {
      task.call(isOpen);
    }
  }
}
