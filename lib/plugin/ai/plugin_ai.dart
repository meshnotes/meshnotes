import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';
import 'ai_diaglog.dart';
import 'ai_executor.dart';
import 'llm_providers.dart';
import 'prompts.dart';
import 'realtime_chat/realtime_chat_dialog.dart';

class PluginAI implements PluginInstance {
  static const _dialogTitle = 'AI assistant';
  static const _pluginName = 'ai_support';
  static const String settingKeyPluginKimiApiKey = 'kimi_api_key';
  static const String settingNamePluginKimiApiKey = 'API key for Kimi.ai';
  static const String settingCommentPluginKimiApiKey = 'API key for kimi.ai';

  static const String settingKeyPluginOpenAiApiKey = 'openai_api_key';
  static const String settingNamePluginOpenAiApiKey = 'API key for OpenAI';
  static const String settingCommentPluginOpenAiApiKey = 'API Key for OpenAI';

  static const String settingKeyPluginQwenApiKey = 'qwen_api_key';
  static const String settingNamePluginQwenApiKey = 'API key for Qwen';
  static const String settingCommentPluginQwenApiKey = 'API Key for Qwen';

  static const String settingKeyPluginDeepSeekApiKey = 'deepseek_api_key';
  static const String settingNamePluginDeepSeekApiKey = 'API key for DeepSeek';
  static const String settingCommentPluginDeepSeekApiKey = 'API Key for DeepSeek';

  static const String settingKeyPluginDefaultAiService = 'default_ai_service';
  static const String settingNamePluginDefaultAiService = 'AI service provider';
  static const String settingCommentPluginDefaultAiService = 'Choose AI service(chatgpt/kimi.ai/qwen/deepseek. Default is $settingDefaultPluginDefaultAiService)';
  static const String settingDefaultPluginDefaultAiService = 'chatgpt';

  static const String settingKeyUseAiForExtra = 'use_ai_for_extra';
  static const String settingNameUseAiForExtra = 'Use AI for block extra';
  static const String settingCommentUseAiForExtra = 'Enable AI to generate extra information for editing block';
  static const String settingDefaultUseAiForExtra = 'false';

  late PluginProxy _proxy;

  @override
  void initPlugin(PluginProxy proxy) {
    _proxy = proxy;
    _registerEditorPlugin(_proxy);
    _registerGlobalPlugin(_proxy);
  }

  @override
  void start() {
    // Do nothing
  }

  void _registerEditorPlugin(PluginProxy proxy) {
    final toolbarInfo = ToolbarInformation(
      buttonIcon: Icons.wb_incandescent_outlined,
      action: _aiAction,
      tip: 'AI assistant',
    );
    final settingInfo = _genPluginSettings();
    final editorPluginRegisterInfo = EditorPluginRegisterInformation(
      pluginName: _pluginName,
      toolbarInformation: toolbarInfo,
      settingsInformation: settingInfo,
      onBlockChanged: _blockChangedHandler,
    );
    proxy.registerEditorPlugin(editorPluginRegisterInfo);
  }
  void _registerGlobalPlugin(PluginProxy proxy) {
    final globalToolbarInfo = GlobalToolbarInformation(
      buttonIcon: Icons.record_voice_over_outlined,
      buildWidget: _realtimeAiAction,
      tip: 'ChatUI',
      isAvailable: () => _proxy.getSettingValue(settingKeyPluginOpenAiApiKey) != null && _proxy.getSettingValue(settingKeyPluginOpenAiApiKey)!.isNotEmpty,
    );
    final globalPluginRegisterInfo = GlobalPluginRegisterInformation(
      pluginName: _pluginName,
      toolbarInformation: globalToolbarInfo,
      settingsInformation: [],
    );
    proxy.registerGlobalPlugin(globalPluginRegisterInfo);
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
        settingKey: settingKeyPluginQwenApiKey,
        settingName: settingNamePluginQwenApiKey,
        settingComment: settingCommentPluginQwenApiKey,
      ),
      PluginSetting(
        settingKey: settingKeyPluginDeepSeekApiKey,
        settingName: settingNamePluginDeepSeekApiKey,
        settingComment: settingCommentPluginDeepSeekApiKey,
      ),
      PluginSetting(
        settingKey: settingKeyPluginDefaultAiService,
        settingName: settingNamePluginDefaultAiService,
        settingComment: settingCommentPluginDefaultAiService,
        settingDefaultValue: settingDefaultPluginDefaultAiService,
      ),
      PluginSetting(
        settingKey: settingKeyUseAiForExtra,
        settingName: settingNameUseAiForExtra,
        settingComment: settingCommentUseAiForExtra,
        settingDefaultValue: settingDefaultUseAiForExtra,
        type: PluginSettingType.bool,
      ),
    ];
    return result;
  }
  void _aiAction() {
    var _executor = _buildAiExecutor();
    if(_executor != null) {
      var dialog = AIDialog(
        proxy: _proxy,
        executor: _executor,
      );
      _proxy.showDialog(_dialogTitle, dialog);
    } else {
      MyLogger.info('AI parameter is not ready yet!');
      _proxy.showToast('Please set api key first');
    }
  }
  Widget? _realtimeAiAction({required void Function() onClose}) {
    var _apiKey = _proxy.getSettingValue(PluginAI.settingKeyPluginOpenAiApiKey);
    if(_apiKey == null || _apiKey.isEmpty) {
      _proxy.showToast('Please set the OpenAI API key first');
      return null;
    }
    return RealtimeChatDialog(
      closeCallback: onClose,
      apiKey: _apiKey,
      proxy: _proxy,
    );
  }

  OpenAiExecutor? _buildAiExecutor() {
    var service = _proxy.getSettingValue(settingKeyPluginDefaultAiService);
    if(service == null || service.isEmpty) return null;
    switch(service) {
      case 'kimi.ai':
        return _buildKimiExecutor();
      case 'chatgpt':
        return _buildChatGptExecutor();
      case 'qwen':
        return _buildQwenExecutor();
      case 'deepseek':
        return _buildDeepSeekExecutor();
      default:
        return _buildChatGptExecutor();
    }
  }
  OpenAiExecutor? _buildKimiExecutor() {
    return _buildOpenAiExecutor(settingKeyPluginKimiApiKey, LLMProviders.kimi);
  }
  OpenAiExecutor? _buildChatGptExecutor() {
    return _buildOpenAiExecutor(settingKeyPluginOpenAiApiKey, LLMProviders.openai);
  }
  OpenAiExecutor? _buildQwenExecutor() {
    return _buildOpenAiExecutor(settingKeyPluginQwenApiKey, LLMProviders.qwen);
  }
  OpenAiExecutor? _buildDeepSeekExecutor() {
    return _buildOpenAiExecutor(settingKeyPluginDeepSeekApiKey, LLMProviders.deepseek);
  }
  OpenAiExecutor? _buildOpenAiExecutor(String settingKey, LLMModel llm) {
    var _apiKey = _proxy.getSettingValue(settingKey);
    if(_apiKey == null || _apiKey.isEmpty) {
      return null;
    }
    return OpenAiExecutor(apiKey: _apiKey, llm: llm);
  }

  List<String> noneExpression = ['None', 'None.', 'none', 'none.'];
  void _blockChangedHandler(BlockChangedEventData data) {
    if(_proxy.getSettingValue(settingKeyUseAiForExtra)?.toLowerCase() != 'true') {
      MyLogger.debug('AI plugin for extra is not enabled');
      return;
    }
    MyLogger.info('AI plugin receive block changed: id=${data.blockId}, content=${data.content}');
    var executor = _buildAiExecutor();
    const userPrompt = 'Here is the user\'s note';
    const systemPrompt = SystemPrompts.systemPromptForBlockSuggestion;
    executor?.execute(systemPrompt, userPrompt, data.content).then((value) {
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
