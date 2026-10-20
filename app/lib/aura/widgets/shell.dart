import 'package:flutter/material.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Keeps the app at phone width (max 480) when run in a browser or tablet,
/// and switches to right-to-left for Urdu.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child, this.background = AppColors.background});
  final Widget child;
  final Color background;
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: context.isUrdu ? TextDirection.rtl : TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On an actual phone (or a narrow web/desktop window) the app should
          // fill the full width edge-to-edge. The capped "phone mockup" frame
          // is only useful on a wide desktop/web viewport, where it keeps the
          // layout from stretching awkwardly across a huge window.
          if (constraints.maxWidth <= 560) {
            return Material(color: background, child: child);
          }
          return ColoredBox(
            color: const Color(0xFFEDE4DA),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(color: background, child: child),
              ),
            ),
          );
        },
      ),
    );
  }
}

class AuraTab {
  const AuraTab(this.key, this.icon, this.activeIcon);
  final String key;
  final IconData icon, activeIcon;
}

const auraTabs = [
  AuraTab('home', Icons.home_outlined, Icons.home_rounded),
  AuraTab('bookings', Icons.event_note_outlined, Icons.event_note_rounded),
  AuraTab('messages', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  AuraTab('wallet', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded),
  AuraTab('profile', Icons.person_outline_rounded, Icons.person_rounded),
];

class AuraBottomNav extends StatelessWidget {
  const AuraBottomNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final unread = AuraStore.i.unread();
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.border)),
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (var i = 0; i < auraTabs.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => onTap(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(clipBehavior: Clip.none, children: [
                              Icon(i == index ? auraTabs[i].activeIcon : auraTabs[i].icon, color: i == index ? AppColors.maroon : AppColors.mutedForeground, size: 24),
                              if (i == 2 && unread > 0)
                                Positioned(
                                  right: -10,
                                  top: -6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    constraints: const BoxConstraints(minWidth: 18),
                                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(9), border: Border.all(color: AppColors.card, width: 1.5)),
                                    child: Text(unread > 9 ? '9+' : '$unread', textAlign: TextAlign.center, style: AppText.sans(size: 10, weight: FontWeight.w800, color: AppColors.maroon)),
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 4),
                            Text(context.t(auraTabs[i].key), style: AppText.sans(size: 11, weight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? AppColors.maroon : AppColors.mutedForeground)),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == index ? 5 : 0,
                              height: 5,
                              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
