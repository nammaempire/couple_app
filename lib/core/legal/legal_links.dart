import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:couple_app/core/backend/backend_config.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';

/// The public pages on the Us server: the privacy policy, the terms of use
/// and how to delete an account. Google Play links to them too.
enum LegalPage {
  privacy('/privacy', 'Privacy policy'),
  terms('/terms', 'Terms of use'),
  deleteAccount('/delete-account', 'Deleting your account');

  const LegalPage(this.path, this.label);

  final String path;
  final String label;

  Uri get url => Uri.parse('${BackendConfig.apiUrl}$path');
}

/// Opens [page] in the browser. Coming back doesn't trigger the app lock.
Future<void> openLegalPage(
  BuildContext context,
  WidgetRef ref,
  LegalPage page,
) async {
  bool ok;
  try {
    ok = await ref
        .read(appLockControllerProvider.notifier)
        .suspendWhile(
          launchUrl(page.url, mode: LaunchMode.externalApplication),
        );
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    context.showSnackMessage('Could not open ${page.label.toLowerCase()}.');
  }
}

/// "By continuing, you confirm you're 18 or older and agree to our Terms of
/// use and Privacy policy", with both links tappable.
class LegalAgreementText extends ConsumerStatefulWidget {
  const LegalAgreementText({super.key, this.color, this.textAlign});

  final Color? color;
  final TextAlign? textAlign;

  @override
  ConsumerState<LegalAgreementText> createState() => _LegalAgreementTextState();
}

class _LegalAgreementTextState extends ConsumerState<LegalAgreementText> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => openLegalPage(context, ref, LegalPage.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => openLegalPage(context, ref, LegalPage.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: widget.color ?? theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    final link = base?.copyWith(
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      key: const Key('legal-agreement'),
      TextSpan(
        style: base,
        children: [
          const TextSpan(
            text:
                'By continuing, you confirm you\'re 18 or older and agree to '
                'our ',
          ),
          TextSpan(text: 'Terms of use', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: widget.textAlign ?? TextAlign.center,
    );
  }
}
