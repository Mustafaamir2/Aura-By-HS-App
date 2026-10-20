import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../services/api.dart';
import '../../services/live.dart';
import '../../l10n.dart';
import '../../routes.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/kit.dart';
import '../../widgets/payment_panel.dart';
import '../booking_screen.dart';

class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});
  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  ApptStatus _tab = ApptStatus.upcoming;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) {
        final list = AuraStore.i.appointments.where((a) => a.status == _tab).toList()
          ..sort((a, b) => _tab == ApptStatus.upcoming ? a.startsAt.compareTo(b.startsAt) : b.startsAt.compareTo(a.startsAt));
        return Column(children: [
          ScreenHeader(
            title: context.t('bookings'),
            subtitle: 'Your appointments at Aura',
            trailing: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: AppColors.maroon),
              onPressed: () {
                AuraStore.i.booking.clear();
                Navigator.pushNamed(context, Routes.booking);
              },
              icon: const Icon(Icons.add_rounded, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.muted, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(children: [
                for (final t in ApptStatus.values)
                  Expanded(
                    child: Pressable(
                      onTap: () => setState(() => _tab = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: _tab == t ? AppColors.card : Colors.transparent, borderRadius: BorderRadius.circular(11), boxShadow: _tab == t ? AppShadows.soft : null),
                        child: Text(
                          '${context.t(t.name)} (${AuraStore.i.appointments.where((a) => a.status == t).length})',
                          style: AppText.sans(size: 13, weight: FontWeight.w600, color: _tab == t ? AppColors.maroon : AppColors.mutedForeground),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.maroon,
              onRefresh: () async {
                try {
                  await AuraStore.i.refreshBookings();
                } on ApiException catch (e) {
                  if (context.mounted) toast(context, e.message, error: true);
                }
              },
              child: () {
                final weddings = AuraStore.i.bridal.where((b) => switch (_tab) {
                      ApptStatus.upcoming => b.status == 'tentative' || b.status == 'confirmed',
                      ApptStatus.past => b.status == 'completed',
                      ApptStatus.cancelled => b.status == 'cancelled',
                    }).toList();
                if (list.isEmpty && weddings.isEmpty) {
                  return ListView(children: [
                    EmptyState(
                      icon: Icons.event_available_rounded,
                      title: 'Nothing here yet',
                      body: _tab == ApptStatus.upcoming ? 'Book your next visit in under a minute.' : 'Your appointment history appears here.',
                      action: _tab == ApptStatus.upcoming ? Btn(label: context.t('bookAppointment'), expand: false, onTap: () => Navigator.pushNamed(context, Routes.booking)) : null,
                    ),
                  ]);
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    for (final w in weddings) ...[BridalCard(b: w), const SizedBox(height: 12)],
                    for (final a in list) ...[AppointmentCard(a: a), const SizedBox(height: 12)],
                  ],
                );
              }(),
            ),
          ),
        ]);
      },
    );
  }
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({super.key, required this.a});
  final Appointment a;

  @override
  Widget build(BuildContext context) {
    final s = AuraStore.i;
    final sv = serviceById(a.serviceIds.first);
    final balance = a.total - a.paid;
    final (label, bg, fg) = switch (a.status) {
      ApptStatus.upcoming when a.rawStatus == 'pending' => ('Awaiting confirmation', AppColors.goldSoft, AppColors.warning),
      ApptStatus.upcoming when a.rawStatus == 'checked-in' || a.rawStatus == 'in-progress' => ('At the salon', AppColors.successSoft, AppColors.success),
      ApptStatus.upcoming => (a.paid > 0 || a.rawStatus == 'confirmed' ? 'Confirmed' : 'Pay at salon', AppColors.successSoft, AppColors.success),
      ApptStatus.past => ('Completed', AppColors.muted, AppColors.mutedForeground),
      ApptStatus.cancelled => ('Cancelled', AppColors.destructiveSoft, AppColors.destructive),
    };
    return AuraCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AuraImage(sv?.image ?? '$img/salon.jpg', width: 64, height: 64, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.sans(size: 14.5, weight: FontWeight.w600))),
                  Badge2(label, bg: bg, fg: fg),
                ]),
                const SizedBox(height: 4),
                Text('${fmtDate(a.date)} · ${fmtTime(a.time)}', style: AppText.sans(size: 12.5, color: AppColors.foreground, weight: FontWeight.w500)),
                Text('${branchById(a.branchId)?.name} · ${stylistById(a.stylistId)?.name}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                Text('#${a.id.length > 12 ? a.id.substring(a.id.length - 6).toUpperCase() : a.id}', style: AppText.sans(size: 11, color: AppColors.mutedForeground)),
              ]),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: AppColors.secondary,
          child: Row(children: [
            Text('Total ${rs(a.total)}', style: AppText.sans(size: 12.5, weight: FontWeight.w600)),
            const Spacer(),
            if (a.status != ApptStatus.cancelled)
              Text(balance > 0 ? 'Paid ${rs(a.paid)} · Due ${rs(balance)}' : 'Fully paid', style: AppText.sans(size: 12, color: balance > 0 ? AppColors.warning : AppColors.success, weight: FontWeight.w600)),
            if (a.status == ApptStatus.cancelled) Text(a.cancelReason ?? '', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Wrap(spacing: 0, children: [
            if (a.status == ApptStatus.upcoming) ...[
              if (a.canCancel) _Act(Icons.edit_calendar_rounded, 'Reschedule', () => _reschedule(context)),
              if (balance > 0 && a.canPay)
                _Act(Icons.payments_outlined, a.paid > 0 ? 'Pay balance' : 'Pay now', () async {
                  final r = await showPaymentSheet(context, amount: balance, purpose: 'Balance · ${a.title}', allowSalon: false, target: PayTarget.appointment(a.id, plan: 'full'));
                  if (r != null) {
                    if (!s.live) s.payBalance(a, r);
                    if (context.mounted) toast(context, r.status == 'paid' ? 'Paid — see you soon!' : 'Receipt sent — the salon will confirm it.');
                  }
                }),
              _Act(Icons.chat_bubble_outline_rounded, 'Message', () {
                final id = s.startThread(ThreadKind.branch, branchId: a.branchId);
                Navigator.pushNamed(context, Routes.chat, arguments: id);
              }),
              if (a.canCancel)
                _Act(Icons.close_rounded, 'Cancel', () => _cancel(context), color: AppColors.destructive)
              else
                _Act(Icons.call_outlined, 'Call to change', () => toast(context, 'Within ${AuraStore.i.cancelHours} hours of the visit, please call the salon to change it.')),
            ],
            if (a.status == ApptStatus.past) ...[
              if (a.rating == null && a.status == ApptStatus.past && (a.canReview || !s.live)) _Act(Icons.star_outline_rounded, 'Rate visit', () => _rate(context)),
              if (a.rating != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 5; i++) Icon(i < a.rating! ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: AppColors.gold)]),
                ),
              _Act(Icons.receipt_long_outlined, 'Invoice', () => Navigator.pushNamed(context, Routes.invoices)),
            ],
            if (a.status != ApptStatus.upcoming)
              _Act(Icons.replay_rounded, 'Book again', () {
                s.booking
                  ..clear()
                  ..branchId = a.branchId
                  ..stylistId = a.stylistId;
                s.booking.serviceIds.addAll(a.serviceIds);
                Navigator.pushNamed(context, Routes.booking);
              }),
          ]),
        ),
      ]),
    );
  }

  Future<void> _reschedule(BuildContext context) async {
    final r = await showAuraSheet<(DateTime, String, String?)>(context, builder: (_) => _RescheduleSheet(a: a));
    if (r == null) return;
    try {
      await AuraStore.i.moveBooking(a, r.$1, r.$2, startAt: r.$3);
      if (context.mounted) toast(context, 'Moved to ${fmtDate(r.$1)} at ${fmtTime(r.$2)}');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final reason = await showAuraSheet<String>(context, builder: (_) => _CancelSheet(a: a));
    if (reason == null) return;
    try {
      await AuraStore.i.cancelBooking(a, reason);
      if (context.mounted) toast(context, a.paid > 0 ? 'Cancelled. Your ${rs(a.paid)} advance stays on your account — the salon will refund or move it.' : 'Appointment cancelled.');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _rate(BuildContext context) async {
    final r = await showAuraSheet<(int, String)>(context, builder: (_) => _RateSheet(a: a));
    if (r == null) return;
    try {
      await AuraStore.i.reviewBooking(a, r.$1, r.$2);
      if (context.mounted) toast(context, 'Thank you for your feedback! 🌸');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}

class _Act extends StatelessWidget {
  const _Act(this.icon, this.label, this.onTap, {this.color = AppColors.maroon});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: color),
        label: Text(label, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: color)),
      );
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({required this.a});
  final Appointment a;
  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime _d = widget.a.date.isBefore(DateTime.now()) ? DateTime.now() : widget.a.date;
  String? _t;
  List<Slot>? _slots;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuraStore.i.live) return;
    setState(() {
      _loading = true;
      _slots = null;
      _t = null;
    });
    try {
      final list = await fetchSlots(shopId: widget.a.branchId, day: _d, serviceIds: widget.a.serviceIds, staffId: widget.a.stylistId, exclude: widget.a.id);
      if (mounted) setState(() => _slots = list);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Reschedule', style: AppText.display(size: 22)),
        Text('Free up to ${AuraStore.i.cancelHours} hours before your appointment.', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        const SizedBox(height: 14),
        DateStrip(selected: _d, onPick: (d) {
          setState(() => _d = d);
          _load();
        }),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: AppColors.maroon)))
        else
          TimeGrid(selected: _t, live: _slots, onPick: (t) => setState(() => _t = t)),
        const SizedBox(height: 16),
        Btn(
          label: _t == null ? 'Pick a time' : 'Move to ${fmtDate(_d)}, ${fmtTime(_t!)}',
          onTap: _t == null ? null : () => Navigator.pop(context, (_d, _t!, _slots?.where((x) => x.time == _t).firstOrNull?.startAt)),
        ),
      ]);
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.a});
  final Appointment a;
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  static const reasons = ['Change of plans', 'Found another time', 'Feeling unwell', 'Travelling', 'Other'];
  String? _r;
  @override
  Widget build(BuildContext context) {
    final hours = widget.a.startsAt.difference(DateTime.now()).inHours;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Cancel appointment?', style: AppText.display(size: 22)),
      const SizedBox(height: 10),
      AuraCard(
        color: hours >= 24 ? AppColors.successSoft : AppColors.goldSoft,
        borderColor: Colors.transparent,
        padding: const EdgeInsets.all(12),
        child: Text(
          hours >= 24
              ? 'You’re cancelling more than 24 hours ahead${widget.a.paid > 0 ? ' — your ${rs(widget.a.paid)} advance will be refunded in full.' : '.'}'
              : 'Less than 24 hours to go. Advances may not be refundable — consider rescheduling instead.',
          style: AppText.sans(size: 13, height: 1.4),
        ),
      ),
      const SizedBox(height: 12),
      Text('Reason', style: AppText.sans(size: 13, weight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [for (final r in reasons) ChipPill(r, selected: _r == r, onTap: () => setState(() => _r = r))]),
      const SizedBox(height: 16),
      Btn(label: 'Cancel appointment', variant: BtnVariant.destructive, onTap: _r == null ? null : () => Navigator.pop(context, _r)),
      const SizedBox(height: 8),
      Btn(label: 'Keep my booking', variant: BtnVariant.ghost, onTap: () => Navigator.pop(context)),
    ]);
  }
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.a});
  final Appointment a;
  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _stars = 0;
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('How was your visit?', style: AppText.display(size: 22)),
        Text('${widget.a.title} with ${stylistById(widget.a.stylistId)?.name}', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              onPressed: () => setState(() => _stars = i),
              icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 38, color: AppColors.gold),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _c, maxLines: 3, decoration: const InputDecoration(hintText: 'Tell us what you loved (optional)')),
        const SizedBox(height: 16),
        Btn(label: 'Submit review', onTap: _stars == 0 ? null : () => Navigator.pop(context, (_stars, _c.text.trim()))),
      ]);
}


/// A wedding booked with the salon (live app): events, money and the advance.
class BridalCard extends StatelessWidget {
  const BridalCard({super.key, required this.b});
  final BridalBooking b;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (b.status) {
      'tentative' => (b.verifying ? 'Receipt being checked' : 'Advance needed', AppColors.goldSoft, AppColors.warning),
      'confirmed' => ('Dates confirmed', AppColors.successSoft, AppColors.success),
      'completed' => ('Completed', AppColors.muted, AppColors.mutedForeground),
      _ => ('Cancelled', AppColors.destructiveSoft, AppColors.destructive),
    };
    return AuraCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.diamond_outlined, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(child: Text(b.packageName, style: AppText.display(size: 17))),
          Badge2(label, bg: bg, fg: fg),
        ]),
        const SizedBox(height: 4),
        Text('${b.bookingNo} · ${b.shopName}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
        const SizedBox(height: 8),
        for (final e in b.events)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('• ${e['type']} — ${e['date'] == null ? '' : fmtDate(DateTime.parse('${e['date']}'))}${e['artistName'] != null ? ' · ${e['artistName']}' : ''}', style: AppText.sans(size: 13)),
          ),
        const Divider(),
        Row(children: [
          Expanded(child: Text('Paid ${rs(b.paid)} of ${rs(b.total)}', style: AppText.sans(size: 12.5, weight: FontWeight.w600))),
          if (b.canPay && !b.verifying)
            Btn(
              label: b.advanceDue > 0 ? 'Pay advance ${rs(b.advanceDue)}' : 'Pay ${rs(b.due)}',
              expand: false,
              height: 40,
              onTap: () async {
                final r = await showPaymentSheet(context,
                    amount: b.advanceDue > 0 ? b.advanceDue : b.due,
                    purpose: '${b.packageName} · ${b.bookingNo}',
                    target: PayTarget.bridal(b.id, plan: b.advanceDue > 0 ? 'advance' : 'full'));
                if (r != null && context.mounted) toast(context, r.status == 'paid' ? 'Payment received — thank you!' : 'Receipt sent — the salon will confirm it.');
              },
            ),
        ]),
        if (b.status == 'tentative')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Your dates are held once the ${rs(b.advanceDue + b.paid)} advance is paid. The salon will assign your artist and confirm timings.', style: AppText.sans(size: 12, color: AppColors.mutedForeground, height: 1.35)),
          ),
      ]),
    );
  }
}
