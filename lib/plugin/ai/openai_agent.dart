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
    OpenAIChatCompletionModel completion = await OpenAI.instance.chat.create(
      model: 'gpt-4-turbo',
      messages: [
        const OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.system,
          content: 'Answer the question directly, in the original language. make the answer within 300 words, better no more than 100 words',
        ),
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: userPrompt,
        ),
      ],
      temperature: 0.3,
    );
    return completion.choices.first.message.content;
  }
}