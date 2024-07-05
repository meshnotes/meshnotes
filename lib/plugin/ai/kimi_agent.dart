import 'package:dart_openai/dart_openai.dart';
import 'package:mesh_note/plugin/ai/abstract_agent.dart';
import 'package:my_log/my_log.dart';

class KimiExecutor implements AiExecutor {
  String apiKey;
  // OpenAICompletionModel? _openAI;

  KimiExecutor({
    required this.apiKey,
  }) {
    OpenAI.baseUrl = 'https://api.moonshot.cn';
    OpenAI.apiKey = apiKey;
    // _initOpenAI(apiKey).then((value) => _openAI = value);
  }

  @override
  Future<String> execute({required String userPrompt, String? systemPrompt}) async {
    OpenAI.baseUrl = 'https://api.moonshot.cn';
    OpenAI.apiKey = apiKey;
    OpenAI.showLogs = true;
    var messages = <OpenAIChatCompletionChoiceMessageModel>[
      const OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: 'Answer question directly, no more than 300 words, better in 50 words, and in the language of original text',//'请直接回答问题，尽量控制字数在100以内，不要超过300',
      ),
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: userPrompt,
      ),
    ];
    if(systemPrompt != null) {
      messages.insert(0, OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: systemPrompt,
      ));
    }
    MyLogger.debug('kimi execute: messages=$messages');
    OpenAIChatCompletionModel completion = await OpenAI.instance.chat.create(
      model: 'moonshot-v1-8k',
      messages: messages,
      temperature: 0.3,
    );
    return completion.choices.first.message.content;
  }
}