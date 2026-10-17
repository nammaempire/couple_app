/// Agora credentials.
///
/// Get an App ID from https://console.agora.io — create a project, and set
/// its authentication mode to "Testing mode: APP ID" so no token server is
/// needed.
///
/// Two ways to supply it, in order of precedence:
///
///  1. A --dart-define at run time, which keeps the id out of version control:
///       flutter run --dart-define=AGORA_APP_ID=your_app_id_here
///  2. Pasting it into [_hardcodedAppId] below. Simpler when launching
///     several devices from an IDE, but it does get committed — so do not
///     push this file to a public repo with a real id in it.
class AgoraConfig {
  const AgoraConfig._();

  /// Paste your Agora App ID between the quotes.
  static const _hardcodedAppId = 'c5d46ac1e9eb442f8fc4529d73866f97';

  static const _defineAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '',
  );

  /// The --dart-define wins when both are set.
  static String get appId =>
      _defineAppId.isNotEmpty ? _defineAppId : _hardcodedAppId;

  static bool get isConfigured => appId.isNotEmpty;
}
