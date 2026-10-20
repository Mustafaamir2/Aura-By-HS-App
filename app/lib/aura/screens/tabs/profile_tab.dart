import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/mock_data.dart';
import '../../l10n.dart';
import '../../routes.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/kit.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final s = AuraStore.i;
        final p = s.profile;
        return ListView(padding: EdgeInsets.zero, children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 22, 16, 22),
            decoration: const BoxDecoration(gradient: AppGradients.maroon, borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
            child: Row(children: [
              Avatar(name: p.name, size: 66, gold: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.guest ? 'Guest' : p.name, style: AppText.display(size: 22, color: Colors.white)),
                  Text(s.guest ? 'Sign in to book and earn points' : (p.email.isNotEmpty ? p.email : p.phone), style: AppText.sans(size: 12.5, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Badge2('${s.tier} · ${s.loyaltyPoints} pts', bg: AppColors.gold, fg: AppColors.maroonInk),
                ]),
              ),
              if (!s.guest)
                IconButton(tooltip: 'Edit profile', onPressed: () => Navigator.pushNamed(context, Routes.editProfile), icon: const Icon(Icons.edit_rounded, color: Colors.white)),
            ]),
          ),
          if (s.guest)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Btn(label: 'Sign in or create account', onTap: () {
                s.signOutAsync();
                Navigator.pushNamedAndRemoveUntil(context, Routes.auth, (_) => false);
              }),
            ),
          const SizedBox(height: 16),
          _Group(children: [
            _Row(Icons.favorite_outline_rounded, 'Favourites', () => Navigator.pushNamed(context, Routes.favourites)),
            _Row(Icons.spa_outlined, 'Beauty preferences', () => Navigator.pushNamed(context, Routes.preferences), sub: 'Skin type, allergies, notes for your artist'),
            _Row(Icons.receipt_long_outlined, 'Invoices & receipts', () => Navigator.pushNamed(context, Routes.invoices)),
            _Row(Icons.location_on_outlined, 'Our branches', () => Navigator.pushNamed(context, Routes.branches)),
            _Row(Icons.photo_library_outlined, 'Lookbook', () => Navigator.pushNamed(context, Routes.gallery)),
            _Row(Icons.local_offer_outlined, 'Offers', () => Navigator.pushNamed(context, Routes.offers)),
          ]),
          _Group(children: [
            _Row(Icons.notifications_none_rounded, 'Notifications', () => Navigator.pushNamed(context, Routes.notifications)),
            ListTile(
              leading: const Icon(Icons.translate_rounded, color: AppColors.maroon),
              title: Text(context.t('language'), style: AppText.sans(weight: FontWeight.w500)),
              trailing: SegmentedButton<String>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(selectedBackgroundColor: AppColors.maroon, selectedForegroundColor: Colors.white, visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'ur', label: Text('اردو'))],
                selected: {s.lang},
                onSelectionChanged: (v) => s.setLang(v.first),
              ),
            ),
          ]),
          _Group(children: [
            _Row(Icons.help_outline_rounded, 'Help & FAQs', () => Navigator.pushNamed(context, Routes.help)),
            _Row(Icons.chat_outlined, 'WhatsApp us', () => launchUrl(Uri.parse('https://wa.me/${_wa(s.links.whatsapp.isNotEmpty ? s.links.whatsapp : '03001234567')}'), mode: LaunchMode.externalApplication)),
            _Row(Icons.call_outlined, 'Call the salon', () => launchUrl(Uri.parse('tel:${branchById(s.selectedBranchId)?.phone.isNotEmpty == true ? branchById(s.selectedBranchId)!.phone : '+924235771420'}'))),
            _Row(Icons.privacy_tip_outlined, 'Privacy policy', () => Navigator.pushNamed(context, Routes.legal, arguments: 'privacy')),
            _Row(Icons.description_outlined, 'Terms of service', () => Navigator.pushNamed(context, Routes.legal)),
          ]),
          if (!s.guest)
            _Group(children: [
              _Row(Icons.delete_outline_rounded, 'Delete account', () async {
                if (await confirmDialog(context, title: 'Delete your account?', body: 'Your profile, points and history will be permanently removed. Upcoming appointments are cancelled.', confirm: 'Delete', danger: true)) {
                  try {
                    await s.deleteAccount();
                  } catch (e) {
                    if (context.mounted) toast(context, '$e', error: true);
                    return;
                  }
                  if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, Routes.auth, (_) => false);
                }
              }, color: AppColors.destructive),
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Btn(
              label: context.t('logout'),
              variant: BtnVariant.outline,
              icon: Icons.logout_rounded,
              onTap: () async {
                if (await confirmDialog(context, title: 'Log out?', body: 'You can sign back in any time.', confirm: 'Log out')) {
                  await s.signOutAsync();
                  if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, Routes.auth, (_) => false);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 28, top: 6),
            child: Text('Aura by HS · v1.0.0', textAlign: TextAlign.center, style: AppText.sans(size: 11.5, color: AppColors.mutedForeground)),
          ),
        ]);
      },
    );
  }
}

String _wa(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  return d.startsWith('0') ? '92${d.substring(1)}' : d;
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: AuraCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56, color: AppColors.border),
              children[i],
            ],
          ]),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.onTap, {this.sub, this.color = AppColors.maroon});
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(label, style: AppText.sans(weight: FontWeight.w500, color: color == AppColors.maroon ? AppColors.foreground : color)),
        subtitle: sub == null ? null : Text(sub!, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.mutedForeground),
      );
}
