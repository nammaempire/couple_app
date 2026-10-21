import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/features/auth/models/phone_number.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// A mobile-number field with the country's flag and code in front; tapping
/// the code opens [showCountryPicker].
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.country,
    required this.controller,
    required this.onCountryChanged,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.label = 'Mobile number',
    this.onSubmitted,
    this.onChanged,
  });

  final PhoneCountry country;
  final TextEditingController controller;
  final ValueChanged<PhoneCountry> onCountryChanged;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final String label;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      key: const Key('phone-number-field'),
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        LengthLimitingTextInputFormatter(country.maxDigits + 4),
      ],
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: country.example,
        errorText: errorText,
        errorMaxLines: 3,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 6, right: 4),
          child: TextButton(
            key: const Key('phone-country-button'),
            onPressed: enabled
                ? () async {
                    final picked = await showCountryPicker(
                      context,
                      selected: country,
                    );
                    if (picked != null) onCountryChanged(picked);
                  }
                : null,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(country.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Text(
                  country.plusCode,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.arrow_drop_down_rounded),
              ],
            ),
          ),
        ),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }
}

/// A searchable list of countries; resolves to the one picked, or null.
Future<PhoneCountry?> showCountryPicker(
  BuildContext context, {
  required PhoneCountry selected,
}) {
  return showModalBottomSheet<PhoneCountry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CountryPicker(selected: selected),
  );
}

class _CountryPicker extends StatefulWidget {
  const _CountryPicker({required this.selected});

  final PhoneCountry selected;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase().replaceAll('+', '');
    final countries = [
      for (final c in PhoneCountry.all)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.dialCode.startsWith(q) ||
            c.iso.toLowerCase() == q)
          c,
    ];

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          const SheetHeader(
            icon: Icons.public_rounded,
            title: 'Your country',
            subtitle: 'Where your mobile number is from.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in countries)
                  ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(c.name),
                    trailing: Text(
                      c.plusCode,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    selected: c.iso == widget.selected.iso,
                    onTap: () => Navigator.of(context).pop(c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
