import 'package:dart_openai/dart_openai.dart';

class AIExecutor {
  String apiKey;
  // OpenAICompletionModel? _openAI;

  AIExecutor({
    required this.apiKey,
  }) {
    OpenAI.baseUrl = 'https://api.moonshot.cn';
    OpenAI.apiKey = apiKey;
    // _initOpenAI(apiKey).then((value) => _openAI = value);
  }

  Future<String> execute(String prompt) async {
    OpenAI.baseUrl = 'https://api.moonshot.cn';
    OpenAI.apiKey = apiKey;
    OpenAI.showLogs = true;
    OpenAIChatCompletionModel completion = await OpenAI.instance.chat.create(
      model: 'moonshot-v1-8k',
      messages: [
        const OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.system,
          content: '请直接回答问题',
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