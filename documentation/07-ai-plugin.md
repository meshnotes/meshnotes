# Mesh Notes - AI Plugin System

## Overview

Mesh Notes provides an extensible plugin system, currently focused on AI features. The AI plugin supports:

- **Text assistant**: run AI actions on selected text (continue, rewrite, translate, etc.)
- **Real-time voice chat**: AI voice interaction via WebRTC
- **Auto suggestions**: listen to block changes and provide AI tips

## Plugin Architecture

### PluginManager

**Location**: [lib/plugin/plugin_manager.dart](../lib/plugin/plugin_manager.dart)

```dart
class PluginManager {
  // Editor plugins (toolbar buttons)
  Map<PluginProxy, EditorPluginRegisterInformation> _editorPluginInstances = {};

  // Global plugins (floating buttons)
  Map<PluginProxy, GlobalPluginRegisterInformation> _globalPluginInstances = {};

  // Register all plugins
  void registerPlugins() {
    final plugins = [
      PluginAI(),  // AI plugin
      // Add more plugins in the future
    ];

    for (var plugin in plugins) {
      final proxy = PluginProxy(this);
      plugin.initPlugin(proxy);
      plugin.start();
    }
  }

  // Toolbar buttons
  List<Widget> getToolbarButtons() {
    return _editorPluginInstances.values
        .map((info) => info.toolbarButton)
        .toList();
  }

  // Floating buttons
  List<Widget> getGlobalButtons() {
    return _globalPluginInstances.values
        .map((info) => info.floatingButton)
        .toList();
  }
}
```

### PluginInstance

```dart
abstract class PluginInstance {
  // Initialize plugin
  void initPlugin(PluginProxy proxy);

  // Start plugin
  void start();

  // Stop plugin
  void stop();
}
```

### PluginProxy

Provides APIs for plugins to access core features:

```dart
class PluginProxy {
  final PluginManager _manager;

  PluginProxy(this._manager);

  // Register editor plugin
  void registerEditorPlugin(EditorPluginRegisterInformation info) {
    _manager._editorPluginInstances[this] = info;
  }

  // Register global plugin
  void registerGlobalPlugin(GlobalPluginRegisterInformation info) {
    _manager._globalPluginInstances[this] = info;
  }

  // Get selected text or focused block content
  String getSelectedOrFocusedContent() {
    final selection = controller.selection;
    if (selection.hasSelection) {
      return selection.getSelectedText();
    } else {
      final blockId = controller.document.editingBlockId;
      if (blockId != null) {
        final block = controller.document.getBlock(blockId);
        return block.getPlainText();
      }
    }
    return '';
  }

  // Current editing block ID
  String? getEditingBlockId() {
    return controller.document.editingBlockId;
  }

  // Show dialog
  void showDialog(String title, Widget child) {
    controller.floatingView.showPluginDialog(title, child);
  }

  // Close dialog
  void closeDialog() {
    controller.floatingView.closePluginDialog();
  }

  // Add extra content to block (e.g., AI suggestion)
  void addExtra(String blockId, String content) {
    final block = controller.document.getBlock(blockId);
    block.addExtra(ExtraInfo(
      source: 'plugin:ai',
      content: content,
      metadata: {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    ));
  }

  // Append text to the next block
  void appendTextToNextBlock(String blockId, String text) {
    final block = controller.document.getBlock(blockId);
    if (block.next != null) {
      final currentText = block.next!.getPlainText();
      block.next!.deleteText(0, currentText.length);
      block.next!.insertText(0, currentText + text);
    } else {
      // Create new block
      final newBlock = controller.document.addNewParagraph(
        afterId: blockId,
        type: _BlockType.text,
      );
      newBlock.insertText(0, text);
    }
  }

  // Get user notes
  UserNotes? getUserNotes() {
    return controller.userManager.currentUser?.notes;
  }

  // List all documents
  List<DocumentMeta> getAllDocumentList() {
    return controller.docManager.getFlattenedDocumentList();
  }

  // Get document content
  String getDocumentContent(String documentId) {
    final doc = controller.docManager.getDocument(documentId);
    if (doc == null) return '';

    final buffer = StringBuffer();
    for (var para in doc.paragraphs) {
      buffer.writeln(para.getPlainText());
    }
    return buffer.toString();
  }

  // Register block change listener
  void registerBlockContentChangeEventListener(
    void Function(BlockChangedEventData) handler
  ) {
    CallbackRegistry.registerBlockContentChangeEventListener(handler);
  }
}
```

## AI Plugin Implementation

### PluginAI

**Location**: [lib/plugin/ai/plugin_ai.dart](../lib/plugin/ai/plugin_ai.dart)

```dart
class PluginAI implements PluginInstance {
  late PluginProxy _proxy;
  AiExecutor? _executor;

  @override
  void initPlugin(PluginProxy proxy) {
    _proxy = proxy;

    // 1. Editor plugin (toolbar)
    _proxy.registerEditorPlugin(EditorPluginRegisterInformation(
      name: 'AI Assistant',
      toolbarButton: _buildToolbarButton(),
    ));

    // 2. Global plugin (floating)
    _proxy.registerGlobalPlugin(GlobalPluginRegisterInformation(
      name: 'AI Voice Chat',
      floatingButton: _buildVoiceChatButton(),
    ));

    // 3. Load AI config
    _loadAiConfig();
  }

  @override
  void start() {
    // Listen to block changes
    _proxy.registerBlockContentChangeEventListener(_onBlockChanged);
  }

  @override
  void stop() {
    // Cleanup
  }

  Widget _buildToolbarButton() {
    return IconButton(
      icon: Icon(Icons.auto_awesome),
      tooltip: 'AI Assistant',
      onPressed: _showAiAssistant,
    );
  }

  Widget _buildVoiceChatButton() {
    return FloatingActionButton(
      child: Icon(Icons.mic),
      onPressed: _startVoiceChat,
    );
  }

  void _loadAiConfig() {
    // Load AI config from DB
    final config = _db.getConfig('ai');
    if (config != null) {
      final data = jsonDecode(config);
      final provider = data['provider'];
      final apiKey = data['apiKey'];
      final model = data['model'];

      _executor = AiExecutor(
        provider: LLMProviders.getProvider(provider),
        apiKey: apiKey,
        model: model,
      );
    }
  }
}
```

### AI Text Assistant

```dart
void _showAiAssistant() {
  // 1. Get selected/focused content
  final content = _proxy.getSelectedOrFocusedContent();
  if (content.isEmpty) {
    CallbackRegistry.showToast('Please select text or focus a block first');
    return;
  }

  // 2. Show AI dialog
  _proxy.showDialog('AI Assistant', AiAssistantDialog(
    content: content,
    onAction: (action) => _handleAiAction(action, content),
  ));
}

Future<void> _handleAiAction(String action, String content) async {
  if (_executor == null) {
    CallbackRegistry.showToast('Configure AI first');
    return;
  }

  String systemPrompt;
  String userPrompt;

  switch (action) {
    case 'continue':
      systemPrompt = 'You are a writing assistant that continues text.';
      userPrompt = 'Continue the following content:';
      break;

    case 'improve':
      systemPrompt = 'You help improve writing.';
      userPrompt = 'Improve the following text for clarity and flow:';
      break;

    case 'translate':
      systemPrompt = 'You are a translation assistant.';
      userPrompt = 'Translate the following content to English:';
      break;

    case 'summarize':
      systemPrompt = 'You summarize text.';
      userPrompt = 'Summarize the following content:';
      break;

    default:
      return;
  }

  try {
    // 3. Call AI
    final result = await _executor!.execute(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      content: content,
    );

    // 4. Append to next block
    final blockId = _proxy.getEditingBlockId();
    if (blockId != null) {
      _proxy.appendTextToNextBlock(blockId, result);
    }

    // 5. Close dialog
    _proxy.closeDialog();

  } catch (e) {
    CallbackRegistry.showToast('AI call failed: $e');
  }
}
```

### AI Auto Suggestions

```dart
void _onBlockChanged(BlockChangedEventData data) {
  // 1. Minimum length
  if (data.content.length < 50) {
    return;
  }

  // 2. Debounce
  _debounceTimer?.cancel();
  _debounceTimer = Timer(Duration(seconds: 2), () {
    _generateSuggestion(data.blockId, data.content);
  });
}

Future<void> _generateSuggestion(String blockId, String content) async {
  if (_executor == null) return;

  try {
    // 3. Call AI
    final suggestion = await _executor!.execute(
      systemPrompt: 'You are a writing assistant providing short suggestions.',
      userPrompt: 'Give a short suggestion or addition (<=50 chars) for this note:',
      content: content,
    );

    // 4. Attach as extra
    _proxy.addExtra(blockId, suggestion);

  } catch (e) {
    MyLogger.warn('Failed to generate suggestion: $e');
  }
}
```

### AI Dialog UI

```dart
class AiAssistantDialog extends StatelessWidget {
  final String content;
  final Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected content:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              content.length > 200 ? content.substring(0, 200) + '...' : content,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: 16),
          Text('Choose an action:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          _buildActionButton('Continue', 'continue', Icons.edit),
          _buildActionButton('Improve', 'improve', Icons.auto_fix_high),
          _buildActionButton('Translate', 'translate', Icons.translate),
          _buildActionButton('Summarize', 'summarize', Icons.summarize),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, String action, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => onAction(action),
    );
  }
}
```

## LLM Integration

### AiExecutor

**Location**: [lib/plugin/ai/ai_executor.dart](../lib/plugin/ai/ai_executor.dart)

```dart
class AiExecutor {
  final LLMModel provider;
  final String apiKey;
  final String model;

  AiExecutor({
    required this.provider,
    required this.apiKey,
    required this.model,
  });

  Future<String> execute({
    required String systemPrompt,
    required String userPrompt,
    required String content,
  }) async {
    final client = HttpClient();

    try {
      // 1. Build request
      final request = await client.postUrl(Uri.parse(provider.endpoint));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $apiKey');

      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '$userPrompt\n\n$content'},
        ],
        'temperature': 0.7,
        'max_tokens': 1000,
      });

      request.write(body);

      // 2. Send
      final response = await request.close();

      // 3. Read
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody);

      // 4. Extract
      if (data['choices'] != null && data['choices'].isNotEmpty) {
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('No response from AI');
      }

    } catch (e) {
      MyLogger.error('AI request failed: $e');
      rethrow;
    } finally {
      client.close();
    }
  }
}
```

### LLM Providers

```dart
class LLMModel {
  final String name;
  final String endpoint;
  final List<String> models;

  LLMModel({
    required this.name,
    required this.endpoint,
    required this.models,
  });
}

class LLMProviders {
  static final kimi = LLMModel(
    name: 'Kimi',
    endpoint: 'https://api.moonshot.cn/v1/chat/completions',
    models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
  );

  static final openai = LLMModel(
    name: 'OpenAI',
    endpoint: 'https://api.openai.com/v1/chat/completions',
    models: ['gpt-3.5-turbo', 'gpt-4', 'gpt-4-turbo'],
  );

  static final qwen = LLMModel(
    name: 'Qwen',
    endpoint: 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation',
    models: ['qwen-turbo', 'qwen-plus', 'qwen-max'],
  );

  static final deepseek = LLMModel(
    name: 'DeepSeek',
    endpoint: 'https://api.deepseek.com/v1/chat/completions',
    models: ['deepseek-chat', 'deepseek-coder'],
  );

  static LLMModel getProvider(String name) {
    switch (name.toLowerCase()) {
      case 'kimi':
        return kimi;
      case 'openai':
        return openai;
      case 'qwen':
        return qwen;
      case 'deepseek':
        return deepseek;
      default:
        throw Exception('Unknown provider: $name');
    }
  }

  static List<LLMModel> getAllProviders() {
    return [kimi, openai, qwen, deepseek];
  }
}
```

## Real-time Voice Chat

### VoiceChatPlugin

**Location**: [lib/plugin/ai/voice_chat.dart](../lib/plugin/ai/voice_chat.dart)

```dart
class VoiceChatPlugin {
  WebRTCClient? _webrtcClient;
  bool _isActive = false;

  void start() {
    if (_isActive) return;

    _isActive = true;

    // Init WebRTC
    _webrtcClient = WebRTCClient(
      apiKey: _getOpenAIApiKey(),
      onTranscript: _onTranscriptReceived,
      onResponse: _onResponseReceived,
    );

    _webrtcClient!.connect();
  }

  void stop() {
    _isActive = false;
    _webrtcClient?.disconnect();
    _webrtcClient = null;
  }

  void _onTranscriptReceived(String transcript) {
    // Show user speech
    MyLogger.info('User: $transcript');
  }

  void _onResponseReceived(String response) {
    // Show AI reply
    MyLogger.info('AI: $response');

    // Optional: save to note
    _saveToNote(response);
  }

  void _saveToNote(String content) {
    final blockId = _proxy.getEditingBlockId();
    if (blockId != null) {
      _proxy.appendTextToNextBlock(blockId, '\n[AI]: $content\n');
    }
  }
}
```

### WebRTC Client

```dart
class WebRTCClient {
  final String apiKey;
  final Function(String) onTranscript;
  final Function(String) onResponse;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;

  WebRTCClient({
    required this.apiKey,
    required this.onTranscript,
    required this.onResponse,
  });

  Future<void> connect() async {
    // 1. Mic permission
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    // 2. PeerConnection
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    // 3. Add audio track
    _localStream!.getAudioTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // 4. Data channel for text
    _dataChannel = await _peerConnection!.createDataChannel('chat', RTCDataChannelInit());
    _dataChannel!.onMessage = (message) {
      _onDataChannelMessage(message.text);
    };

    // 5. Connect to OpenAI Realtime API
    await _connectToRealtimeAPI();
  }

  Future<void> _connectToRealtimeAPI() async {
    // Use OpenAI Realtime API WebRTC endpoint
    // See OpenAI docs for details
  }

  void _onDataChannelMessage(String message) {
    final data = jsonDecode(message);

    if (data['type'] == 'transcript') {
      onTranscript(data['text']);
    } else if (data['type'] == 'response') {
      onResponse(data['text']);
    }
  }

  void disconnect() {
    _dataChannel?.close();
    _peerConnection?.close();
    _localStream?.dispose();
  }
}
```

## AI Settings UI

### AiSettingsPage

```dart
class AiSettingsPage extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Settings')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider
            Text('LLM Provider', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<LLMModel>(
              value: _selectedProvider,
              items: LLMProviders.getAllProviders().map((provider) {
                return DropdownMenuItem(
                  value: provider,
                  child: Text(provider.name),
                );
              }).toList(),
              onChanged: (provider) {
                setState(() {
                  _selectedProvider = provider;
                  _selectedModel = provider!.models.first;
                });
              },
            ),

            SizedBox(height: 16),

            // Model
            Text('Model', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: _selectedModel,
              items: _selectedProvider!.models.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text(model),
                );
              }).toList(),
              onChanged: (model) {
                setState(() => _selectedModel = model);
              },
            ),

            SizedBox(height: 16),

            // API Key
            Text('API Key', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Enter your API key',
                border: OutlineInputBorder(),
              ),
            ),

            SizedBox(height: 24),

            // Save
            ElevatedButton(
              onPressed: _saveConfig,
              child: Text('Save'),
            ),

            SizedBox(height: 16),

            // Test
            ElevatedButton(
              onPressed: _testConnection,
              child: Text('Test Connection'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveConfig() {
    final config = jsonEncode({
      'provider': _selectedProvider!.name,
      'model': _selectedModel,
      'apiKey': _apiKeyController.text,
    });

    _db.saveConfig('ai', config);
    CallbackRegistry.showToast('Configuration saved');
  }

  Future<void> _testConnection() async {
    try {
      final executor = AiExecutor(
        provider: _selectedProvider!,
        apiKey: _apiKeyController.text,
        model: _selectedModel!,
      );

      final result = await executor.execute(
        systemPrompt: 'You are a test helper.',
        userPrompt: 'Reply with "connected"',
        content: '',
      );

      CallbackRegistry.showToast('Test successful: $result');
    } catch (e) {
      CallbackRegistry.showToast('Test failed: $e');
    }
  }
}
```

## Event System

### BlockChangedEvent

**Location**: [lib/mindeditor/controller/callback_registry.dart](../lib/mindeditor/controller/callback_registry.dart)

```dart
class BlockChangedEventData {
  String blockId;
  String content;
  int timestamp;

  BlockChangedEventData({
    required this.blockId,
    required this.content,
    required this.timestamp,
  });
}

class CallbackRegistry {
  static final List<Function(BlockChangedEventData)> _blockChangeListeners = [];

  static void registerBlockContentChangeEventListener(
    Function(BlockChangedEventData) handler
  ) {
    _blockChangeListeners.add(handler);
  }

  static void triggerBlockChangedEvent(BlockChangedEventData data) {
    for (var listener in _blockChangeListeners) {
      try {
        listener(data);
      } catch (e) {
        MyLogger.error('Block change listener error: $e');
      }
    }
  }
}
```

## Building a New Plugin

### Steps

1. **Create the plugin class**:

```dart
class MyPlugin implements PluginInstance {
  late PluginProxy _proxy;

  @override
  void initPlugin(PluginProxy proxy) {
    _proxy = proxy;

    // Register toolbar or global buttons
    _proxy.registerEditorPlugin(EditorPluginRegisterInformation(
      name: 'My Plugin',
      toolbarButton: IconButton(
        icon: Icon(Icons.extension),
        onPressed: _onButtonPressed,
      ),
    ));
  }

  @override
  void start() {
    // Startup logic
  }

  @override
  void stop() {
    // Cleanup
  }

  void _onButtonPressed() {
    final content = _proxy.getSelectedOrFocusedContent();
    // ... your logic
  }
}
```

2. **Register the plugin**:

Add to `PluginManager.registerPlugins()`:

```dart
void registerPlugins() {
  final plugins = [
    PluginAI(),
    MyPlugin(),
  ];

  // ...
}
```

3. **Use PluginProxy APIs**:

```dart
// Read content
String content = _proxy.getSelectedOrFocusedContent();

// Modify document
_proxy.appendTextToNextBlock(blockId, newText);

// Add suggestion
_proxy.addExtra(blockId, suggestion);

// Show dialog
_proxy.showDialog('Title', MyDialogWidget());

// Listen for events
_proxy.registerBlockContentChangeEventListener((data) {
  // Handle block change
});
```

## Known Limitations

1. **API cost**: frequent AI calls may be expensive
2. **Latency**: network round-trips can be slow
3. **Offline**: requires connectivity
4. **Language**: primarily Chinese/English support

## Future Work

1. **Local LLM**: integrate local models (e.g., llama.cpp)
2. **Streaming**: support SSE streaming responses
3. **Context memory**: remember prior conversation
4. **Multimodal**: support image/audio inputs
5. **Custom prompts**: user-defined prompt templates
6. **RAG**: retrieval-augmented generation on the note base
7. **Plugin marketplace**: community plugins
