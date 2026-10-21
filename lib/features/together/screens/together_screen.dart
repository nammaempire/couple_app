import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/music/screens/music_screen.dart';
import 'package:couple_app/features/plans/screens/plans_hub_screen.dart';
import 'package:couple_app/features/together/screens/calendar_screen.dart';
import 'package:couple_app/features/together/screens/love_notes_screen.dart';

/// The Together tab: planning your life as a couple. Calendar, love notes,
/// Plans (date planner, bucket list, wishlist, places and expenses) and
/// Music (your songs, and listening to them together).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key, this.initialTab = 0});

  final int initialTab;

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
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Together'),
        bottom: TabBar(
          controller: _tabs,
          // Four tabs share a phone's width: keep "Love notes" whole.
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Calendar'),
            Tab(icon: Icon(Icons.mail_outline), text: 'Love notes'),
            Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'Plans'),
            Tab(icon: Icon(Icons.library_music_outlined), text: 'Music'),
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
