import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _labels = {
    'reminders24h': ('Reminder a day before', Icons.event_rounded),
    'reminders2h': ('Reminder 2 hours before', Icons.alarm_rounded),
    'bookingUpdates': ('Booking & payment updates', Icons.receipt_rounded),
    'messages': ('New messages', Icons.chat_bubble_outline_rounded),
    'offers': ('Offers & new services', Icons.local_offer_outlined),
  };

  IconData _icon(String k) => switch (k) {
        'reminder' => Icons.event_rounded,
        'offer' => Icons.local_offer_rounded,
        'payment' => Icons.payments_rounded,
        _ => Icons.star_rounded,
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AuraStore.i,
        builder: (context, _) {
          final s = AuraStore.i;
          return AuraPage(
            title: 'Notifications',
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.feed.isEmpty) Text('Nothing new — reminders and payment updates appear here.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
              for (final n in s.feed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AuraCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CircleAvatar(backgroundColor: AppColors.goldSoft, child: Icon(_icon(n.kind), color: AppColors.maroon, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n.title, style: AppText.sans(weight: FontWeight.w600)),
                          Text(n.body, style: AppText.sans(size: 12.5, color: AppColors.mutedForeground)),
                        ]),
                      ),
                      Text(agoLabel(DateTime.now().subtract(Duration(minutes: (n.hoursAgo * 60).round()))), style: AppText.sans(size: 11, color: AppColors.mutedForeground)),
                    ]),
                  ),
                ),
              const SizedBox(height: 18),
              Text('Notification settings', style: AppText.display(size: 18)),
              const SizedBox(height: 8),
              AuraCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final e in _labels.entries)
                    SwitchListTile(
                      secondary: Icon(e.value.$2, color: AppColors.maroon),
                      title: Text(e.value.$1, style: AppText.sans(size: 14)),
                      value: s.notify[e.key] ?? false,
                      onChanged: (v) => s.update(() => s.notify[e.key] = v),
                    ),
                ]),
              ),
            ]),
          );
        },
      );
}
