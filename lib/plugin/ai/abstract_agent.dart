
abstract class AiExecutor {
  Future<String> execute({required String userPrompt, String? systemPrompt});
  String getApiKey();
}