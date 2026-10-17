import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/play/know_me/know_me_service.dart';

final knowMeServiceProvider = Provider<KnowMeService>((ref) => KnowMeService());
