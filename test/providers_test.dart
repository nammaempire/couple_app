import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

void main() {
  const me = AppUser(uid: 'me', displayName: 'Asha', coupleId: 'c1');
  const partner = AppUser(uid: 'p', displayName: 'Ravi', coupleId: 'c1');

  ProviderContainer containerFor({
    required Couple couple,
    AppUser? partnerProfile,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithBuild((ref, notifier) => me),
        coupleProvider.overrideWith((ref) => Stream.value(couple)),
        partnerProvider.overrideWith(
          (ref) => partnerProfile == null
              ? const Stream.empty()
              : Stream.value(partnerProfile),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Keeps the async providers alive and lets their streams emit.
  Future<void> settle(ProviderContainer container) async {
    container.listen(coupleProvider, (_, _) {});
    container.listen(partnerProvider, (_, _) {});
    await container.read(coupleProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  group('session providers', () {
    test('uid and couple id come from the signed-in profile', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithBuild((ref, notifier) => me),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUidProvider), 'me');
      expect(container.read(currentCoupleIdProvider), 'c1');
    });

    test('couple id is refused before pairing', () {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithBuild(
            (ref, notifier) => const AppUser(uid: 'me', displayName: 'Asha'),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(() => container.read(currentCoupleIdProvider), throwsA(anything));
    });
  });

  group('partnerNameProvider', () {
    const couple = Couple(
      id: 'c1',
      inviteCode: 'ABC234',
      memberIds: ['me', 'p'],
    );

    test('uses my nickname for my partner first', () async {
      final container = containerFor(
        couple: const Couple(
          id: 'c1',
          inviteCode: 'ABC234',
          memberIds: ['me', 'p'],
          nicknames: {'me': ' Sunshine '},
        ),
        partnerProfile: partner,
      );
      await settle(container);

      expect(container.read(partnerNameProvider), 'Sunshine');
    });

    test("falls back to the partner's display name", () async {
      final container = containerFor(couple: couple, partnerProfile: partner);
      await settle(container);

      expect(container.read(partnerNameProvider), 'Ravi');
    });

    test('says "Your partner" before their profile loads', () async {
      final container = containerFor(couple: couple);
      await settle(container);

      expect(container.read(partnerNameProvider), 'Your partner');
    });
  });
}
