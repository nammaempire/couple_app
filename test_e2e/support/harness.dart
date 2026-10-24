// End-to-end harness: the app's real data layer (Db, Files, Functions on
// RemoteBackend) against a real Us server with the real security rules.
//
// Start the server first (see test_e2e/README in the final report):
//   cd server && DATABASE_URL=postgres://postgres@127.0.0.1:5432/us_e2e \
//     AUTH_TEST_MODE=true NODE_ENV=test S3_BUCKET= RUN_SCHEDULER=false \
//     PUBLIC_URL=http://127.0.0.1:18090 PORT=18090 npx tsx src/index.ts
//
// Environment: E2E_URL (default http://127.0.0.1:18090) and E2E_DATABASE_URL
// (default postgres://postgres@127.0.0.1:5432/us_e2e, used only to seed
// what only the server may write, e.g. book credits and gifts).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:couple_app/core/backend/backend.dart';

final String serverUrl =
    Platform.environment['E2E_URL'] ?? 'http://127.0.0.1:18090';
final String databaseUrl =
    Platform.environment['E2E_DATABASE_URL'] ??
    'postgres://postgres@127.0.0.1:5432/us_e2e';

/// A fresh suffix per run, so reruns on the same database don't collide.
final String runId = List.generate(
  6,
  (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[Random().nextInt(36)],
).join();

/// A Firebase test token: `test:<uid>:<base64url claims>`.
String testToken(String uid, Map<String, Object?> claims) =>
    'test:$uid:${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}';

/// One signed-in phone: its own API client, Db, Files and Functions.
class Phone {
  Phone({
    required this.uid,
    required this.name,
    this.phoneNumber,
    this.email,
  }) {
    final claims = <String, Object?>{
      'phone_number': ?phoneNumber,
      'email': ?email,
      'firebase': {'sign_in_provider': phoneNumber != null ? 'phone' : 'password'},
    };
    final token = testToken(uid, claims);
    api = ApiClient(
      baseUrl: serverUrl,
      token: ({bool forceRefresh = false}) async => token,
    );
    realtime = Realtime(api);
    db = Db(RemoteBackend(api, realtime: realtime));
    files = Files(api);
    functions = Functions(api);
    auth = FakeFirebaseAuth(
      FakeFirebaseUser(uid: uid, displayName: name, email: email),
    );
  }

  final String uid;
  final String name;
  final String? phoneNumber;
  final String? email;

  late final ApiClient api;
  late final Realtime realtime;
  late final Db db;
  late final Files files;
  late final Functions functions;
  late final FakeFirebaseAuth auth;

  Future<void> close() async {
    await realtime.close();
    api.close();
  }
}

/// Signed in as [currentUser]; only what AuthService touches.
class FakeFirebaseAuth implements FirebaseAuth {
  FakeFirebaseAuth(this.currentUser);

  @override
  User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseUser implements User {
  FakeFirebaseUser({required this.uid, this.displayName, this.email});

  @override
  final String uid;
  @override
  String? displayName;
  @override
  final String? email;
  @override
  String? get photoURL => null;

  @override
  Future<void> updateDisplayName(String? displayName) async =>
      this.displayName = displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs SQL against the server's database (seeding only what the server
/// itself writes, such as book credits and gifts).
Future<void> sql(String statement) async {
  final r = await Process.run('psql', [
    databaseUrl,
    '-v',
    'ON_ERROR_STOP=1',
    '-q',
    '-c',
    statement,
  ]);
  if (r.exitCode != 0) {
    throw StateError('psql failed: ${r.stderr}');
  }
}

String sqlString(String s) => "'${s.replaceAll("'", "''")}'";

/// Waits until [stream] emits a value matching [test].
Future<T> firstWhere<T>(
  Stream<T> stream,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 10),
}) => stream.firstWhere(test).timeout(timeout);

/// A temporary file with [bytes], deleted at exit.
Future<File> tempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('us_e2e');
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  return f;
}

/// A tiny valid PNG (1x1).
final List<int> onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Expects [body] to fail with a DbException of [code].
Future<void> expectDenied(Future<Object?> Function() body,
    {String code = 'permission-denied'}) async {
  try {
    await body();
  } on DbException catch (e) {
    if (e.code == code) return;
    throw StateError('Expected $code, got ${e.code}: ${e.message}');
  }
  throw StateError('Expected $code, but it succeeded');
}
