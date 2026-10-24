import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/backend_config.dart';

/// Connects the app to the Us server. Call once after Firebase.initializeApp().
///
/// Sign-in stays on Firebase Auth (phone, email, Google): every request
/// carries the user's Firebase ID token, which the server verifies.
void initBackend({String? baseUrl, FirebaseAuth? auth}) {
  final firebaseAuth = auth ?? FirebaseAuth.instance;
  final api = ApiClient(
    baseUrl: (baseUrl ?? BackendConfig.apiUrl).replaceAll(RegExp(r'/+$'), ''),
    token: ({bool forceRefresh = false}) async =>
        firebaseAuth.currentUser?.getIdToken(forceRefresh),
  );
  final realtime = Realtime(api);
  Db.instance = Db(RemoteBackend(api, realtime: realtime));
  Files.instance = Files(api);
  Functions.instance = Functions(api);
  // New token (refresh, sign-in, sign-out) → tell the live connection.
  firebaseAuth.idTokenChanges().listen((_) => unawaited(realtime.reauthenticate()));
}
