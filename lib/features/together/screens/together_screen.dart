import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/shell/tab_badges.dart';

import 'package:couple_app/features/music/screens/music_screen.dart';
import 'package:couple_app/features/plans/screens/plans_hub_screen.dart';
import 'package:couple_app/features/together/screens/calendar_screen.dart';
import 'package:couple_app/features/together/screens/love_notes_screen.dart';

/// The Together tab: planning your life as a couple. Calendar, love notes,
/// Plans (date planner, bucket list, wishlist, places and expenses) and
/// Music (your songs, and listening to them together).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key, this.initialTab = 0, this.isActive = true});

  final int initialTab;

  /// Whether this tab is on screen; a section's badge clears only then.
  final bool isActive;

  @override
  ConsumerState<TogetherScreen> createState() => TogetherScreenState();
}

class TogetherScreenState extends ConsumerState<TogetherScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  static const calendarTab = 0;
  static const loveNotesTab = 1;
  static const plansTab = 2;
  static const musicTab = 3;

  /// Lets the shell jump straight to a sub-tab (e.g. from Home).
  void showTab(int index) => _tabs.animateTo(index);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_markSeen);
    // Something new arriving in the open section clears straight away.
    for (final p in [
      calendarBadgeProvider,
      plansBadgeProvider,
      musicBadgeProvider,
    ]) {
      ref.listenManual(p, (_, next) {
        if (next > 0) _markSeen();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
  }

  @override
  void didUpdateWidget(covariant TogetherScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _markSeen();
  }

  /// The badge section of each sub-tab (love notes clear when opened).
  static const _sections = {
    calendarTab: BadgeSection.calendar,
    plansTab: BadgeSection.plans,
    musicTab: BadgeSection.music,
  };

  /// Clears the badge of the section on screen, if it has one.
  void _markSeen() {
    if (!mounted || !widget.isActive || _tabs.indexIsChanging) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final section = _sections[_tabs.index];
    if (section == null) return;
    final count = switch (_tabs.index) {
      calendarTab => ref.read(calendarBadgeProvider),
      plansTab => ref.read(plansBadgeProvider),
      _ => ref.read(musicBadgeProvider),
    };
    if (count > 0) {
      markSectionSeen(ref.read(currentUidProvider), [section]);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_markSeen);
    _tabs.dispose();
    super.dispose();
  }

  Tab _tab(IconData icon, String text, int count) => Tab(
    icon: Badge(
      isLabelVisible: count > 0,
      label: Text(badgeLabel(count)),
      child: Icon(icon),
    ),
    text: text,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Together'),
        bottom: TabBar(
          controller: _tabs,
          // Four tabs share a phone's width: keep "Love notes" whole.
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: [
            _tab(
              Icons.calendar_month_outlined,
              'Calendar',
              ref.watch(calendarBadgeProvider),
            ),
            _tab(
              Icons.mail_outline,
              'Love notes',
              ref.watch(loveNotesBadgeProvider),
            ),
            _tab(
              Icons.auto_awesome_outlined,
              'Plans',
              ref.watch(plansBadgeProvider),
            ),
            _tab(
              Icons.library_music_outlined,
              'Music',
              ref.watch(musicBadgeProvider),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          CalendarScreen(),
          LoveNotesScreen(),
          PlansHubScreen(),
          MusicScreen(),
        ],
      ),
    );
  }
}
