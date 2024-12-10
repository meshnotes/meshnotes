import 'package:flutter/material.dart';
import 'package:mesh_note/plugin/ai/realtime_chat/chat_messages.dart';
import 'package:mesh_note/util/util.dart';

class Subtitles extends StatefulWidget {
  final ChatMessages messages;
  const Subtitles({
    super.key,
    required this.messages,
  });

  @override
  State<Subtitles> createState() => SubtitlesState();
}

class SubtitlesState extends State<Subtitles> {
  ChatMessages _messages = ChatMessages();
  final ScrollController _scrollController = ScrollController();
  final listViewKey = GlobalKey();
  
  @override
  void initState() {
    super.initState();
    _messages = widget.messages;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messageView = _buildMessageListView();
    return Container(
      margin: const EdgeInsets.all(6),
      height: double.infinity,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          _scrollController.position.moveTo(
            _scrollController.offset - details.delta.dy,
          );
        },
        child: messageView,
      ),
    );
  }

  void updateMessages(ChatMessages messages) {
    setState(() {
      _messages = messages;
      Util.runInPostFrame(() {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    });
  }

  ListView _buildMessageListView() {
    List<ChatMessage> messages = _messages.messages;
    const marginOfFirst = EdgeInsets.fromLTRB(0, 0, 0, 0);
    const marginOfOther = EdgeInsets.fromLTRB(0, 4, 0, 0);
    const colorOfUser = Color.fromARGB(255, 114, 189, 255);
    const colorOfAi = Colors.white;
    return ListView.builder(
      key: listViewKey,
      controller: _scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final text = message.content;
        final isAi = message.role == ChatRole.assistant;
        final isUser = message.role == ChatRole.user;
        final color = isAi ? colorOfAi : colorOfUser;
        final key = 'msg-${message.role}-$index';
        final container = Container(
          key: ValueKey(key),
          margin: index == 0 ? marginOfFirst : marginOfOther,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontStyle: FontStyle.normal,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.normal,
              fontFamily: 'Yuanti SC',
            ),
          ),
        );
        final row = Row(
          children: [
            isUser ? const SizedBox(width: 32) : const SizedBox(),
            Expanded(child: container),
            isAi ? const SizedBox(width: 32) : const SizedBox(),
            const SizedBox(width: 16),
          ],
        );
        return row;
      },
    );
  }
} 