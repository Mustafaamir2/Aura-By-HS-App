import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../services/api.dart';
import '../widgets/payment_panel.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../services/live.dart';
import '../theme.dart';
import '../widgets/kit.dart';

class PackagesScreen extends StatelessWidget {
  const PackagesScreen({super.key});

  Future<void> _book(BuildContext context, BridalPackage p) async {
    final s = AuraStore.i;
    if (s.live) {
      if (s.guest) {
        toast(context, 'Please sign in to book a bridal package.');
        return;
      }
      final booked = await showAuraSheet<BridalBooking>(context, builder: (_) => _BridalRequest(p: p));
      if (booked == null || !context.mounted) return;
      final pay = await showPaymentSheet(context, amount: booked.advanceDue, purpose: 'Advance · ${booked.packageName}', target: PayTarget.bridal(booked.id));
      if (!context.mounted) return;
      toast(context, pay == null ? 'Booking ${booked.bookingNo} requested — pay the advance from My bookings to hold your dates.' : 'Thank you! ${booked.bookingNo} — the salon will confirm your artist and timings.');
      Navigator.pushNamedAndRemoveUntil(context, Routes.main, (_) => false, arguments: 1);
      return;
    }
    final b = s.booking..clear();
    b.packageId = p.id;
    b.serviceIds.add(switch (p.id) {
      'pkg-essential' => 'svc-bridal-sig',
      'pkg-signature' => 'svc-bridal-hd',
      _ => 'svc-bridal-air',
    });
    b.notes = 'Package: ${p.name} (${rs(p.price)})';
    Navigator.pushNamed(context, Routes.booking);
  }

  void _consult(BuildContext context, BridalPackage p) {
    showAuraSheet<void>(context, builder: (c) => _ConsultSheet(p: p));
  }

  @override
  Widget build(BuildContext context) => AuraPage(
        title: 'Bridal packages',
        subtitle: 'Secure your dates with a 30% advance',
        body: Column(children: [
          for (final p in packages)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AuraCard(
                padding: EdgeInsets.zero,
                borderColor: p.popular ? AppColors.gold : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    height: 170,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                      child: Stack(fit: StackFit.expand, children: [
                        AuraImage(p.image),
                        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xE62B0709)], stops: [0.3, 1]))),
                        if (p.popular) const Positioned(top: 12, left: 12, child: Badge2('★ MOST LOVED', bg: AppColors.gold, fg: AppColors.maroonInk)),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: AppText.display(size: 22, color: Colors.white)),
                                Text(p.occasion, style: AppText.sans(size: 12.5, color: Colors.white70)),
                              ]),
                            ),
                            Text(rs(p.price), style: AppText.display(size: 20, color: AppColors.goldLight)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final inc in p.includes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            const Icon(Icons.check_circle_rounded, size: 17, color: AppColors.gold),
                            const SizedBox(width: 8),
                            Expanded(child: Text(inc, style: AppText.sans(size: 13.5))),
                          ]),
                        ),
                      const SizedBox(height: 6),
                      Text('Advance to confirm: ${rs(p.deposit)}', style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: AppColors.maroon)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: Btn(label: 'Book now', onTap: () => _book(context, p))),
                        const SizedBox(width: 10),
                        Expanded(child: Btn(label: 'Free consultation', variant: BtnVariant.outline, onTap: () => _consult(context, p))),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          Text('Prices include lashes and standard jewellery setting. Venue service available on request.', textAlign: TextAlign.center, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
        ]),
      );
}

class _ConsultSheet extends StatefulWidget {
  const _ConsultSheet({required this.p});
  final BridalPackage p;
  @override
  State<_ConsultSheet> createState() => _ConsultSheetState();
}

class _ConsultSheetState extends State<_ConsultSheet> {
  DateTime? _date;
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Free bridal consultation', style: AppText.display(size: 22)),
        Text('Our concierge will call you within a few hours about ${widget.p.name}.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
          onPressed: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), initialDate: DateTime.now().add(const Duration(days: 60)));
            if (d != null) setState(() => _date = d);
          },
          icon: const Icon(Icons.event_rounded, color: AppColors.maroon),
          label: Text(_date == null ? 'Wedding date' : fmtDateLong(_date!), style: AppText.sans(color: AppColors.foreground)),
        ),
        const SizedBox(height: 10),
        TextField(controller: _c, maxLines: 3, decoration: const InputDecoration(hintText: 'Events, venue city, number of family make-ups…')),
        const SizedBox(height: 16),
        Btn(
          label: 'Request call back',
          onTap: () {
            final s = AuraStore.i;
            final id = s.startThread(ThreadKind.concierge);
            s.sendMessage(id, 'Consultation request: ${widget.p.name}${_date == null ? '' : ' · wedding ${fmtDateLong(_date!)}'}${_c.text.trim().isEmpty ? '' : '\n${_c.text.trim()}'}');
            Navigator.pop(context);
            toast(context, 'Request sent — the concierge will call you shortly.');
          },
        ),
      ]);
}


/// Connected app: request a bridal package for real dates at a branch.
class _BridalRequest extends StatefulWidget {
  const _BridalRequest({required this.p});
  final BridalPackage p;
  @override
  State<_BridalRequest> createState() => _BridalRequestState();
}

class _BridalRequestState extends State<_BridalRequest> {
  static const types = ['Mayun', 'Mehndi', 'Nikah', 'Barat', 'Walima', 'Engagement', 'Trial', 'Photoshoot'];
  late String _shop = AuraStore.i.selectedBranchId;
  final Map<String, DateTime> _events = {};
  bool _venue = false;
  final _address = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(String t) async {
    final d = await showDatePicker(context: context, firstDate: DateTime.now().add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 730)), initialDate: _events[t] ?? DateTime.now().add(const Duration(days: 60)));
    if (d != null) setState(() => _events[t] = d);
  }

  Future<void> _submit() async {
    if (_events.isEmpty) return setState(() => _error = 'Add at least one event with its date (e.g. Barat).');
    if (_venue && _address.text.trim().isEmpty) return setState(() => _error = 'Add the venue address.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await AuraStore.i.bookBridal(
        shopId: _shop,
        packageId: widget.p.id,
        events: [for (final e in _events.entries) {'type': e.key, 'date': e.value.toIso8601String().substring(0, 10)}],
        location: _venue ? 'on-location' : 'salon',
        venue: _address.text.trim(),
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, b);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
      if (e.message.contains('mobile number') && mounted) Navigator.pushNamed(context, Routes.editProfile);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Book ${widget.p.name}', style: AppText.display(size: 22)),
        Text('${rs(widget.p.price)} · ${AuraStore.i.pay.bridalAdvancePct.round()}% advance holds your dates', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        const SizedBox(height: 14),
        Text('Branch', style: AppText.sans(size: 13, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final b in branches) ChipPill(b.name, selected: _shop == b.id, onTap: () => setState(() => _shop = b.id))]),
        const SizedBox(height: 14),
        Text('Your events', style: AppText.sans(size: 13, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in types)
            ChipPill(_events[t] == null ? t : '$t · ${fmtDate(_events[t]!)}', selected: _events.containsKey(t), onTap: () async {
              if (_events.containsKey(t)) {
                setState(() => _events.remove(t));
              } else {
                await _pick(t);
              }
            }),
        ]),
        const SizedBox(height: 10),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _venue, onChanged: (v) => setState(() => _venue = v), title: Text('Artist comes to my venue / home', style: AppText.sans(size: 14))),
        if (_venue) TextField(controller: _address, decoration: const InputDecoration(hintText: 'Venue address')),
        const SizedBox(height: 10),
        TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(hintText: 'Outfit colours, number of family make-ups, anything else')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: AppText.sans(size: 12.5, color: AppColors.destructive))),
        const SizedBox(height: 14),
        Btn(label: 'Request booking', loading: _busy, onTap: _submit),
      ]);
}
