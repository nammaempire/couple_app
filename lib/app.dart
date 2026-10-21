import 'package:flutter/material.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/app_lock/widgets/app_lock_gate.dart';
import 'package:couple_app/features/auth/screens/auth_gate.dart';

/// The app: theme, the onboarding-or-app gate, and the app lock over every
/// screen.
class CoupleApp extends StatelessWidget {
  const CoupleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLockGate(
      child: MaterialApp(
        title: 'Us',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        // Above the navigator, so the lock covers every route.
        builder: (context, child) => AppLockOverlay(child: child!),
        home: const AuthGate(),
      ),
    );
  }
}
