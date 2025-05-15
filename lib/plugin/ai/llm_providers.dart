class LLMProviders {
  static LLMModel kimi = LLMModel(
    baseUrl: 'https://api.moonshot.cn',
    model: 'moonshot-v1-8k',
  );
  static LLMModel openai = LLMModel(
    model: 'gpt-4-turbo',
  );
  static LLMModel qwen = LLMModel(
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode',
    model: 'qwen-plus',
  );
  static LLMModel deepseek = LLMModel(
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
  );
}

class LLMModel {
  final String? baseUrl;
  final String model;
  final double temperature;
  LLMModel({
    this.baseUrl,
    required this.model,
    this.temperature = 0.3,
  });
}
