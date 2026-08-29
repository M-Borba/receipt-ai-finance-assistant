/// Core abstraction for all AI provider implementations.
/// Swap providers by injecting a different implementation.
abstract interface class AIProvider {
  String get name;

  /// Send a prompt and return the response text.
  Future<String> complete({
    required String prompt,
    String? systemPrompt,
    double temperature = 0.3,
    int maxTokens = 1024,
  });

  /// Stream a response token by token.
  Stream<String> stream({
    required String prompt,
    String? systemPrompt,
    double temperature = 0.3,
  });

  /// Check if this provider is reachable.
  Future<bool> isAvailable();
}
