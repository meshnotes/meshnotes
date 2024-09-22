import 'package:dart_openai/dart_openai.dart';
import 'package:mesh_note/plugin/ai/abstract_agent.dart';

class OpenAiExecutor implements AiExecutor {
  String apiKey;

  OpenAiExecutor({
    required this.apiKey,
  }) {
    OpenAI.apiKey = apiKey;
  }

  @override
  Future<String> execute({required String userPrompt, String? systemPrompt}) async {
    OpenAI.apiKey = apiKey;
    OpenAI.showLogs = true;
    var messages = <OpenAIChatCompletionChoiceMessageModel>[
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
    OpenAIChatCompletionModel completion = await OpenAI.instance.chat.create(
      model: 'gpt-4-turbo',
      messages: messages,
      temperature: 0.3,
    );
    return completion.choices.first.message.content;
  }
}