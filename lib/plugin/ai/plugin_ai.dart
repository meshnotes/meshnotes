import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';
import 'abstract_agent.dart';
import 'kimi_agent.dart';
import 'openai_agent.dart';
import 'prompt.dart';

class PluginAI implements PluginInstance {
  static const _dialogTitle = 'AI assistant';
  static const _pluginName = 'ai_support';
  static const _settingKeyKimiApiKey = 'kimi_api_key';
  static const _settingKeyOpenAiApiKey = 'openai_api_key';
  static const _settingKeyDefaultAiService = 'default_ai_service';
  static const String settingKeyPluginKimiApiKey = 'kimi_api_key';
  static const String settingNamePluginKimiApiKey = 'API key for Kimi.ai';
  static const String settingCommentPluginKimiApiKey = 'API key for kimi.ai';
  static const String settingKeyPluginOpenAiApiKey = 'openai_api_key';
  static const String settingNamePluginOpenAiApiKey = 'API key for OpenAI';
  static const String settingCommentPluginOpenAiApiKey = 'API Key for OpenAI';
  static const String settingKeyPluginDefaultAiService = 'default_ai_service';
  static const String settingNamePluginDefaultAiService = 'AI service provider';
  static const String settingCommentPluginDefaultAiService = 'Default AI service(e.g. chatgpt, or kimi.ai)';
  static const String settingDefaultPluginDefaultAiService = 'chatgpt';
  late PluginProxy _proxy;

  @override
  void initPlugin(PluginProxy proxy) {
    _proxy = proxy;
    final toolbarInfo = ToolbarInformation(buttonIcon: Icons.wb_incandescent_outlined, action: _aiAction, tip: 'AI assistant');
    final settingInfo = _genPluginSettings();
    final registerInfo = PluginRegisterInformation(
      pluginName: _pluginName,
      toolbarInformation: toolbarInfo,
      settingsInformation: settingInfo,
      onBlockChanged: _blockChangedHandler,
    );
    proxy.registerPlugin(registerInfo);
  }

  @override
  void start() {
    // TODO: implement start
  }

  List<PluginSetting> _genPluginSettings() {
    List<PluginSetting> result = [
      PluginSetting(
        settingKey: settingKeyPluginKimiApiKey,
        settingName: settingNamePluginKimiApiKey,
        settingComment: settingCommentPluginKimiApiKey,
      ),
      PluginSetting(
        settingKey: settingKeyPluginOpenAiApiKey,
        settingName: settingNamePluginOpenAiApiKey,
        settingComment: settingCommentPluginOpenAiApiKey,
      ),
      PluginSetting(
        settingKey: settingKeyPluginDefaultAiService,
        settingName: settingNamePluginDefaultAiService,
        settingComment: settingCommentPluginDefaultAiService,
        settingDefaultValue: settingDefaultPluginDefaultAiService,
      ),
    ];
    return result;
  }
  void _aiAction() {
    var _executor = _buildAiExecutor();
    if(_executor != null) {
      var dialog = _AIDialog(
        proxy: _proxy,
        executor: _executor,
      );
      _proxy.showDialog(_dialogTitle, dialog);
    } else {
      MyLogger.info('AI parameter is not ready yet!');
      var dialog = const Text('Please set api key first');
      _proxy.showDialog(_dialogTitle, dialog);
    }
  }

  AiExecutor? _buildAiExecutor() {
    var service = _proxy.getSettingValue(_settingKeyDefaultAiService);
    if(service == null || service.isEmpty) return null;
    switch(service) {
      case 'kimi.ai':
        return _buildKimiExecutor();
      case 'chatgpt':
        return _buildChatGptExecutor();
      default:
        return _buildChatGptExecutor();
    }
  }
  AiExecutor? _buildKimiExecutor() {
    var _apiKey = _proxy.getSettingValue(_settingKeyKimiApiKey);
    if(_apiKey == null || _apiKey.isEmpty) {
      return null;
    }
    KimiExecutor kimi = KimiExecutor(apiKey: _apiKey);
    return kimi;
  }
  AiExecutor? _buildChatGptExecutor() {
    var _apiKey = _proxy.getSettingValue(_settingKeyOpenAiApiKey);
    if(_apiKey == null || _apiKey.isEmpty) {
      return null;
    }
    OpenAiExecutor openAi = OpenAiExecutor(apiKey: _apiKey);
    return openAi;
  }
  List<String> noneExpression = ['None', 'None.', 'none', 'none.'];
  void _blockChangedHandler(BlockChangedEventData data) {
    MyLogger.info('AI plugin receive block changed: id=${data.blockId}, content=${data.content}');
    var executor = _buildAiExecutor();
    final userPrompt = 'Here is the user\'s note: ${data.content}';
    const systemPrompt = Prompts.systemPromptForBlockSuggestion;
    executor?.execute(userPrompt: userPrompt, systemPrompt: systemPrompt).then((value) {
      MyLogger.info('Here is AI\'s reply: $value');
      final trimValue = value.trim();
      if(noneExpression.contains(trimValue)) {
        _proxy.clearExtra(data.blockId);
        return;
      }
      final _m = jsonDecode(value);
      if(_m is! Map<String, dynamic>) return;
      Map<String, dynamic> map = _m;
      final comment = map['comment'];
      final suggestion = map['suggestion'];
      if(comment == null || comment.toString().isEmpty) return;
      String aiReview = suggestion == null? comment: '$comment\n\n$suggestion';
      _proxy.addExtra(data.blockId, aiReview);
    });
  }
}

class _AIDialog extends StatefulWidget {
  final PluginProxy proxy;
  final AiExecutor executor;

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
    _AIAction(
      displayedText: 'Summary',
      promptTemplate: 'Summary the following content: ',
      //systemPrompt: 'Answer in the original language',
    ),
    _AIAction(
      displayedText: 'Continue writing',
      promptTemplate: 'Here is a text, continue writing by the original language: ',
    ),
    _AIAction(
      displayedText: 'Rewrite more',
      promptTemplate: 'Rewrite the following text, make it better and more verbose, by the original language: ',
    ),
    _AIAction(
      displayedText: 'Rewrite simpler',
      promptTemplate: 'Rewrite the following text, make it more concise and simpler, by the original language: ',
    ),
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
              onPressed: () => _switchActionsLayer(),
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
      ],
    );
    var gestureDetector = GestureDetector(
      child: column,
      onTap: () {
        _triggerActionsLayer(false);
      },
    );
    return gestureDetector;
  }

  void _switchActionsLayer() {
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
      var prompt = action.getPrompt(originalContent);
      MyLogger.info('_executeAction: prompt=$prompt');
      _AIContent item = _AIContent(
        text: originalContent,
        prompt: prompt,
        result: '',
      );
      contents.add(item);
      _update(item.text);
      widget.executor.execute(userPrompt: prompt, systemPrompt: action.getSystemPrompt()).then((value) {
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
  String? systemPrompt;

  _AIAction({
    required this.displayedText,
    required this.promptTemplate,
    this.systemPrompt,
  });

  String getPrompt(String text) {
    return promptTemplate + text;
  }

  String? getSystemPrompt() => systemPrompt;
}