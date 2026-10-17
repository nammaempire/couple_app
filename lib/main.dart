import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/app.dart';
import 'package:couple_app/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    ProviderScope(
      // Streams report their own errors and screens show them; Riverpod's
      // automatic retry would hide them and re-open failing listeners.
      retry: (retryCount, error) => null,
      child: const CoupleApp(),
    ),
  );
}
