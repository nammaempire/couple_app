import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/plans/screens/plans_hub_screen.dart';
import 'package:couple_app/features/together/screens/calendar_screen.dart';
import 'package:couple_app/features/together/screens/love_notes_screen.dart';

/// The Together tab: planning your life as a couple. Calendar, love notes,
/// and Plans (date planner, bucket list, wishlist, places and expenses).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<TogetherScreen> createState() => TogetherScreenState();
}

class TogetherScreenState extends ConsumerState<TogetherScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab,
  );

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
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Calendar'),
            Tab(icon: Icon(Icons.mail_outline), text: 'Love notes'),
            Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'Plans'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [CalendarScreen(), LoveNotesScreen(), PlansHubScreen()],
      ),
    );
  }
}
