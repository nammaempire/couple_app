import 'package:url_launcher/url_launcher.dart';

import 'package:couple_app/features/plans/models/place.dart';

/// Opens [place] in the maps app (or browser). Returns false if nothing
/// could open it.
Future<bool> launchPlaceInMaps(Place place) async {
  try {
    return await launchUrl(
      Uri.parse(place.openInMapsUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
