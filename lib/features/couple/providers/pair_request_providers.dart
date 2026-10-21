import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/pair_request_service.dart';
import 'package:couple_app/features/couple/models/pair_request.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

final pairRequestServiceProvider = Provider<PairRequestService>(
  (ref) => PairRequestService(
    couples: ref.watch(coupleServiceProvider),
    phones: ref.watch(phoneNumberServiceProvider),
  ),
);

/// Pending "wants to pair with you" requests to a user.
final incomingPairRequestsProvider = StreamProvider.autoDispose
    .family<List<PairRequest>, String>(
      (ref, uid) => ref.watch(pairRequestServiceProvider).watchIncoming(uid),
    );

/// Requests a user has sent, newest first.
final outgoingPairRequestsProvider = StreamProvider.autoDispose
    .family<List<PairRequest>, String>(
      (ref, uid) => ref.watch(pairRequestServiceProvider).watchOutgoing(uid),
    );
