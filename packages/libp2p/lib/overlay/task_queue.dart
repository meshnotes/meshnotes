import 'villager_node.dart';

enum TaskType {
  connect,
  sayHello,
  reportStatus,
}

class TaskItem {
  TaskType taskType;
  VillagerNode node;

  TaskItem({
    required this.taskType,
    required this.node,
  });
}

class TaskQueue {
  List<TaskItem> _tasks = [];

  void enqueue(TaskType type, VillagerNode node) {
    final item = TaskItem(taskType: type, node: node);
    _tasks.add(item);
  }

  void enqueueAllWithType(TaskType type, List<VillagerNode> nodes) {
    for(var node in nodes) {
      enqueue(type, node);
    }
  }

  List<TaskItem> popAllWithType(TaskType type) {
    List<TaskItem> matchResult = [];
    for(final item in _tasks) {
      if(item.taskType == type) {
        matchResult.add(item);
      }
    }
    if(matchResult.isNotEmpty) {
      for(final item in matchResult) {
        _tasks.remove(item);
      }
    }
    return matchResult;
  }
}