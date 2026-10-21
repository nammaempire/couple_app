import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';

/// The gradient each kind of event wears on the calendar.
extension CalendarEventLook on EventType {
  GradientPreset get preset => switch (this) {
    EventType.dateNight => GradientPreset.lavender,
    EventType.trip => GradientPreset.ocean,
    EventType.anniversary => GradientPreset.blush,
    EventType.birthday => GradientPreset.peach,
    EventType.meetup => GradientPreset.mint,
    EventType.custom => GradientPreset.sunny,
  };

  /// Two strong tones for the little dot pills under a day.
  List<Color> dotColors(Brightness b) {
    final accent = preset.accent(b);
    return [
      accent,
      Color.lerp(
        accent,
        b == Brightness.dark ? Colors.white : Colors.pink,
        .35,
      )!,
    ];
  }
}
