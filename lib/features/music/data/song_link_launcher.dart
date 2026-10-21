import 'package:url_launcher/url_launcher.dart';

/// Opens a song link in its own app (Spotify, Apple Music, YouTube…) or the
/// browser. Returns false if nothing could open it.
typedef SongLinkLauncher = Future<bool> Function(String url);

/// The real [SongLinkLauncher], through url_launcher.
Future<bool> launchSongLink(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
