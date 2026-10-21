import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/screens/qr_scan_screen.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_choose_step.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_confirm_step.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_create_step.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_join_step.dart';

enum _Mode { choose, create, join, confirm }

/// Onboarding step 2: create a couple space, or join one with an invite.
///
/// All sub-steps live in this one widget rather than as pushed routes, so
/// when pairing succeeds and [AuthGate] swaps screens there is no stale route
/// left on the navigator.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key, required this.uid, this.me, this.notice});

  final String uid;

  /// This user's profile, used to label the invite with their name.
  final AppUser? me;

  /// Optional message shown at the top, e.g. when a previous space is gone.
  final String? notice;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  late final AuthService _auth;
  late final CoupleService _couples;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authServiceProvider);
    _couples = ref.read(coupleServiceProvider);
    _storage = ref.read(storageServiceProvider);
  }

  _Mode _mode = _Mode.choose;

  // Create
  final _coupleName = TextEditingController();
  DateTime? _startDate;
  File? _couplePhoto;

  // Join
  final _code = TextEditingController();
  Invite? _invite;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _coupleName.dispose();
    _code.dispose();
    super.dispose();
  }

  void _go(_Mode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PairingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
    final couple = await _couples.createCouple(
      widget.uid,
      inviterName: widget.me?.displayName ?? 'Your partner',
      inviterPhotoUrl: widget.me?.photoUrl,
      coupleName: _coupleName.text,
      startDate: _startDate,
    );

    // AuthGate moves to the invite screen as soon as `coupleId` lands, so
    // the photo finishes uploading in the background.
    final photo = _couplePhoto;
    if (photo != null) {
      _storage
          .uploadCouplePhoto(coupleId: couple.id, file: photo)
          .then(
            (url) =>
                _couples.setCouplePhoto(coupleId: couple.id, photoUrl: url),
          )
          .catchError((_) {});
    }
  }, 'Could not create your space. Try again.');

  Future<void> _findInvite() async {
    final code = InviteCode.extract(_code.text);
    if (code == null) {
      setState(() => _error = 'Enter the 6-character code your partner sent.');
      return;
    }
    await _run(() async {
      final invite = await _couples.lookupInvite(uid: widget.uid, code: code);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _mode = _Mode.confirm;
      });
    }, 'Could not check that code. Check your connection and try again.');
  }

  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (code == null || !mounted) return;
    _code.text = code;
    await _findInvite();
  }

  Future<void> _accept() => _run(
    () => _couples.acceptInvite(uid: widget.uid, invite: _invite!),
    'Could not connect. Try again.',
  );

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      helpText: 'When did you two start?',
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _mode != _Mode.choose;

    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) {
          _go(_mode == _Mode.confirm ? _Mode.join : _Mode.choose);
        }
      },
      child: RomanceBackdrop(
        preset: GradientPreset.festive,
        strength: .55,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: romanceAppBar(
            leading: canGoBack
                ? BackButton(
                    onPressed: _busy
                        ? null
                        : () => _go(
                            _mode == _Mode.confirm ? _Mode.join : _Mode.choose,
                          ),
                  )
                : null,
            title: Text(switch (_mode) {
              _Mode.choose => 'Connect',
              _Mode.create => 'Create your space',
              _Mode.join => 'Join your partner',
              _Mode.confirm => 'Accept invite',
            }),
            actions: [
              if (!canGoBack)
                TextButton(
                  onPressed: _busy ? null : _auth.signOut,
                  child: const Text('Sign out'),
                ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(_mode),
                      child: switch (_mode) {
                        _Mode.choose => PairingChooseStep(
                          notice: widget.notice,
                          onCreate: () => _go(_Mode.create),
                          onJoin: () => _go(_Mode.join),
                        ),
                        _Mode.create => PairingCreateStep(
                          couplePhoto: _couplePhoto,
                          onPhotoPicked: (file) =>
                              setState(() => _couplePhoto = file),
                          coupleName: _coupleName,
                          startDate: _startDate,
                          onPickStartDate: _pickStartDate,
                          busy: _busy,
                          error: _error,
                          onCreate: _create,
                        ),
                        _Mode.join => PairingJoinStep(
                          code: _code,
                          busy: _busy,
                          error: _error,
                          onSubmit: _findInvite,
                          onScan: _scan,
                        ),
                        _Mode.confirm => PairingConfirmStep(
                          invite: _invite!,
                          busy: _busy,
                          error: _error,
                          onAccept: _accept,
                          onUseAnotherCode: () => _go(_Mode.join),
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
