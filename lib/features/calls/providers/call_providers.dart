import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/calls/data/call_service.dart';

final callServiceProvider = Provider<CallService>((ref) => CallService());
