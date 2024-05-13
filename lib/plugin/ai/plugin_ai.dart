import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';

import 'kimi_agent.dart';

class PluginAI implements PluginInstance {
  static const _dialogTitle = 'AI assistant';
  static const _settingKeyApiKey = 'kimi_api_key';
  late PluginProxy _proxy;
  String? _apiKey;

  @override
  void initPlugin(PluginProxy proxy) {
    _proxy = proxy;
    final toolbarInfo = ToolbarInformation(buttonIcon: Icons.wb_incandescent_outlined, action: _aiAction, tip: 'AI assistant');
    final registerInfo = PluginRegisterInformation(toolbarInformation: toolbarInfo);
    proxy.registerPlugin(registerInfo);
  }

  @override
  void start() {
    // TODO: implement start
  }

  void _aiAction() {
    _apiKey = _proxy.getSettingValue(_settingKeyApiKey);
    MyLogger.info('AI action!');
    if(_apiKey != null && _apiKey!.isNotEmpty) {
      AIExecutor kimi = AIExecutor(apiKey: _apiKey!);
      var dialog = _AIDialog(
        proxy: _proxy,
        executor: kimi,
      );
      _proxy.showDialog(_dialogTitle, dialog);
    } else {
      MyLogger.info('AI parameter is not ready yet!');
      var dialog = const Text('Please set api key first');
      _proxy.showDialog(_dialogTitle, dialog);
    }
  }
}

class _AIDialog extends StatefulWidget {
  final PluginProxy proxy;
  final AIExecutor executor;

  const _AIDialog({
    required this.proxy,
    required this.executor,
  });
  @override
  State<StatefulWidget> createState() => _AIDialogState();
}

class _AIDialogState extends State<_AIDialog> {
  List<_AIContent> contents = [
    // _AIContent(text: '', prompt: '', result: 'content1'),
    // _AIContent(text: '', prompt: '', result: 'content2'),
    // _AIContent(text: '', prompt: '', result: 'content3'),
  ];
  final List<_AIAction> _supportedActions = [
    _AIAction(displayedText: 'Summary', promptTemplate: '对下面内容进行简要总结：'),
    _AIAction(displayedText: 'Continue writing', promptTemplate: '接着下面内容继续写下去：'),
    _AIAction(displayedText: 'Rewrite more', promptTemplate: '改写下面内容，使其更丰富：'),
    _AIAction(displayedText: 'Rewrite simpler', promptTemplate: '改写下面内容，使其更简洁'),
  ];
  String originalContent = '';
  ScrollController scrollController = ScrollController();
  bool _showSelection = false;
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
    var bottomLayer = _buildBottomLayer();
    var upperLayer = _buildUpperLayer(_showSelection);
    var stack = Stack(
      children: [
        bottomLayer,
        upperLayer,
      ],
    );
    return stack;
  }

  Widget _buildBottomLayer() {
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
        CompositedTransformTarget(
          link: _layerLink,
          child: CupertinoTextField(
            padding: const EdgeInsets.all(8.0),
            placeholder: 'Ask AI anything here...',
            focusNode: _focusNode,
            onTap: () => _switchActionsLayer(),
            // onTapOutside: (_) {
            //   _focusNode.unfocus();
            //   _triggerActionsLayer(false);
            // },
          ),
        ),
      ],
    );
    return column;
  }

  void _switchActionsLayer() {
    bool show = !_showSelection;
    _triggerActionsLayer(show);
  }
  void _triggerActionsLayer(bool show) {
    if(show != _showSelection) {
      MyLogger.info('efantest: show=$show');
      setState(() {
        _showSelection = show;
      });
    }
  }

  Widget _buildUpperLayer(bool visible) {
    var container = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5.0),
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[200]!, width: 1.0),
      ),
      padding: const EdgeInsets.all(8.0),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _supportedActions.length,
        itemBuilder: (context, idx) {
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
        },
      ),
    );
    var composited = CompositedTransformFollower(
      link: _layerLink,
      targetAnchor: Alignment.topLeft,
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
      var prompt = action.getPrompt(originalContent);
      MyLogger.info('_executeAction: prompt=$prompt');
      _AIContent item = _AIContent(
        text: originalContent,
        prompt: prompt,
        result: '',
      );
      contents.add(item);
      _update(item.text);
      widget.executor.execute(prompt).then((value) {
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
      resultWidget = LoadingAnimationWidget.prograssiveDots(color: Colors.black54, size: 14.0);
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

  _AIAction({
    required this.displayedText,
    required this.promptTemplate,
  });

  String getPrompt(String text) {
    return promptTemplate + text;
  }
}