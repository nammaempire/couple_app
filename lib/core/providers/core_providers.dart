import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/services/storage_service.dart';

/// Uploads to Firebase Storage (profile and couple photos).
final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(),
);
