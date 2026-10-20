import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/mock_data.dart';
import '../services/api.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import 'catalogue_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final p = AuraStore.i.profile;
  late final _name = TextEditingController(text: p.name);
  late final _email = TextEditingController(text: p.email);
  late final _phone = TextEditingController(text: p.phone);
  late DateTime? _bday = p.birthday;
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return setState(() => _err = 'Enter your full name.');
    if (_email.text.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) return setState(() => _err = 'That email doesn’t look right.');
    if (!RegExp(r'^03\d{9}$').hasMatch(_phone.text.replaceAll(RegExp(r'\D'), ''))) return setState(() => _err = 'Enter a mobile number like 03001234567.');
    p.name = _name.text.trim();
    if (!AuraStore.i.live) p.email = _email.text.trim();
    p.phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    p.birthday = _bday;
    try {
      await AuraStore.i.saveProfile();
    } on ApiException catch (e) {
      return setState(() => _err = e.message);
    }
    if (!mounted) return;
    toast(context, 'Profile saved');
    Navigator.pop(context);
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6, top: 14), child: Text(t, style: AppText.sans(size: 13, weight: FontWeight.w600)));

  @override
  Widget build(BuildContext context) => AuraPage(
        title: 'Edit profile',
        bottom: Btn(label: 'Save changes', onTap: _save),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Avatar(name: _name.text.isEmpty ? '?' : _name.text, size: 84, gold: true)),
          _label('Full name'),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {})),
          _label('Email'),
          TextField(controller: _email, readOnly: AuraStore.i.live, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(helperText: AuraStore.i.live ? 'Your sign-in email' : null)),
          _label('Mobile number'),
          TextField(controller: _phone, keyboardType: TextInputType.phone),
          _label('Birthday (for your birthday treat 🎂)'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), alignment: Alignment.centerLeft, side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
            onPressed: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime.now(), initialDate: _bday ?? DateTime(1998, 1, 1));
              if (d != null) setState(() => _bday = d);
            },
            icon: const Icon(Icons.cake_outlined, color: AppColors.maroon),
            label: Text(_bday == null ? 'Add birthday' : fmtDateLong(_bday!), style: AppText.sans(color: AppColors.foreground)),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: AppText.sans(size: 13, color: AppColors.destructive))),
        ]),
      );
}

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  static const skins = ['Normal', 'Dry', 'Oily', 'Combination', 'Sensitive'];
  final p = AuraStore.i.profile;
  late final _allergies = TextEditingController(text: p.allergies);
  late String _skin = skins.contains(p.skinNotes.split('|').first) ? p.skinNotes.split('|').first : '';
  late final _notes = TextEditingController(text: p.skinNotes.contains('|') ? p.skinNotes.split('|').last : '');

  @override
  void dispose() {
    _allergies.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuraPage(
        title: 'Beauty preferences',
        subtitle: 'Shared with your artist before every visit',
        bottom: Btn(
          label: 'Save preferences',
          onTap: () async {
            p.skinNotes = '$_skin|${_notes.text.trim()}';
            p.allergies = _allergies.text.trim();
            try {
              await AuraStore.i.saveProfile();
            } on ApiException catch (e) {
              if (context.mounted) toast(context, e.message, error: true);
              return;
            }
            if (!context.mounted) return;
            toast(context, 'Preferences saved');
            Navigator.pop(context);
          },
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Skin type', style: AppText.sans(weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final s in skins) ChipPill(s, selected: _skin == s, onTap: () => setState(() => _skin = s))]),
          const SizedBox(height: 18),
          Text('Allergies or sensitivities', style: AppText.sans(weight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(controller: _allergies, decoration: const InputDecoration(hintText: 'e.g. latex, fragrance, certain wax')),
          const SizedBox(height: 18),
          Text('Notes for your artist', style: AppText.sans(weight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(controller: _notes, maxLines: 4, decoration: const InputDecoration(hintText: 'Preferred looks, shades, hair length…')),
        ]),
      );
}

class FavouritesScreen extends StatelessWidget {
  const FavouritesScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AuraStore.i,
        builder: (context, _) {
          final list = AuraStore.i.favouriteServices.map(serviceById).whereType<Service>().toList();
          return AuraPage(
            title: 'Favourites',
            body: list.isEmpty
                ? EmptyState(
                    icon: Icons.favorite_outline_rounded,
                    title: 'No favourites yet',
                    body: 'Tap the heart on any service to save it here.',
                    action: Btn(label: 'Browse services', expand: false, onTap: () => Navigator.pushNamed(context, Routes.catalogue)),
                  )
                : Column(children: [for (final s in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: ServiceTile(s: s))]),
          );
        },
      );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => AuraPage(
        title: 'Help & FAQs',
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AuraCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final (q, a) in faqs)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    iconColor: AppColors.maroon,
                    title: Text(q, style: AppText.sans(weight: FontWeight.w600, size: 14)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [Text(a, style: AppText.sans(size: 13.5, color: AppColors.mutedForeground, height: 1.45))],
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          Text('Still need help?', style: AppText.display(size: 18)),
          const SizedBox(height: 10),
          Btn(label: 'Chat with Concierge', icon: Icons.support_agent_rounded, onTap: () => Navigator.pushNamed(context, Routes.chat, arguments: AuraStore.i.startThread(ThreadKind.concierge))),
          const SizedBox(height: 10),
          Btn(label: 'WhatsApp us', icon: Icons.chat_rounded, variant: BtnVariant.outline, onTap: () => launchUrl(Uri.parse('https://wa.me/923001234567'), mode: LaunchMode.externalApplication)),
        ]),
      );
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.privacy = false});
  final bool privacy;

  static const _privacy = [
    ('What we collect', 'Your name, mobile number, email, appointment history, beauty preferences and payment receipts. Card numbers are handled by the payment gateway and never stored by Aura.'),
    ('How we use it', 'To confirm and remind you of appointments, prepare your artist, issue invoices, run the loyalty programme and — only if you allow it — send offers.'),
    ('Sharing', 'Only with the branch you book at and our payment partners (JazzCash, Easypaisa, card processors). We never sell your data.'),
    ('Your choices', 'Edit your details in Profile, turn off offers in Notifications, or delete your account at any time from Profile.'),
  ];
  static const _terms = [
    ('Bookings', 'A booking is confirmed once you receive an SMS or in-app confirmation. Please arrive 10 minutes before your slot.'),
    ('Advances', 'Bridal bookings need a 30% advance. Other services may be paid in advance or at the salon.'),
    ('Rescheduling & cancellation', 'Reschedule free up to 4 hours before. Cancel 24+ hours ahead for a full refund of any advance. Bridal advances are non-refundable within 30 days of the event.'),
    ('Gift vouchers & points', 'Vouchers are valid for 12 months at all branches. Points have no cash value and expire after 18 months of inactivity.'),
  ];

  @override
  Widget build(BuildContext context) => AuraPage(
        title: privacy ? 'Privacy policy' : 'Terms of service',
        subtitle: 'Last updated October 2026',
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (h, b) in privacy ? _privacy : _terms) ...[
            Text(h, style: AppText.display(size: 17)),
            const SizedBox(height: 6),
            Text(b, style: AppText.sans(size: 14, height: 1.5, color: AppColors.mutedForeground)),
            const SizedBox(height: 18),
          ],
        ]),
      );
}
