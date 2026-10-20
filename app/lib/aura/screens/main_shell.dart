import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';

import '../widgets/shell.dart';
import 'tabs/bookings_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/messages_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/wallet_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = 0});
  final int initialTab;
  static void goTo(BuildContext context, int tab) => context.findAncestorStateOfType<_MainShellState>()?.go(tab);
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _i = widget.initialTab;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Connected: keep chat badges and booking statuses fresh (the salon may
    // reply, confirm or check a receipt at any moment).
    if (AuraStore.i.live) {
      _tick = Timer.periodic(const Duration(seconds: 45), (_) async {
        try {
          await AuraStore.i.refreshThreads();
          if (_i == 1) await AuraStore.i.refreshBookings();
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void go(int i) {
    setState(() => _i = i);
    if (AuraStore.i.live) {
      // Fresh data when a tab opens.
      final s = AuraStore.i;
      unawaited(switch (i) {
        1 => s.refreshBookings(),
        2 => s.refreshThreads(),
        3 => s.refreshWallet(),
        _ => Future<void>.value(),
      }.catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PhoneFrame(
      child: Scaffold(
        body: IndexedStack(index: _i, children: const [HomeTab(), BookingsTab(), MessagesTab(), WalletTab(), ProfileTab()]),
        bottomNavigationBar: AuraBottomNav(index: _i, onTap: go),
      ),
    );
  }
}
