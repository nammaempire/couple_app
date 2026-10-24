// The app's backend: documents (Db), files (Files) and server functions
// (Functions) on the Us server, with Firebase Auth for sign-in.
//
// Feature code imports this one file.

export 'package:couple_app/core/backend/db.dart';
export 'package:couple_app/core/backend/files.dart';
export 'package:couple_app/core/backend/functions.dart';
export 'package:couple_app/core/backend/remote.dart' show ApiClient, RemoteBackend, Realtime, TokenProvider;
export 'package:couple_app/core/backend/values.dart';
