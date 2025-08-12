import 'persona_config.dart';

class AnamClientOptions {
  final String? apiKey;
  final String? sessionToken;
  final String apiBaseUrl;
  final String apiVersion;
  final bool enableLogging;
  final PersonaConfig? defaultPersonaConfig;
  final bool disableBrains;

  AnamClientOptions({
    this.apiKey,
    this.sessionToken,
    this.apiBaseUrl = 'https://api.anam.ai',
    this.apiVersion = '/v1',
    this.enableLogging = false,
    this.defaultPersonaConfig,
    this.disableBrains = false,
  }) {
    if (apiKey == null && sessionToken == null) {
      throw ArgumentError('Either apiKey or sessionToken must be provided');
    }
  }
}
