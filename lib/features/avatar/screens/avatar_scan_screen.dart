import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/features/avatar/data/selfie_avatar.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// Makes an avatar from a live selfie: a round front-camera preview counts
/// down 3-2-1 and takes the picture by itself, then the face is read on the
/// phone (see [SelfieAvatarScanner]). Only the live camera is used; photos
/// can't be picked from the gallery, and the selfie is deleted right after
/// the scan.
///
/// Pops with a [SelfieAvatar], or nothing if the person backs out.
class AvatarScanScreen extends StatefulWidget {
  const AvatarScanScreen({super.key, required this.base});

  /// The avatar the scan starts from (parts a photo can't tell are kept).
  final AvatarConfig base;

  /// Opens the scan and returns its result.
  static Future<SelfieAvatar?> open(
    BuildContext context, {
    required AvatarConfig base,
  }) => Navigator.of(context).push<SelfieAvatar>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarScanScreen(base: base),
    ),
  );

  @override
  State<AvatarScanScreen> createState() => _AvatarScanScreenState();
}

enum _Phase { starting, counting, scanning, failed }

class _AvatarScanScreenState extends State<AvatarScanScreen>
    with WidgetsBindingObserver {
  static const _steps = [
    'Finding your face',
    'Reading skin & hair colour',
    'Checking beard & outfit',
    'Drawing your avatar',
  ];

  CameraController? _camera;
  _Phase _phase = _Phase.starting;
  int _count = 3;
  int _step = 0;
  String? _error;
  Timer? _countdown;
  Timer? _stepTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdown?.cancel();
    _stepTimer?.cancel();
    unawaited(_camera?.dispose());
    super.dispose();
  }

  /// The camera is released in the background and reopened on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (camera == null || _phase == _Phase.scanning) return;
      _countdown?.cancel();
      _camera = null;
      unawaited(camera.dispose());
      if (_phase == _Phase.counting && mounted) {
        setState(() => _phase = _Phase.starting);
      }
    } else if (state == AppLifecycleState.resumed &&
        camera == null &&
        _phase == _Phase.starting) {
      unawaited(_start());
    }
  }

  bool _opening = false;

  Future<void> _start() async {
    // The permission prompt pauses and resumes the app while opening.
    if (_opening) return;
    _opening = true;
    setState(() {
      _phase = _Phase.starting;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return _fail('No camera found on this phone.');
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      _startCountdown();
    } on CameraException catch (e) {
      _fail(
        e.code.contains('AccessDenied') || e.code.contains('Restricted')
            ? 'Allow camera access to scan your face. You can turn it on '
                  'in the app\'s settings.'
            : 'The camera couldn\'t start. Try again.',
      );
    } catch (_) {
      _fail('The camera couldn\'t start. Try again.');
    } finally {
      _opening = false;
    }
  }

  void _startCountdown() {
    setState(() {
      _phase = _Phase.counting;
      _count = 3;
    });
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_count > 1) {
        HapticFeedback.selectionClick();
        setState(() => _count--);
      } else {
        t.cancel();
        unawaited(_capture());
      }
    });
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    setState(() {
      _phase = _Phase.scanning;
      _step = 0;
    });
    unawaited(HapticFeedback.mediumImpact());
    _stepTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted && _step < _steps.length - 1) setState(() => _step++);
    });
    try {
      final shot = await camera.takePicture();
      final result = await SelfieAvatarScanner.scan(
        shot.path,
        base: widget.base,
      );
      _stepTimer?.cancel();
      if (!mounted) return;
      if (result == null) {
        return _fail(
          'Couldn\'t see your face. Face the camera in good light and '
          'try again.',
        );
      }
      Navigator.of(context).pop(result);
    } catch (_) {
      _stepTimer?.cancel();
      _fail('Something went wrong reading the photo. Try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  void _retry() {
    if (_camera?.value.isInitialized ?? false) {
      _startCountdown();
    } else {
      unawaited(_start());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final circle = (size.width * .78).clamp(200.0, 340.0);
    final camera = _camera;

    final String title;
    final String subtitle;
    switch (_phase) {
      case _Phase.starting:
        title = 'Opening the camera…';
        subtitle = 'Hold the phone at eye level';
      case _Phase.counting:
        title = 'Look at the camera';
        subtitle = 'Taking your selfie in $_count…';
      case _Phase.scanning:
        title = _steps[_step];
        subtitle = 'This stays on your phone';
      case _Phase.failed:
        title = 'Let\'s try that again';
        subtitle = _error ?? '';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan my face')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              SizedBox.square(
                dimension: circle,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Container(
                        width: circle,
                        height: circle,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child:
                            camera != null &&
                                camera.value.isInitialized &&
                                _phase != _Phase.failed
                            ? _CoverPreview(camera: camera)
                            : Icon(
                                Icons.face_retouching_natural,
                                size: circle * .35,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                    // The guide ring.
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 4,
                          ),
                        ),
                      ),
                    ),
                    if (_phase == _Phase.counting)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, a) =>
                            ScaleTransition(scale: a, child: child),
                        child: Text(
                          '$_count',
                          key: ValueKey(_count),
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            shadows: const [
                              Shadow(blurRadius: 12, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
                    if (_phase == _Phase.scanning)
                      Container(
                        width: circle,
                        height: circle,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x66000000),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_phase == _Phase.failed) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
              const Spacer(),
              Text(
                '🔒 Live camera only — photo uploads aren\'t allowed.\n'
                'Your selfie is deleted right after the scan.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// The camera preview filling a square (cropped, not stretched).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    // previewSize is landscape (width > height) on phones.
    final preview = camera.value.previewSize;
    final w = preview == null ? 3.0 : preview.height;
    final h = preview == null ? 4.0 : preview.width;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: w, height: h, child: CameraPreview(camera)),
    );
  }
}
