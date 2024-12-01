enum ChatRole {
  user,
  assistant,
}
class ChatMessage {
  final ChatRole role;
  final String content;
  final bool isComposing;
  ChatMessage({required this.role, required this.content, this.isComposing = false});
}

class ChatMessages {
  List<ChatMessage> messages;
  ChatMessages({
    List<ChatMessage>? messages,
  }): messages = messages ?? [];

  List<ChatMessage> getRawMessages() => messages;

  ChatMessage? _popComposingMessage() {
    for(int i = messages.length - 1; i >= 0; i--) {
      if(messages[i].isComposing) {
        return messages.removeAt(i);
      }
    }
    return null;
  }

  void updateAiTranscriptDelta(String text) {
    final oldMessage = _popComposingMessage();
    if(oldMessage != null) {
      messages.add(ChatMessage(role: ChatRole.assistant, content: (oldMessage.content + text).trim(), isComposing: true));
    } else {
      messages.add(ChatMessage(role: ChatRole.assistant, content: text.trim(), isComposing: true));
    }
  }

  void updateAiTranscriptDone(String text) {
    final _ = _popComposingMessage();
    messages.add(ChatMessage(role: ChatRole.assistant, content: text.trim()));
  }

  void updateUserTranscriptDone(String text) {
    messages.add(ChatMessage(role: ChatRole.user, content: text.trim()));
  }

  String buildHistory() {
    return messages.map((e) => '${e.role}: ${e.content}').join('\n');
  }

  bool isEmpty() => messages.isEmpty;
}
