import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
  String content = '';
  @override
  void initState() {
    super.initState();
    String selectedContent = widget.proxy.getSelectedContent();
    if(selectedContent.isNotEmpty) {
      widget.executor.execute('对下面内容进行简要总结：$selectedContent').then((value) => _update(value));
    }
  }
  void _update(String value) {
    setState(() {
      content = value;
    });
  }
  @override
  Widget build(BuildContext context) {
    String text = switch(content) {
      ''=> 'Please wait...',
      String() => content,
    };
    var result = Column(
      children: [
        Expanded(
          child: Text(text),
        ),
        const Row(
          children: [
            CupertinoButton(
              child: Text('Summary'),
              onPressed: null,
            ),
            Spacer(),
            CupertinoButton(
              child: Text('Copy result'),
              onPressed: null,
            ),
          ],
        )
      ],
    );
    return result;
  }
}