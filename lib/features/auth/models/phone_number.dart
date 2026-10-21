/// A country in the mobile-number picker: its dialling code and how many
/// digits a mobile number there has after it.
class PhoneCountry {
  const PhoneCountry({
    required this.iso,
    required this.name,
    required this.dialCode,
    required this.flag,
    required this.minDigits,
    required this.maxDigits,
    this.mobilePrefix,
    this.example,
  });

  /// ISO 3166 code, e.g. `IN`.
  final String iso;
  final String name;

  /// Without the plus, e.g. `91`.
  final String dialCode;
  final String flag;
  final int minDigits;
  final int maxDigits;

  /// Digits a mobile number must start with, when the country has a rule.
  final RegExp? mobilePrefix;

  /// A sample number for the hint text.
  final String? example;

  String get plusCode => '+$dialCode';

  static final india = PhoneCountry(
    iso: 'IN',
    name: 'India',
    dialCode: '91',
    flag: '🇮🇳',
    minDigits: 10,
    maxDigits: 10,
    mobilePrefix: RegExp('^[6-9]'),
    example: '98765 43210',
  );

  /// The picker's list: India first, then countries where many of our
  /// couples live, alphabetically.
  static final all = <PhoneCountry>[
    india,
    const PhoneCountry(
      iso: 'AU',
      name: 'Australia',
      dialCode: '61',
      flag: '🇦🇺',
      minDigits: 9,
      maxDigits: 9,
    ),
    const PhoneCountry(
      iso: 'BD',
      name: 'Bangladesh',
      dialCode: '880',
      flag: '🇧🇩',
      minDigits: 10,
      maxDigits: 10,
    ),
    const PhoneCountry(
      iso: 'CA',
      name: 'Canada',
      dialCode: '1',
      flag: '🇨🇦',
      minDigits: 10,
      maxDigits: 10,
    ),
    const PhoneCountry(
      iso: 'FR',
      name: 'France',
      dialCode: '33',
      flag: '🇫🇷',
      minDigits: 9,
      maxDigits: 9,
    ),
    const PhoneCountry(
      iso: 'DE',
      name: 'Germany',
      dialCode: '49',
      flag: '🇩🇪',
      minDigits: 10,
      maxDigits: 11,
    ),
    const PhoneCountry(
      iso: 'KW',
      name: 'Kuwait',
      dialCode: '965',
      flag: '🇰🇼',
      minDigits: 8,
      maxDigits: 8,
    ),
    const PhoneCountry(
      iso: 'MY',
      name: 'Malaysia',
      dialCode: '60',
      flag: '🇲🇾',
      minDigits: 9,
      maxDigits: 10,
    ),
    const PhoneCountry(
      iso: 'NP',
      name: 'Nepal',
      dialCode: '977',
      flag: '🇳🇵',
      minDigits: 10,
      maxDigits: 10,
    ),
    const PhoneCountry(
      iso: 'NZ',
      name: 'New Zealand',
      dialCode: '64',
      flag: '🇳🇿',
      minDigits: 8,
      maxDigits: 10,
    ),
    const PhoneCountry(
      iso: 'OM',
      name: 'Oman',
      dialCode: '968',
      flag: '🇴🇲',
      minDigits: 8,
      maxDigits: 8,
    ),
    const PhoneCountry(
      iso: 'QA',
      name: 'Qatar',
      dialCode: '974',
      flag: '🇶🇦',
      minDigits: 8,
      maxDigits: 8,
    ),
    const PhoneCountry(
      iso: 'SA',
      name: 'Saudi Arabia',
      dialCode: '966',
      flag: '🇸🇦',
      minDigits: 9,
      maxDigits: 9,
    ),
    const PhoneCountry(
      iso: 'SG',
      name: 'Singapore',
      dialCode: '65',
      flag: '🇸🇬',
      minDigits: 8,
      maxDigits: 8,
    ),
    const PhoneCountry(
      iso: 'LK',
      name: 'Sri Lanka',
      dialCode: '94',
      flag: '🇱🇰',
      minDigits: 9,
      maxDigits: 9,
    ),
    const PhoneCountry(
      iso: 'AE',
      name: 'United Arab Emirates',
      dialCode: '971',
      flag: '🇦🇪',
      minDigits: 9,
      maxDigits: 9,
    ),
    const PhoneCountry(
      iso: 'GB',
      name: 'United Kingdom',
      dialCode: '44',
      flag: '🇬🇧',
      minDigits: 10,
      maxDigits: 10,
    ),
    const PhoneCountry(
      iso: 'US',
      name: 'United States',
      dialCode: '1',
      flag: '🇺🇸',
      minDigits: 10,
      maxDigits: 10,
    ),
  ];
}

/// Mobile numbers as typed, in E.164 (`+919876543210`), and masked for
/// showing to someone else.
class PhoneNumbers {
  const PhoneNumbers._();

  static final _e164 = RegExp(r'^\+[1-9][0-9]{6,14}$');

  /// The digits of what was typed, without a leading trunk `0`.
  static String nationalDigits(String typed) {
    var digits = typed.replaceAll(RegExp(r'[^0-9]'), '');
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// Why [typed] isn't a mobile number in [country], or null if it is.
  static String? validate(PhoneCountry country, String typed) {
    final digits = nationalDigits(typed);
    if (digits.isEmpty) return 'Enter your mobile number.';
    if (digits.length < country.minDigits ||
        digits.length > country.maxDigits) {
      return country.minDigits == country.maxDigits
          ? 'A ${country.name} mobile number has ${country.minDigits} digits.'
          : 'A ${country.name} mobile number has ${country.minDigits} to '
                '${country.maxDigits} digits.';
    }
    final prefix = country.mobilePrefix;
    if (prefix != null && !prefix.hasMatch(digits)) {
      return 'That doesn\'t look like a ${country.name} mobile number.';
    }
    return null;
  }

  /// [typed] in E.164 for [country], or null if it isn't valid.
  static String? toE164(PhoneCountry country, String typed) {
    if (validate(country, typed) != null) return null;
    final e164 = '+${country.dialCode}${nationalDigits(typed)}';
    return isE164(e164) ? e164 : null;
  }

  static bool isE164(String value) => _e164.hasMatch(value);

  /// The country whose code starts [e164], longest code first.
  static PhoneCountry? countryOf(String e164) {
    PhoneCountry? best;
    for (final c in PhoneCountry.all) {
      if (e164.startsWith(c.plusCode) &&
          (best == null || c.dialCode.length > best.dialCode.length)) {
        best = c;
      }
    }
    return best;
  }

  /// `+91 98765 43210` for showing your own number.
  static String format(String e164) {
    final country = countryOf(e164);
    if (country == null) return e164;
    final national = e164.substring(country.plusCode.length);
    if (national.length == 10) {
      return '${country.plusCode} ${national.substring(0, 5)} '
          '${national.substring(5)}';
    }
    return '${country.plusCode} $national';
  }

  /// `+91 98•••• 3210`: enough to recognise, not enough to copy.
  static String mask(String e164) {
    final country = countryOf(e164);
    final code = country?.plusCode ?? '';
    final national = e164.substring(code.isEmpty ? 1 : code.length);
    if (national.length < 7) return e164;
    final head = national.substring(0, 2);
    final tail = national.substring(national.length - 4);
    final hidden = '•' * (national.length - 6);
    return code.isEmpty ? '+$head$hidden $tail' : '$code $head$hidden $tail';
  }
}
