import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/mock_data.dart';
import '../services/api.dart';
import '../services/live.dart';
import '../routes.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/payment_panel.dart';
import '../widgets/shell.dart';

/// Seven-step booking: branch → services → artist → date & time → notes →
/// review → payment, then a confirmation page.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

const _steps = ['Branch', 'Services', 'Artist', 'Date & time', 'Notes', 'Review', 'Payment'];

class _BookingScreenState extends State<BookingScreen> {
  final b = AuraStore.i.booking;
  int _step = 0;
  Cat _cat = Cat.bridal;
  final _notes = TextEditingController();
  final _promo = TextEditingController();
  String? _promoError;
  bool _payAdvance = true;
  bool _saving = false;
  List<Slot>? _slots;
  bool _loadingSlots = false;
  String? _slotError;

  @override
  void initState() {
    super.initState();
    b.branchId ??= AuraStore.i.selectedBranchId;
    _notes.text = b.notes;
    b.serviceIds.removeWhere((id) => serviceById(id) == null); // e.g. a service the salon stopped offering
    if (b.serviceIds.isNotEmpty) {
      _cat = serviceById(b.serviceIds.first)!.cat;
    } else if (menuCategories.isNotEmpty) {
      _cat = menuCategories.first.id;
    }
    // Arriving with services already picked (from a service page or "Book again") skips ahead.
    if (b.serviceIds.isNotEmpty) _step = b.stylistId != null ? 3 : 2;
  }

  @override
  void dispose() {
    _notes.dispose();
    _promo.dispose();
    super.dispose();
  }

  List<Service> get _services => b.serviceIds.map(serviceById).whereType<Service>().toList();
  List<AddOn> get _addOns => [for (final s in _services) ...s.addOns.where((a) => b.addOnIds.contains('${s.id}:${a.id}'))];
  int get _subtotal => _services.fold(0, (t, s) => t + s.price) + _addOns.fold(0, (t, a) => t + a.price);
  int get _minutes => _services.fold(0, (t, s) => t + s.minutes);
  Offer? get _offer => b.promo == null ? null : offers.where((o) => o.code == b.promo).firstOrNull;
  int get _discount => _offer?.discountOn(_subtotal) ?? 0;
  int get _total => _subtotal - _discount;
  bool get _isBridal => _services.any((s) => s.cat == Cat.bridal);
  num get _advancePct => _isBridal ? AuraStore.i.pay.bridalAdvancePct : AuraStore.i.pay.advancePct;
  int get _advance => (_total * _advancePct / 100).round();

  bool get _canNext => switch (_step) {
        0 => b.branchId != null,
        1 => b.serviceIds.isNotEmpty,
        2 => b.stylistId != null,
        3 => b.date != null && b.time != null && (!AuraStore.i.live || b.startAt != null),
        _ => true,
      };

  void _next() {
    if (_step == 4) b.notes = _notes.text.trim();
    if (_step < 6) {
      setState(() => _step++);
      if (_step == 3 && b.date != null) _loadSlots();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _pay() async {
    final s = AuraStore.i;
    if (s.guest) {
      final ok = await confirmDialog(context, title: 'Sign in to book', body: 'Create a free account to confirm appointments, pay online and earn points.', confirm: 'Sign in');
      if (ok && mounted) {
        s.signOut();
        Navigator.pushNamedAndRemoveUntil(context, Routes.auth, (_) => false);
      }
      return;
    }
    if (s.live) return _payLive();
    PaymentRecord? rec;
    if (_payAdvance) {
      rec = await showPaymentSheet(context, amount: _advance, purpose: 'Advance · ${_services.first.name}', allowSalon: false);
      if (rec == null) return; // closed the sheet
    }
    final appt = s.confirmBooking(total: _total, payment: rec);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookingConfirmedScreen(a: appt)));
  }

  /// Connected: the booking goes into the branch diary first, then the advance is paid against it.
  Future<void> _payLive() async {
    final s = AuraStore.i;
    final total = _total, advance = _advance, label = _services.first.name;
    setState(() => _saving = true);
    Appointment appt;
    try {
      appt = await s.createBooking(total: total);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, e.message, error: true);
      if (e.message.contains('mobile number')) Navigator.pushNamed(context, Routes.editProfile);
      if (e.status == 409) setState(() => _step = 3); // the slot went: pick another
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (_payAdvance && advance > 0) {
      final rec = await showPaymentSheet(context, amount: advance, purpose: 'Advance · $label', target: PayTarget.appointment(appt.id));
      if (rec != null) {
        await s.afterPayment();
        appt = s.appointments.where((a) => a.id == appt.id).firstOrNull ?? appt;
      }
    }
    if (!mounted) return;
    s.booking.clear();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BookingConfirmedScreen(a: appt)));
  }

  Future<void> _loadSlots() async {
    if (!AuraStore.i.live || b.date == null) return;
    setState(() {
      _loadingSlots = true;
      _slotError = null;
      _slots = null;
    });
    try {
      final list = await fetchSlots(shopId: b.branchId ?? AuraStore.i.selectedBranchId, day: b.date!, serviceIds: b.serviceIds, staffId: b.stylistId);
      if (mounted) setState(() => _slots = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _slotError = e.message);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PhoneFrame(
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (did, _) {
          if (!did) _back();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Column(children: [
            Container(
              padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 10, 16, 12),
              decoration: const BoxDecoration(color: AppColors.background, border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Column(children: [
                Row(children: [
                  IconButton(onPressed: _back, icon: const Icon(Icons.chevron_left_rounded, size: 28)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('STEP ${_step + 1} OF 7', style: AppText.eyebrow()),
                      Text(_steps[_step], style: AppText.display(size: 20)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 4,
                        decoration: BoxDecoration(color: i <= _step ? AppColors.maroon : AppColors.border, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                ]),
              ]),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(_step), child: _body()),
              ),
            ),
          ]),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
            child: SafeArea(
              top: false,
              child: Row(children: [
                if (b.serviceIds.isNotEmpty)
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('${b.serviceIds.length} service${b.serviceIds.length == 1 ? '' : 's'} · ${mins(_minutes)}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                      Text(rs(_total), style: AppText.display(size: 20)),
                    ]),
                  )
                else
                  const Spacer(),
                SizedBox(
                  width: 180,
                  child: _step < 6
                      ? Btn(label: 'Continue', onTap: _canNext ? _next : null)
                      : Btn(label: _payAdvance ? 'Pay ${rs(_advance)}' : 'Confirm booking', loading: _saving, onTap: _saving ? null : _pay),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_step) {
        0 => _branchStep(),
        1 => _servicesStep(),
        2 => _artistStep(),
        3 => _timeStep(),
        4 => _notesStep(),
        5 => _reviewStep(),
        _ => _paymentStep(),
      };

  Widget _branchStep() => ListView(padding: const EdgeInsets.all(16), children: [
        for (final br in branches)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AuraCard(
              borderColor: b.branchId == br.id ? AppColors.maroon : null,
              onTap: () => setState(() => b.branchId = br.id),
              child: Row(children: [
                Icon(b.branchId == br.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.maroon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(br.name, style: AppText.sans(size: 15, weight: FontWeight.w600)),
                    Text(br.address, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                    const SizedBox(height: 4),
                    Text(br.timings, style: AppText.sans(size: 12, color: AppColors.foreground)),
                  ]),
                ),
                Badge2(br.isOpenNow ? 'Open' : 'Closed', bg: br.isOpenNow ? AppColors.successSoft : AppColors.destructiveSoft, fg: br.isOpenNow ? AppColors.success : AppColors.destructive),
              ]),
            ),
          ),
      ]);

  Widget _servicesStep() {
    final list = services.where((s) => s.cat == _cat).toList();
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          itemCount: menuCategories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = menuCategories[i];
            final n = b.serviceIds.where((id) => serviceById(id)!.cat == c.id).length;
            return ChipPill(n > 0 ? '${c.label} · $n' : c.label, selected: _cat == c.id, onTap: () => setState(() => _cat = c.id));
          },
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 16), children: [
          for (final s in list) ...[
            _ServicePickTile(
              s: s,
              selected: b.serviceIds.contains(s.id),
              onTap: () => setState(() {
                if (!b.serviceIds.remove(s.id)) {
                  b.serviceIds.add(s.id);
                } else {
                  b.addOnIds.removeWhere((x) => x.startsWith('${s.id}:'));
                }
              }),
            ),
            if (b.serviceIds.contains(s.id) && s.addOns.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 18, bottom: 8),
                child: Column(children: [
                  for (final a in s.addOns)
                    CheckboxListTile(
                      dense: true,
                      activeColor: AppColors.maroon,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: b.addOnIds.contains('${s.id}:${a.id}'),
                      onChanged: (v) => setState(() => v == true ? b.addOnIds.add('${s.id}:${a.id}') : b.addOnIds.remove('${s.id}:${a.id}')),
                      title: Text('Add ${a.name}', style: AppText.sans(size: 13)),
                      secondary: Text('+${rs(a.price)}', style: AppText.sans(size: 12.5, weight: FontWeight.w600)),
                    ),
                ]),
              ),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    ]);
  }

  Widget _artistStep() {
    final cats = _services.map((s) => s.cat).toSet();
    final list = stylists.where((s) => s.branchIds.contains(b.branchId) && s.specialties.any(cats.contains)).toList();
    final others = stylists.where((s) => s.branchIds.contains(b.branchId) && !list.contains(s)).toList();
    Widget tile(Stylist? st) {
      final id = st?.id ?? 'any';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AuraCard(
          padding: const EdgeInsets.all(12),
          borderColor: b.stylistId == id ? AppColors.maroon : null,
          onTap: () => setState(() => b.stylistId = id),
          child: Row(children: [
            st == null
                ? Container(width: 52, height: 52, decoration: const BoxDecoration(gradient: AppGradients.gold, shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, color: AppColors.maroonInk))
                : Avatar(name: st.name, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st?.name ?? 'Any available artist', style: AppText.sans(size: 15, weight: FontWeight.w600)),
                Text(st?.role ?? 'We’ll match you with the best artist free at your time', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
                if (st != null)
                  Row(children: [
                    const Icon(Icons.star_rounded, size: 15, color: AppColors.gold),
                    Text(st.reviews == 0 ? ' New artist' : ' ${st.rating} · ${st.reviews} reviews', style: AppText.sans(size: 12)),
                  ]),
              ]),
            ),
            Icon(b.stylistId == id ? Icons.check_circle_rounded : Icons.circle_outlined, color: b.stylistId == id ? AppColors.maroon : AppColors.border),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      tile(null),
      if (list.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('RECOMMENDED FOR YOUR SERVICES', style: AppText.eyebrow(color: AppColors.mutedForeground))),
        for (final s in list) tile(s),
      ],
      if (others.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('ALSO AT THIS BRANCH', style: AppText.eyebrow(color: AppColors.mutedForeground))),
        for (final s in others) tile(s),
      ],
    ]);
  }

  Widget _timeStep() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Pick a day', style: AppText.sans(weight: FontWeight.w600)),
        const SizedBox(height: 10),
        DateStrip(selected: b.date, onPick: (d) {
          setState(() {
            b.date = d;
            b.time = null;
            b.startAt = null;
          });
          _loadSlots();
        }),
        const SizedBox(height: 20),
        Text('Available times', style: AppText.sans(weight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (b.date == null)
          Text('Choose a day first.', style: AppText.sans(size: 13, color: AppColors.mutedForeground))
        else if (AuraStore.i.live && _loadingSlots)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: AppColors.maroon)))
        else if (AuraStore.i.live && _slotError != null)
          Column(children: [
            Text(_slotError!, style: AppText.sans(size: 13, color: AppColors.destructive)),
            TextButton(onPressed: _loadSlots, child: const Text('Try again')),
          ])
        else if (AuraStore.i.live && (_slots ?? const []).where((x) => x.available).isEmpty)
          Text('No free times on this day — try another day or “Any available artist”.', style: AppText.sans(size: 13, color: AppColors.mutedForeground))
        else
          TimeGrid(
            selected: b.time,
            live: _slots,
            onPick: (t) => setState(() {
              b.time = t;
              b.startAt = _slots?.where((x) => x.time == t).firstOrNull?.startAt;
            }),
          ),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.mutedForeground),
          const SizedBox(width: 6),
          Expanded(child: Text('Your visit takes about ${mins(_minutes)}. Please arrive 10 minutes early.', style: AppText.sans(size: 12, color: AppColors.mutedForeground))),
        ]),
      ]);

  Widget _notesStep() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Anything your artist should know?', style: AppText.sans(weight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(controller: _notes, maxLines: 4, decoration: const InputDecoration(hintText: 'e.g. outfit colour, skin concerns, allergies, look you want…')),
        const SizedBox(height: 18),
        Text('Reference photo (optional)', style: AppText.sans(weight: FontWeight.w600)),
        const SizedBox(height: 8),
        Pressable(
          onTap: () async {
            final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1400);
            if (f == null) return;
            final bytes = await f.readAsBytes();
            setState(() => b.referencePhoto = bytes);
          },
          child: Container(
            height: 170,
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.border, width: 1.5)),
            clipBehavior: Clip.antiAlias,
            child: b.referencePhoto != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.memory(Uint8List.fromList(b.referencePhoto!), fit: BoxFit.cover),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filled(style: IconButton.styleFrom(backgroundColor: Colors.black54), onPressed: () => setState(() => b.referencePhoto = null), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18)),
                    ),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_photo_alternate_outlined, size: 34, color: AppColors.maroon),
                    const SizedBox(height: 6),
                    Text('Upload the look you love', style: AppText.sans(size: 13, color: AppColors.mutedForeground)),
                  ]),
          ),
        ),
      ]);

  Widget _reviewStep() {
    final br = branchById(b.branchId ?? '') ?? branches.first;
    final st = b.stylistId == 'any' ? null : stylistById(b.stylistId!);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AuraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ReviewLine(Icons.storefront_rounded, br.name, br.address, () => setState(() => _step = 0)),
          const Divider(color: AppColors.border),
          _ReviewLine(Icons.person_rounded, st?.name ?? 'Any available artist', st?.role ?? 'Assigned at check-in', () => setState(() => _step = 2)),
          const Divider(color: AppColors.border),
          _ReviewLine(Icons.event_rounded, '${fmtDate(b.date!)} at ${fmtTime(b.time!)}', 'About ${mins(_minutes)}', () => setState(() => _step = 3)),
        ]),
      ),
      const SizedBox(height: 12),
      AuraCard(
        child: Column(children: [
          for (final s in _services) InfoRow(s.name, '${s.priceFrom ? 'from ' : ''}${rs(s.price)}'),
          for (final a in _addOns) InfoRow('+ ${a.name}', rs(a.price)),
          const Divider(color: AppColors.border),
          InfoRow('Subtotal', rs(_subtotal)),
          if (_discount > 0) InfoRow('Promo ${b.promo}', '−${rs(_discount)}', valueColor: AppColors.success),
          InfoRow('Total', rs(_total), bold: true),
        ]),
      ),
      const SizedBox(height: 12),
      Text('Promo code', style: AppText.sans(weight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _promo, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(hintText: 'e.g. AURA15', errorText: _promoError))),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Btn(
            label: b.promo == null ? 'Apply' : 'Remove',
            variant: BtnVariant.outline,
            onTap: () => setState(() {
              if (b.promo != null) {
                b.promo = null;
                _promo.clear();
                return;
              }
              final o = offers.where((o) => o.code == _promo.text.trim().toUpperCase()).firstOrNull;
              if (o == null) {
                _promoError = 'That code isn’t valid.';
              } else if (o.discountOn(_subtotal) == 0) {
                _promoError = 'Spend ${rs(o.minSpend)} or more to use ${o.code}.';
              } else {
                _promoError = null;
                b.promo = o.code;
              }
            }),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final o in offers)
          ActionChip(
            label: Text(o.code, style: AppText.sans(size: 12, weight: FontWeight.w600, color: AppColors.maroon)),
            backgroundColor: AppColors.goldSoft,
            side: BorderSide.none,
            onPressed: () => setState(() => _promo.text = o.code),
          ),
      ]),
      if (b.notes.isNotEmpty || b.referencePhoto != null) ...[
        const SizedBox(height: 12),
        AuraCard(
          child: Row(children: [
            const Icon(Icons.sticky_note_2_outlined, color: AppColors.maroon),
            const SizedBox(width: 10),
            Expanded(child: Text([if (b.notes.isNotEmpty) b.notes, if (b.referencePhoto != null) '📷 Reference photo attached'].join('\n'), style: AppText.sans(size: 13))),
          ]),
        ),
      ],
    ]);
  }

  Widget _paymentStep() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('How would you like to pay?', style: AppText.display(size: 18)),
        const SizedBox(height: 12),
        _PayChoice(
          selected: _payAdvance,
          title: 'Pay ${_advancePct.round()}% advance now · ${rs(_advance)}',
          sub: 'Locks your slot. JazzCash, Easypaisa, card or bank transfer. Balance ${rs(_total - _advance)} at the salon.',
          badge: _isBridal ? 'Required for bridal' : 'Recommended',
          onTap: () => setState(() => _payAdvance = true),
        ),
        const SizedBox(height: 10),
        if (!_isBridal)
          _PayChoice(
            selected: !_payAdvance,
            title: 'Pay at the salon · ${rs(_total)}',
            sub: 'Cash, card or wallet on the day. Your booking is confirmed by SMS.',
            onTap: () => setState(() => _payAdvance = false),
          ),
        const SizedBox(height: 16),
        AuraCard(
          color: AppColors.secondary,
          borderColor: Colors.transparent,
          child: Text(
            'Free rescheduling up to 4 hours before. Cancel 24+ hours ahead for a full refund of your advance.${_isBridal ? ' Bridal advances are non-refundable within 30 days of the event.' : ''}',
            style: AppText.sans(size: 12.5, color: AppColors.mutedForeground, height: 1.4),
          ),
        ),
      ]);
}

class _ServicePickTile extends StatelessWidget {
  const _ServicePickTile({required this.s, required this.selected, required this.onTap});
  final Service s;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AuraCard(
        padding: const EdgeInsets.all(10),
        borderColor: selected ? AppColors.maroon : null,
        onTap: onTap,
        child: Row(children: [
          AuraImage(s.image, width: 62, height: 62, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: AppText.sans(size: 14, weight: FontWeight.w600)),
              Text('${mins(s.minutes)} · ${s.priceFrom ? 'from ' : ''}${rs(s.price)}', style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: selected ? AppColors.maroon : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: selected ? AppColors.maroon : AppColors.border, width: 1.5)),
            child: Icon(selected ? Icons.check_rounded : Icons.add_rounded, size: 18, color: selected ? Colors.white : AppColors.maroon),
          ),
        ]),
      );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.icon, this.title, this.sub, this.onEdit);
  final IconData icon;
  final String title, sub;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: AppColors.maroon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.sans(weight: FontWeight.w600)),
            Text(sub, style: AppText.sans(size: 12, color: AppColors.mutedForeground)),
          ]),
        ),
        TextButton(onPressed: onEdit, child: Text('Edit', style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: AppColors.maroon))),
      ]);
}

class _PayChoice extends StatelessWidget {
  const _PayChoice({required this.selected, required this.title, required this.sub, required this.onTap, this.badge});
  final bool selected;
  final String title, sub;
  final String? badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AuraCard(
        borderColor: selected ? AppColors.maroon : null,
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.maroon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (badge != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Badge2(badge!)),
              Text(title, style: AppText.sans(size: 14.5, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, style: AppText.sans(size: 12.5, color: AppColors.mutedForeground, height: 1.35)),
            ]),
          ),
        ]),
      );
}

/// 14-day picker shared by booking and reschedule.
class DateStrip extends StatelessWidget {
  const DateStrip({super.key, required this.selected, required this.onPick});
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = today.add(Duration(days: i));
          final on = selected != null && selected!.year == d.year && selected!.month == d.month && selected!.day == d.day;
          return Pressable(
            onTap: () => onPick(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 58,
              decoration: BoxDecoration(color: on ? AppColors.maroon : AppColors.card, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: on ? AppColors.maroon : AppColors.border)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(i == 0 ? 'Today' : weekdays[d.weekday - 1], style: AppText.sans(size: 11.5, color: on ? Colors.white70 : AppColors.mutedForeground)),
                Text('${d.day}', style: AppText.display(size: 22, color: on ? Colors.white : AppColors.foreground)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class TimeGrid extends StatelessWidget {
  const TimeGrid({super.key, required this.selected, required this.onPick, this.live});
  final String? selected;
  final ValueChanged<String> onPick;
  /// Free times from the server (connected app); the sample grid otherwise.
  final List<Slot>? live;
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.6,
        children: [
          for (final t in live?.map((x) => x.time) ?? timeSlots)
            Tooltip(
              message: _taken(t) ?? 'Available',
              child: Pressable(
                onTap: _taken(t) != null ? null : () => onPick(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == t ? AppColors.maroon : _taken(t) != null ? AppColors.muted : AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: selected == t ? AppColors.maroon : AppColors.border),
                  ),
                  child: Text(
                    fmtTime(t),
                    style: AppText.sans(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: selected == t ? Colors.white : _taken(t) != null ? AppColors.mutedForeground.withValues(alpha: 0.6) : AppColors.foreground,
                      decoration: _taken(t) != null ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  String? _taken(String t) {
    final l = live;
    if (l == null) return takenSlots[t];
    final hit = l.where((x) => x.time == t).firstOrNull;
    return hit == null || hit.available ? null : (hit.reason ?? 'Not available');
  }
}

class BookingConfirmedScreen extends StatelessWidget {
  const BookingConfirmedScreen({super.key, required this.a});
  final Appointment a;
  @override
  Widget build(BuildContext context) {
    final br = branchById(a.branchId) ?? Branch(id: a.branchId, name: a.shopName ?? 'Aura by HS', city: '', address: '', timings: '', isOpenNow: true, phone: '', lat: 0, lng: 0);
    return PhoneFrame(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 40, 20, 24), children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(gradient: AppGradients.maroon, shape: BoxShape.circle, boxShadow: AppShadows.lift),
                  child: const Icon(Icons.check_rounded, color: AppColors.goldLight, size: 54),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(AuraStore.i.live && a.rawStatus == 'pending' ? 'Booking received!' : 'Booking confirmed!', textAlign: TextAlign.center, style: AppText.display(size: 28)),
            const SizedBox(height: 6),
            Text(AuraStore.i.live ? (a.rawStatus == 'pending' ? 'The salon will confirm it shortly — watch My bookings ✨' : 'The salon has your booking. See you soon ✨') : 'We’ve sent the details by SMS. See you soon ✨', textAlign: TextAlign.center, style: AppText.sans(color: AppColors.mutedForeground)),
            const SizedBox(height: 22),
            AuraCard(
              child: Column(children: [
                InfoRow('Booking', '#${a.id.length > 12 ? a.id.substring(a.id.length - 6).toUpperCase() : a.id}'),
                InfoRow('Services', a.title),
                InfoRow('When', '${fmtDate(a.date)}, ${fmtTime(a.time)}'),
                InfoRow('Where', br.name),
                InfoRow('Artist', stylistById(a.stylistId)?.name ?? 'Any'),
                const Divider(color: AppColors.border),
                InfoRow('Total', rs(a.total), bold: true),
                InfoRow('Paid', a.paid > 0 ? '${rs(a.paid)} · ${a.paidBy}' : 'Pay at salon', valueColor: a.paid > 0 ? AppColors.success : null),
                if (a.total > a.paid) InfoRow('Due at salon', rs(a.total - a.paid)),
              ]),
            ),
            const SizedBox(height: 10),
            AuraCard(
              color: AppColors.goldSoft,
              borderColor: Colors.transparent,
              child: Row(children: [
                const Icon(Icons.stars_rounded, color: AppColors.maroon),
                const SizedBox(width: 10),
                Expanded(child: Text(AuraStore.i.live ? 'You earn Aura points when you pay your bill at the salon.' : 'You earned ${(a.total / 100).floor()} Aura points with this booking.', style: AppText.sans(size: 13, weight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 22),
            Btn(label: 'View my bookings', onTap: () => Navigator.pushNamedAndRemoveUntil(context, Routes.main, (_) => false, arguments: 1)),
            const SizedBox(height: 10),
            Btn(label: 'Message the branch', variant: BtnVariant.outline, onTap: () {
              final id = AuraStore.i.startThread(ThreadKind.branch, branchId: a.branchId);
              final nav = Navigator.of(context);
              nav.pushNamedAndRemoveUntil(Routes.main, (_) => false, arguments: 2);
              nav.pushNamed(Routes.chat, arguments: id);
            }),
            TextButton(onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.main, (_) => false), child: Text('Back to home', style: AppText.sans(color: AppColors.mutedForeground))),
          ]),
        ),
      ),
    );
  }
}
