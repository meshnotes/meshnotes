import 'package:dart_openai/dart_openai.dart';
import 'package:mesh_note/plugin/ai/abstract_agent.dart';

class OpenAiExecutor implements AiExecutor {
  String apiKey;
  // OpenAICompletionModel? _openAI;

  OpenAiExecutor({
    required this.apiKey,
  }) {
    OpenAI.apiKey = apiKey;
  }

  @override
  Future<String> execute(String prompt) async {
    // OpenAI.baseUrl = 'https://api.moonshot.cn';
    OpenAI.apiKey = apiKey;
    OpenAI.showLogs = true;
    OpenAIChatCompletionModel completion = await OpenAI.instance.chat.create(
      model: 'gpt-4-turbo',
      messages: [
        const OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.system,
          content: '请直接回答问题，尽量控制字数在100以内，不要超过300',
        ),
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: prompt,
        ),
        // OpenAIChatCompletionChoiceMessageModel.fromMap({
        //   "role": "system",
        //   "content": "你是 Kimi，由 Moonshot AI 提供的人工智能助手，你更擅长中文和英文的对话。你会为用户提供安全，有帮助，准确的回答。同时，你会拒绝一切涉及恐怖主义，种族歧视，黄色暴力等问题的回答。Moonshot AI 为专有名词，不可翻译成其他语言。"
        // })
        //
        // {
        //   "role": "user",
        //   "content": "你好，我叫李雷，1+1等于多少？"
        // }
      ],
      temperature: 0.3,
    );
    return completion.choices.first.message.content;
  }
}