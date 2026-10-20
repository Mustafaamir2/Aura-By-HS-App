import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../l10n.dart';
import '../../routes.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/kit.dart';

class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key});

  void _newChat(BuildContext context) {
    showAuraSheet<void>(
      context,
      builder: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start a conversation', style: AppText.display(size: 22)),
          Text(
            'Message head office or any branch directly.',
            style: AppText.sans(size: 13, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 14),
          _PickRow(
            icon: Icons.support_agent_rounded,
            title: 'Aura Concierge',
            sub: 'Head office · bridal, packages & complaints',
            onTap: () {
              Navigator.pop(c);
              Navigator.pushNamed(
                context,
                Routes.chat,
                arguments: AuraStore.i.startThread(ThreadKind.concierge),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'BRANCHES',
            style: AppText.eyebrow(color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 6),
          for (final b in branches)
            _PickRow(
              icon: Icons.storefront_rounded,
              title: b.name,
              sub: b.address,
              onTap: () {
                Navigator.pop(c);
                Navigator.pushNamed(
                  context,
                  Routes.chat,
                  arguments: AuraStore.i.startThread(
                    ThreadKind.branch,
                    branchId: b.id,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final s = AuraStore.i;
        final threads = [...s.threads]
          ..sort((a, b) {
            if (a.kind == ThreadKind.announcements) return -1;
            if (b.kind == ThreadKind.announcements) return 1;
            final la =
                a.lastAt ??
                (a.messages.isEmpty ? DateTime(2000) : a.messages.last.at);
            final lb =
                b.lastAt ??
                (b.messages.isEmpty ? DateTime(2000) : b.messages.last.at);
            return lb.compareTo(la);
          });
        return Scaffold(
          backgroundColor: AppColors.background,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppColors.maroon,
            onPressed: () => _newChat(context),
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            label: Text(
              'New message',
              style: AppText.sans(weight: FontWeight.w600, color: Colors.white),
            ),
          ),
          body: Column(
            children: [
              ScreenHeader(
                title: context.t('messages'),
                subtitle: 'Chat with Aura and your branch',
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.maroon,
                  onRefresh: () async {
                    try {
                      await s.refreshThreads();
                    } catch (_) {}
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: threads.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final t = threads[i];
                      final last = t.messages.isEmpty ? null : t.messages.last;
                      final n = s.unread(t.id);
                      return AuraCard(
                        padding: const EdgeInsets.all(12),
                        onTap: () => Navigator.pushNamed(
                          context,
                          Routes.chat,
                          arguments: t.id,
                        ),
                        child: Row(
                          children: [
                            _ThreadIcon(t),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.title,
                                          style: AppText.sans(
                                            size: 14.5,
                                            weight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (last != null || t.lastAt != null)
                                        Text(
                                          agoLabel(last?.at ?? t.lastAt!),
                                          style: AppText.sans(
                                            size: 11,
                                            color: AppColors.mutedForeground,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          last == null
                                              ? (t.lastText?.isNotEmpty == true
                                                    ? t.lastText!
                                                    : t.subtitle)
                                              : '${last.mine ? 'You: ' : ''}${last.text.isEmpty ? '📷 Photo' : last.text.split('\n').first}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.sans(
                                            size: 12.5,
                                            color: n > 0
                                                ? AppColors.foreground
                                                : AppColors.mutedForeground,
                                            weight: n > 0
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (n > 0)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.maroon,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            '$n',
                                            style: AppText.sans(
                                              size: 11,
                                              weight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThreadIcon extends StatelessWidget {
  const _ThreadIcon(this.t);
  final Thread t;
  @override
  Widget build(BuildContext context) {
    if (t.kind == ThreadKind.announcements) return const Logo(size: 48);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: t.kind == ThreadKind.concierge
            ? AppGradients.gold
            : AppGradients.maroon,
        shape: BoxShape.circle,
      ),
      child: Icon(
        t.kind == ThreadKind.concierge
            ? Icons.support_agent_rounded
            : Icons.storefront_rounded,
        color: t.kind == ThreadKind.concierge
            ? AppColors.maroonInk
            : Colors.white,
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: onTap,
    leading: CircleAvatar(
      backgroundColor: AppColors.goldSoft,
      child: Icon(icon, color: AppColors.maroon),
    ),
    title: Text(title, style: AppText.sans(weight: FontWeight.w600)),
    subtitle: Text(
      sub,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.sans(size: 12, color: AppColors.mutedForeground),
    ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      color: AppColors.mutedForeground,
    ),
  );
}
