import 'package:dart_openai/dart_openai.dart';
import 'package:my_log/my_log.dart';
import 'llm_providers.dart';

class OpenAiExecutor {
  String apiKey;
  LLMModel llm;

  OpenAiExecutor({
    required this.apiKey,
    required this.llm,
  }) {
    if(llm.baseUrl != null) {
      OpenAI.baseUrl = llm.baseUrl!;
    }
    OpenAI.apiKey = apiKey;
  }

  Future<String> execute(String systemPrompt, String userPrompt, String userText) async {
    OpenAI.showLogs = true;
    var messages = <OpenAIChatCompletionChoiceMessageModel>[
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: [OpenAIChatCompletionChoiceMessageContentItemModel(text: systemPrompt, type: 'text')],
      ),
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [OpenAIChatCompletionChoiceMessageContentItemModel(text: userPrompt, type: 'text')],
      ),
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [OpenAIChatCompletionChoiceMessageContentItemModel(text: userText, type: 'text')],
      ),
    ];
    OpenAIChatCompletionModel completion = await OpenAI.instance.chat.create(
      model: llm.model,
      messages: messages,
      temperature: 0.3,
    );
    var text = completion.choices.first.message.content!.first.text!;
    MyLogger.info('${llm.model} response: $text');
    return text;
  }
}