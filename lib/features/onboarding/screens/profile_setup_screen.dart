import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/photo_picker_avatar.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';

/// Onboarding step 1: name, photo, birthday and an optional nickname.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, required this.uid, this.profile});

  final String uid;

  /// The profile so far, if the document exists yet. Google sign-ins arrive
  /// with a name and photo already filled in.
  final AppUser? profile;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  late final AuthService _auth;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authServiceProvider);
    _storage = ref.read(storageServiceProvider);
  }

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _initialName());
  late final _nickname = TextEditingController(
    text: widget.profile?.nickname ?? '',
  );

  File? _photo;
  late DateTime? _birthday = widget.profile?.birthday;
  bool _busy = false;
  String? _error;

  String _initialName() {
    final fromProfile = widget.profile?.displayName;
    if (fromProfile != null && fromProfile != 'Me') return fromProfile;
    return _auth.currentUser?.displayName ?? '';
  }

  /// Right after sign-up the screen can appear before the profile document
  /// lands, so fill in fields the user has not typed in yet once it does.
  @override
  void didUpdateWidget(covariant ProfileSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profile = widget.profile;
    if (profile == null || oldWidget.profile != null) return;

    if (_name.text.trim().isEmpty && profile.displayName != 'Me') {
      _name.text = profile.displayName;
    }
    if (_nickname.text.isEmpty && profile.nickname != null) {
      _nickname.text = profile.nickname!;
    }
    _birthday ??= profile.birthday;
  }

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Your birthday',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      String? photoUrl;
      if (_photo != null) {
        try {
          photoUrl = await _storage.uploadProfilePhoto(
            uid: widget.uid,
            file: _photo!,
          );
        } catch (_) {
          // A failed photo upload should not block onboarding.
          if (mounted) {
            context.showSnackMessage(
              'Photo could not be uploaded. You can add it later.',
            );
          }
        }
      }

      await _auth.saveProfile(
        displayName: _name.text,
        nickname: _nickname.text,
        birthday: _birthday,
        photoUrl: photoUrl,
      );
      // AuthGate moves on once `profileComplete` lands.
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save your profile. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('About you'),
        actions: [
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
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const OnboardingProgress(step: OnboardingStep.profile),
                    const SizedBox(height: 28),
                    Center(
                      child: PhotoPickerAvatar(
                        file: _photo,
                        imageUrl: widget.profile?.photoUrl,
                        label: 'Add your photo',
                        onPicked: (file) => setState(() => _photo = file),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your partner will see this.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline),
                        counterText: '',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Please enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _nickname,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        labelText: 'Nickname (optional)',
                        prefixIcon: Icon(Icons.tag_faces_outlined),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),

                    _BirthdayField(
                      birthday: _birthday,
                      onTap: _busy ? null : _pickBirthday,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(
                        'Used for birthday reminders. You can skip this.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],

                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _busy ? null : _continue,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BirthdayField extends StatelessWidget {
  const _BirthdayField({required this.birthday, required this.onTap});

  final DateTime? birthday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Birthday',
          prefixIcon: Icon(Icons.cake_outlined),
        ),
        child: Text(
          birthday == null
              ? 'Add your birthday'
              : DateFormat.yMMMMd().format(birthday!),
          style: birthday == null
              ? theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}
