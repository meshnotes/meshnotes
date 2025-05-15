import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';
import 'ai_executor.dart';
import 'prompts.dart';

class AIDialog extends StatefulWidget {
  final PluginProxy proxy;
  final OpenAiExecutor executor;

  const AIDialog({
    super.key, 
    required this.proxy,
    required this.executor,
  });
  @override
  State<StatefulWidget> createState() => _AIDialogState();
}

class _AIDialogState extends State<AIDialog> {
  List<_AIContent> contents = [
    // _AIContent(text: '', prompt: '', result: 'content1'),
    // _AIContent(text: '', prompt: '', result: 'content2'),
    // _AIContent(text: '', prompt: '', result: 'content3'),
  ];
  final List<_AIAction> _supportedActions = [
    _AIAction(
      displayedText: 'Summary',
      promptTemplate: 'Summary the following content:',
      systemPrompt: SystemPrompts.summary,
    ),
    _AIAction(
      displayedText: 'Continue writing',
      promptTemplate: 'Continue writing the following text:',
      systemPrompt: SystemPrompts.continueWriting,
    ),
    _AIAction(
      displayedText: 'Rewrite more',
      promptTemplate: 'Rewrite the following text to amplify the content:',
      systemPrompt: SystemPrompts.rewriteMore,
    ),
    _AIAction(
      displayedText: 'Rewrite simpler',
      promptTemplate: 'Rewrite the following text to simplify the content:',
      systemPrompt: SystemPrompts.rewriteSimpler,
    ),
  ];
  String originalContent = '';
  ScrollController scrollController = ScrollController();
  bool _showSelection = false;
  bool _showVoiceChat = false;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  String? _lastEditingBlockId;
  
  @override
  void initState() {
    super.initState();
    originalContent = widget.proxy.getSelectedOrFocusedContent();
  }

  @override
  Widget build(BuildContext context) {
    var buttonLayer = _buildButtonLayer();
    var assistLayer = _buildAssistLayer(!_showVoiceChat && _showSelection); // Prior to show voice chat
    var stack = Stack(
      children: [
        buttonLayer,
        assistLayer,
      ],
    );
    return stack;
  }

  /// Build the assistant button(summary, continue writing, etc.), and the realtime voice chat button
  Widget _buildButtonLayer() {
    var listBuilder = ListView.builder(
      controller: scrollController,
      shrinkWrap: true,
      itemCount: contents.length,
      itemBuilder: (context, idx) {
        _AIChatCard card = _AIChatCard(
          key: ValueKey(idx),
          content: contents[idx],
          copyAction: _copyResult,
          appendAction: _appendResult,
        );
        return card;
      },
    );
    var column = Column(
      children: [
        Expanded(
          child: listBuilder,
        ),
        Row(
          children: [
            Expanded(
              child: CompositedTransformTarget(
                link: _layerLink,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    // color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  width: double.infinity,
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(8.0),
                    child: const Text('Ask AI anything here', style: TextStyle(color: Colors.grey),),
                    onPressed: () => _switchToAssistLayer(),
                  ),
                ),
                // child: CupertinoTextField(
                //   padding: const EdgeInsets.all(8.0),
                //   placeholder: 'Ask AI anything here...',
                //   focusNode: _focusNode,
                //   onTap: () => _switchActionsLayer(),
                //   // onTapOutside: (_) {
                //   //   _focusNode.unfocus();
                //   //   _triggerActionsLayer(false);
                //   // },
                // ),
              ),
            ),
          ],
        ),
      ],
    );
    var gestureDetector = GestureDetector(
      child: column,
      onTap: () {
        _triggerActionsLayer(false);
        _triggerVoiceChatLayer(false);
      },
    );
    return gestureDetector;
  }

  void _switchToAssistLayer() {
    bool show = !_showSelection;
    _triggerActionsLayer(show);
  }
  void _triggerActionsLayer(bool show) {
    if(show != _showSelection) {
      setState(() {
        _showSelection = show;
      });
    }
  }
  void _triggerVoiceChatLayer(bool show) {
    if(show != _showVoiceChat) {
      setState(() {
        _showVoiceChat = show;
      });
    }
  }

  Widget _buildAssistLayer(bool visible) {
    var container = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5.0),
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[200]!, width: 1.0),
      ),
      padding: const EdgeInsets.all(8.0),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _supportedActions.length + 1, // The last item is TextField
        itemBuilder: (context, idx) {
          if(idx < _supportedActions.length) {
            return Container(
              margin: const EdgeInsets.fromLTRB(0, 2.0, 0, 2.0),
              child: CupertinoButton(
                padding: const EdgeInsets.all(4.0),
                minSize: 14.0,
                child: Text(_supportedActions[idx].displayedText),
                onPressed: () {
                  _triggerActionsLayer(false);
                  _executeAction(_supportedActions[idx]);
                },
              ),
            );
          }
          return CupertinoTextField(
            padding: const EdgeInsets.all(8.0),
            placeholder: 'Ask AI anything here...',
            focusNode: _focusNode,
            onSubmitted: (v) {},
            // onTap: () => _switchActionsLayer(),
            // onTapOutside: (_) {
            //   _focusNode.unfocus();
            //   _triggerActionsLayer(false);
            // },
          );
        },
      ),
    );
    var composited = CompositedTransformFollower(
      link: _layerLink,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.bottomLeft,
      child: container,
    );
    var visibility = Visibility(
      visible: visible,
      child: composited,
    );
    return visibility;
  }

  void _executeAction(_AIAction action) {
    if(originalContent.isNotEmpty) {
      var prompt = action.getPrompt();
      MyLogger.info('_executeAction: prompt=$prompt');
      _AIContent item = _AIContent(
        text: originalContent,
        prompt: prompt,
        result: '',
      );
      contents.add(item);
      _update(item.text);
      widget.executor.execute(action.getSystemPrompt(), prompt, originalContent).then((value) {
        item.result = value;
        _update(value);
      });
    }
  }
  void _update(String result) {
    setState(() {
    });
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      scrollController.animateTo(scrollController.position.maxScrollExtent, duration: const Duration(microseconds: 300), curve: Curves.easeOut);
    });
  }

  void _copyResult(String text) {
    widget.proxy.sendTextToClipboard(text);
  }
  void _appendResult(String text) {
    if(_lastEditingBlockId == null) {
      String? blockId = widget.proxy.getEditingBlockId();
      _lastEditingBlockId = blockId;
    }
    if(_lastEditingBlockId == null) return;

    var newBlockId = widget.proxy.appendTextToNextBlock(_lastEditingBlockId!, text);
    if(newBlockId != null) {
      _lastEditingBlockId = newBlockId;
    }
  }
}

class _AIContent {
  String text;
  String prompt;
  String result;
  
  _AIContent({
    required this.text,
    required this.prompt,
    required this.result,
  });
}

typedef _CallbackFunction = void Function(String);

class _AIChatCard extends StatelessWidget {
  final _AIContent content;
  final _CallbackFunction copyAction;
  final _CallbackFunction appendAction;
  const _AIChatCard({
    required super.key,
    required this.content,
    required this.copyAction,
    required this.appendAction,
  });

  @override
  Widget build(BuildContext context) {
    Widget? resultWidget;
    if(content.result.isEmpty) {
      resultWidget = LoadingAnimationWidget.progressiveDots(color: Colors.black54, size: 14.0);
      // return Text('Querying: ${content.prompt}');
    } else {
      resultWidget = Text(content.result);
    }
    var column = Column(
      children: [
        resultWidget,
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.all(4.0),
              minSize: 16.0,
              child: const Icon(Icons.copy_all),
              onPressed: () => copyAction(content.result),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(4.0),
              minSize: 16.0,
              child: const Icon(Icons.add),
              onPressed: () => appendAction(content.result),
            ),
          ],
        ),
      ],
    );
    var container = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.0),
        color: Colors.grey[100],
      ),
      margin: const EdgeInsets.fromLTRB(16.0, 16.0, 4.0, 16.0),
      padding: const EdgeInsets.all(8.0),
      // color: Colors.grey[100],
      child: column,
    );
    return container;
  }
}

class _AIAction {
  String displayedText;
  String promptTemplate;
  String systemPrompt;

  _AIAction({
    required this.displayedText,
    required this.promptTemplate,
    required this.systemPrompt,
  });

  String getPrompt() {
    return promptTemplate;
  }

  String getSystemPrompt() => systemPrompt;
}