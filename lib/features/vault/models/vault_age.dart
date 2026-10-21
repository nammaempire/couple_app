import 'package:couple_app/features/auth/models/app_user.dart';

/// Whether the vault may open, by both partners' ages.
enum VaultAgeStatus {
  /// Both are 18 or older.
  ok,

  /// This user has no birthday and hasn't confirmed they're 18+.
  confirmMine,

  /// The partner has no birthday and hasn't confirmed yet.
  waitingForPartner,

  /// A birthday shows someone is under 18.
  underage,
}

/// The vault is for adults only.
const vaultMinimumAge = 18;

/// Full years between [birthday] and [now].
int ageOn(DateTime birthday, DateTime now) {
  var age = now.year - birthday.year;
  final hadBirthday =
      now.month > birthday.month ||
      (now.month == birthday.month && now.day >= birthday.day);
  if (!hadBirthday) age--;
  return age;
}

/// True for an adult, false for a minor, null when unknown. A birthday
/// decides; without one, a stored confirmation counts.
bool? isAdult(AppUser? user, DateTime now) {
  if (user == null) return null;
  final birthday = user.birthday;
  if (birthday != null) return ageOn(birthday, now) >= vaultMinimumAge;
  return user.adultConfirmedAt != null ? true : null;
}

VaultAgeStatus vaultAgeStatus({
  required AppUser me,
  required AppUser? partner,
  required DateTime now,
}) {
  final mine = isAdult(me, now);
  final theirs = isAdult(partner, now);
  if (mine == false || theirs == false) return VaultAgeStatus.underage;
  if (mine == null) return VaultAgeStatus.confirmMine;
  if (theirs == null) return VaultAgeStatus.waitingForPartner;
  return VaultAgeStatus.ok;
}
