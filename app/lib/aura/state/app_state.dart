import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/mock_data.dart';
import '../services/api.dart';
import '../services/auth.dart';
import '../services/live.dart';

/// App-wide store. Widgets listen with
/// `ListenableBuilder(listenable: AuraStore.i, builder: ...)`.
///
/// Two modes, same screens:
/// * **live** (servers configured, see config.dart) — sign-in is Supabase Auth,
///   and the catalogue, bookings, payments, chats and wallet come from the Aura
///   API, shared with the POS.
/// * **demo** — everything runs on built-in sample data, nothing leaves the phone.

enum PayMethod { jazzcash, easypaisa, card, bank, salon }

extension PayMethodX on PayMethod {
  String get label => switch (this) {
        PayMethod.jazzcash => 'JazzCash',
        PayMethod.easypaisa => 'Easypaisa',
        PayMethod.card => 'Debit / Credit card',
        PayMethod.bank => 'Bank transfer',
        PayMethod.salon => 'Pay at salon',
      };
}

class PaymentRecord {
  PaymentRecord({required this.id, required this.at, required this.amount, required this.method, required this.purpose, required this.status, required this.reference});
  final String id, purpose, reference;
  final DateTime at;
  final int amount;
  final PayMethod method;
  final String status; // paid | pending
}

class SavedMethod {
  SavedMethod(this.id, this.method, this.label, {this.isDefault = false});
  final String id, label;
  final PayMethod method;
  bool isDefault;
}

class Voucher {
  Voucher(this.code, this.value, this.recipient, this.at);
  final String code, recipient;
  final int value;
  final DateTime at;
}

class Profile {
  Profile({this.name = 'Ayesha Rizwan', this.email = '', this.phone = '03001234567', this.birthday, this.skinNotes = '', this.allergies = ''});
  String name, email, phone, skinNotes, allergies;
  DateTime? birthday;
  String get firstName => name.split(' ').first;
  String get initials => name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
}

class BookingDraft {
  String? branchId;
  final List<String> serviceIds = [];
  final List<String> addOnIds = [];
  String? stylistId; // 'any' or an id
  DateTime? date;
  String? time;
  /// Exact start from the server's slot list (live mode).
  String? startAt;
  String notes = '';
  List<int>? referencePhoto;
  String? promo;
  String? packageId;

  void clear() {
    branchId = null;
    serviceIds.clear();
    addOnIds.clear();
    stylistId = null;
    date = null;
    time = null;
    startAt = null;
    notes = '';
    referencePhoto = null;
    promo = null;
    packageId = null;
  }
}

class AuraStore extends ChangeNotifier {
  AuraStore._();
  static final AuraStore i = AuraStore._();

  // ---- persisted
  bool onboarded = false;
  bool authed = false;
  bool guest = false;
  String lang = 'en';
  final Profile profile = Profile();

  // ---- session
  String selectedBranchId = 'gulberg';
  final BookingDraft booking = BookingDraft();
  final List<Appointment> appointments = seedAppointments();
  final List<Thread> threads = seedThreads();
  final Map<String, DateTime> readAt = {};
  final List<PaymentRecord> payments = [];
  final List<Voucher> vouchers = [];
  final List<SavedMethod> savedMethods = [SavedMethod('sm1', PayMethod.easypaisa, 'Easypaisa •••• 4567', isDefault: true)];
  final Set<String> favouriteServices = {};
  final Set<String> favouriteStylists = {};
  int loyaltyPoints = 2450;
  final Map<String, bool> notify = {'reminders24h': true, 'reminders2h': true, 'offers': true, 'bookingUpdates': true, 'messages': true};

  // ---- live
  bool get live => AuraConfig.live;
  /// Set while the first catalogue load is running (the free server may be waking up).
  bool connecting = false;
  String? connectError;
  CatalogExtras? extras;
  final List<BridalBooking> bridal = [];
  final List<Invoice> invoices = [];
  final List<Map<String, dynamic>> livePayments = [];
  final List<Map<String, dynamic>> liveVouchers = [];
  int credit = 0;
  num pointValue = 0.5;
  int announcementsUnread = 0;
  bool profileComplete = true;
  StreamSubscription<dynamic>? _authSub;

  PayConfig get pay => extras?.pay ?? PayConfig();
  AppLinks get links => extras?.links ?? AppLinks();
  num get cancelHours => extras?.cancelHours ?? 4;

  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;
      onboarded = p.getBool('onboarded') ?? false;
      authed = p.getBool('authed') ?? false;
      guest = p.getBool('guest') ?? false;
      lang = p.getString('lang') ?? 'en';
      profile.name = p.getString('name') ?? profile.name;
      profile.email = p.getString('email') ?? '';
      profile.phone = p.getString('phone') ?? profile.phone;
      profile.skinNotes = p.getString('skin') ?? '';
      profile.allergies = p.getString('allergies') ?? '';
    } catch (_) {
      // Storage unavailable (e.g. private browsing on web): run in memory.
    }
    if (live) await _startLive();
  }

  Future<void> _startLive() async {
    // Demo samples never show in a connected app.
    appointments.clear();
    threads.clear();
    payments.clear();
    savedMethods.clear();
    loyaltyPoints = 0;
    try {
      await AuthService.init();
    } catch (e) {
      connectError = 'Sign-in could not start: $e';
      return;
    }
    authed = AuthService.i.signedIn || guest;
    if (AuthService.i.signedIn) guest = false;
    _authSub = AuthService.i.changes.listen((state) async {
      final signedIn = state.session != null;
      if (signedIn && (!authed || guest)) {
        authed = true;
        guest = false;
        _save();
        notifyListeners();
      }
      if (signedIn) unawaited(refreshAccount());
      if (!signedIn && authed && !guest) {
        authed = false;
        _clearAccount();
        _save();
        notifyListeners();
      }
      if (state.event.name == 'passwordRecovery') passwordRecovery.value = true;
    });
    unawaited(refreshCatalog());
    if (AuthService.i.signedIn) unawaited(refreshAccount());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Flips to true when the customer opens a password-reset link.
  final ValueNotifier<bool> passwordRecovery = ValueNotifier(false);

  Future<void> refreshCatalog() async {
    connecting = true;
    connectError = null;
    notifyListeners();
    try {
      extras = applyCatalog(Map<String, dynamic>.from(await Api.i.get('/v1/catalog')));
      if (branches.isNotEmpty && !branches.any((b) => b.id == selectedBranchId)) selectedBranchId = branches.first.id;
      _syncAnnouncements();
    } on ApiException catch (e) {
      connectError = e.message;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void _clearAccount() {
    appointments.clear();
    bridal.clear();
    invoices.clear();
    livePayments.clear();
    liveVouchers.clear();
    threads.removeWhere((t) => t.kind != ThreadKind.announcements);
    loyaltyPoints = 0;
    credit = 0;
  }

  /// Everything that belongs to the signed-in customer, fresh from the server.
  Future<void> refreshAccount() async {
    if (!live || !AuthService.i.signedIn) return;
    try {
      final me = Map<String, dynamic>.from(await Api.i.get('/v1/me'));
      profile.name = '${me['name'] ?? profile.name}';
      profile.email = '${me['email'] ?? ''}';
      profile.phone = '${me['phone'] ?? ''}';
      profile.allergies = '${me['allergies'] ?? ''}';
      profile.skinNotes = '${me['skinType'] ?? ''}|${me['notes'] ?? ''}';
      profile.birthday = me['birthday'] == null ? null : DateTime.tryParse('${me['birthday']}');
      profileComplete = me['profileComplete'] == true;
      _save();
      await Future.wait([refreshBookings(), refreshThreads(), refreshWallet(), refreshInvoices()]);
    } on ApiException catch (e) {
      connectError = e.needsSignIn ? null : e.message;
    }
    notifyListeners();
  }

  Future<void> refreshBookings() async {
    if (!live || !AuthService.i.signedIn) return;
    final r = Map<String, dynamic>.from(await Api.i.get('/v1/bookings'));
    appointments
      ..clear()
      ..addAll((r['appointments'] as List).cast<Map<String, dynamic>>().map(appointmentFromJson));
    bridal
      ..clear()
      ..addAll((r['bridal'] as List).cast<Map<String, dynamic>>().map(BridalBooking.new));
    notifyListeners();
  }

  Future<void> refreshWallet() async {
    if (!live || !AuthService.i.signedIn) return;
    final w = Map<String, dynamic>.from(await Api.i.get('/v1/wallet'));
    loyaltyPoints = ((w['points'] ?? 0) as num).toInt();
    credit = ((w['credit'] ?? 0) as num).round();
    liveVouchers
      ..clear()
      ..addAll((w['vouchers'] as List).cast<Map<String, dynamic>>());
    vouchers
      ..clear()
      ..addAll(liveVouchers.map((v) => Voucher('${v['code']}', ((v['balance'] ?? 0) as num).round(), '${v['recipientName'] ?? ''}', DateTime.now())));
    pointValue = (w['pointValue'] ?? 1) as num;
    livePayments
      ..clear()
      ..addAll((w['payments'] as List).cast<Map<String, dynamic>>());
    payments
      ..clear()
      ..addAll(livePayments.where((p) => p['status'] == 'paid' || p['status'] == 'verifying').map((p) => PaymentRecord(
            id: '${p['paymentNo']}',
            at: DateTime.tryParse('${p['paidAt'] ?? p['createdAt']}')?.toLocal() ?? DateTime.now(),
            amount: ((p['amount'] ?? 0) as num).round(),
            method: _payMethod('${p['method']}'),
            purpose: '${p['refLabel'] ?? ''}',
            status: p['status'] == 'paid' ? 'paid' : 'pending',
            reference: '${p['gatewayRef'] ?? p['paymentNo']}',
          )));
    notifyListeners();
  }

  Future<void> refreshInvoices() async {
    if (!live || !AuthService.i.signedIn) return;
    final r = Map<String, dynamic>.from(await Api.i.get('/v1/invoices'));
    invoices
      ..clear()
      ..addAll((r['invoices'] as List).cast<Map<String, dynamic>>().map(Invoice.new));
    notifyListeners();
  }

  static PayMethod _payMethod(String m) => switch (m) {
        'jazzcash' => PayMethod.jazzcash,
        'easypaisa' => PayMethod.easypaisa,
        'card' => PayMethod.card,
        'bank-transfer' => PayMethod.bank,
        _ => PayMethod.salon,
      };

  /// The bell: reminders, payment updates and news. Sample items in demo mode.
  List<AppNotification> get feed {
    if (!live) return seedNotifications;
    final now = DateTime.now();
    double ago(DateTime t) => now.difference(t).inMinutes / 60;
    final out = <(DateTime, AppNotification)>[];
    for (final a in appointments.where((a) => a.status == ApptStatus.upcoming)) {
      final until = a.startsAt.difference(now);
      if (until.inHours <= 48 && !until.isNegative) {
        out.add((now, AppNotification('Appointment reminder', '${a.title} at ${a.shopName ?? 'Aura'} — ${fmtDate(a.date)}, ${fmtTime(a.time)}.', 0, 'reminder')));
      }
      if (a.rawStatus == 'pending') out.add((a.startsAt.subtract(const Duration(days: 30)), AppNotification('Waiting for confirmation', '${a.title} on ${fmtDate(a.date)} — the salon will confirm shortly.', 1, 'reminder')));
    }
    for (final p in livePayments.take(10)) {
      final at = DateTime.tryParse('${p['paidAt'] ?? p['createdAt']}')?.toLocal() ?? now;
      final st = '${p['status']}';
      final title = switch (st) { 'paid' => 'Payment received', 'verifying' => 'Receipt being checked', 'rejected' => 'Payment not accepted', 'failed' => 'Payment not completed', _ => '' };
      if (title.isEmpty) continue;
      out.add((at, AppNotification(title, '${rs((p['amount'] ?? 0) as num)} · ${p['refLabel'] ?? ''}${st == 'rejected' && p['rejectReason'] != null ? ' — ${p['rejectReason']}' : ''}', ago(at), 'payment')));
    }
    for (final a in extras?.announcements ?? const <Announcement>[]) {
      out.add((a.at, AppNotification(a.title, a.body, ago(a.at), 'offer')));
    }
    for (final a in appointments.where((a) => a.status == ApptStatus.past && a.canReview).take(2)) {
      out.add((a.startsAt, AppNotification('Rate your visit', 'How was ${a.title}${a.staffName?.isNotEmpty == true ? ' with ${a.staffName}' : ''}?', ago(a.startsAt), 'review')));
    }
    out.sort((x, y) => y.$1.compareTo(x.$1));
    return [for (final e in out) e.$2];
  }

  // ---- chats (live)

  void _syncAnnouncements() {
    final list = extras?.announcements ?? const [];
    threads.removeWhere((t) => t.kind == ThreadKind.announcements);
    threads.insert(
      0,
      Thread(
        id: 'th-announce',
        kind: ThreadKind.announcements,
        title: 'Aura Updates',
        subtitle: 'News & offers from ${extras?.businessName ?? 'Aura by HS'}',
        messages: [
          for (final a in list.reversed)
            ChatMessage(id: a.id, mine: false, author: extras?.businessName ?? 'Aura by HS', text: a.body.isEmpty ? a.title : '${a.title}\n${a.body}', at: a.at, imageUrl: a.imageUrl),
        ],
        serverUnread: announcementsUnread,
      ),
    );
  }

  Future<void> refreshThreads() async {
    if (!live || !AuthService.i.signedIn) return;
    final r = Map<String, dynamic>.from(await Api.i.get('/v1/threads'));
    announcementsUnread = ((r['announcements']?['unread'] ?? 0) as num).toInt();
    final existing = {for (final t in threads) t.id: t};
    final next = <Thread>[];
    for (final t in (r['threads'] as List).cast<Map<String, dynamic>>()) {
      final key = '${t['key']}';
      final old = existing[key];
      next.add(Thread(
        id: key,
        kind: key == 'hq' ? ThreadKind.concierge : ThreadKind.branch,
        title: '${t['title']}',
        subtitle: '${t['subtitle'] ?? ''}',
        branchId: key == 'hq' ? null : key,
        messages: old?.messages ?? [],
        serverUnread: ((t['unread'] ?? 0) as num).toInt(),
        lastText: '${t['lastText'] ?? ''}',
        lastAt: DateTime.tryParse('${t['lastAt']}')?.toLocal(),
      ));
    }
    // Keep a chat the customer just opened but has not written in yet.
    for (final t in threads) {
      if (t.kind != ThreadKind.announcements && !next.any((n) => n.id == t.id) && t.messages.isEmpty) next.add(t);
    }
    threads
      ..removeWhere((t) => t.kind != ThreadKind.announcements)
      ..addAll(next);
    _syncAnnouncements();
    notifyListeners();
  }

  Future<void> loadMessages(String key) async {
    if (!live || key == 'th-announce') {
      if (live && key == 'th-announce' && announcementsUnread > 0) {
        announcementsUnread = 0;
        _syncAnnouncements();
        notifyListeners();
        unawaited(Api.i.post('/v1/announcements/read').then((_) {}, onError: (_) {}));
      }
      return;
    }
    final r = Map<String, dynamic>.from(await Api.i.get('/v1/threads/$key/messages'));
    final t = thread(key);
    t.messages
      ..clear()
      ..addAll((r['messages'] as List).cast<Map<String, dynamic>>().map((m) => ChatMessage(
            id: '${m['id']}',
            mine: m['from'] == 'customer',
            author: m['from'] == 'customer' ? 'You' : '${m['authorName'] ?? 'Aura'}',
            text: '${m['text'] ?? ''}',
            at: DateTime.parse('${m['at']}').toLocal(),
            imageUrl: m['imageUrl'] as String?,
            seen: m['from'] == 'customer' ? m['readByStaff'] == true : true,
          )));
    t.serverUnread = 0;
    notifyListeners();
  }

  // ---- bookings (live)

  /// Books the draft. Live: in the branch diary, as "pending" until paid or confirmed.
  Future<Appointment> createBooking({required int total}) async {
    if (!live) return confirmBooking(total: total);
    final b = booking;
    final r = Map<String, dynamic>.from(await Api.i.post('/v1/bookings', {
      'shopId': b.branchId ?? selectedBranchId,
      'serviceIds': b.serviceIds,
      'staffId': b.stylistId ?? 'any',
      'startAt': b.startAt ?? '',
      'notes': b.notes,
      if (b.promo != null) 'couponCode': b.promo,
    }));
    final appt = appointmentFromJson(Map<String, dynamic>.from(r['booking']));
    appointments.insert(0, appt);
    // The draft is cleared by the booking screen once it moves on.
    notifyListeners();
    return appt;
  }

  Future<void> cancelBooking(Appointment a, String reason) async {
    if (!live) return cancelAppointment(a, reason);
    await Api.i.post('/v1/bookings/${a.id}/cancel', {'reason': reason});
    await refreshBookings();
  }

  Future<void> moveBooking(Appointment a, DateTime date, String time, {String? startAt}) async {
    if (!live) return reschedule(a, date, time);
    await Api.i.post('/v1/bookings/${a.id}/reschedule', {'startAt': startAt ?? ''});
    await refreshBookings();
  }

  Future<void> reviewBooking(Appointment a, int stars, String text) async {
    if (!live) {
      rate(a, stars, text);
      update(() => loyaltyPoints += 50);
      return;
    }
    await Api.i.post('/v1/bookings/${a.id}/review', {'rating': stars, 'comment': text});
    await refreshBookings();
  }

  Future<BridalBooking> bookBridal({required String shopId, required String packageId, required List<Map<String, String>> events, String location = 'salon', String venue = '', String notes = ''}) async {
    final r = Map<String, dynamic>.from(await Api.i.post('/v1/bridal', {'shopId': shopId, 'packageId': packageId, 'events': events, 'location': location, 'venue': venue, 'notes': notes}));
    final b = BridalBooking(Map<String, dynamic>.from(r['bridal']));
    bridal.insert(0, b);
    notifyListeners();
    return b;
  }

  // ---- payments (live)

  /// Creates a payment on the server. Returns the payment and, for wallets and
  /// cards, the address of the secure checkout page to open.
  Future<Map<String, dynamic>> createPayment({required String purpose, String? refId, required String plan, num? amount, required String method, Map<String, dynamic>? voucher}) async {
    return Map<String, dynamic>.from(await Api.i.post('/v1/payments', {
      'purpose': purpose,
      'refId': ?refId,
      'plan': plan,
      'amount': ?amount,
      'method': method,
      'voucher': ?voucher,
    }));
  }

  Future<Map<String, dynamic>> paymentStatus(String id) async => Map<String, dynamic>.from((await Api.i.get('/v1/payments/$id'))['payment']);

  Future<Map<String, dynamic>> uploadSlip(String id, List<int> bytes, String filename, String note) async =>
      Map<String, dynamic>.from((await Api.i.upload('/v1/payments/$id/slip', bytes: bytes, filename: filename, fields: {'note': note}))['payment']);

  /// After a payment: the booking, wallet and receipts all change.
  Future<void> afterPayment() async {
    try {
      await Future.wait([refreshBookings(), refreshWallet(), refreshInvoices()]);
    } on ApiException {
      // Shown again on the next pull-to-refresh.
    }
  }

  // ---- profile (live)

  Future<void> saveProfile() async {
    if (!live) {
      update(() {});
      return;
    }
    final skin = profile.skinNotes.split('|');
    final r = Map<String, dynamic>.from(await Api.i.put('/v1/me', {
      'name': profile.name,
      if (profile.phone.isNotEmpty) 'phone': profile.phone,
      if (profile.birthday != null) 'birthday': profile.birthday!.toIso8601String().substring(0, 10),
      'allergies': profile.allergies,
      'skinType': skin.first,
      'notes': skin.length > 1 ? skin.sublist(1).join('|') : '',
    }));
    profileComplete = r['profileComplete'] == true;
    _save();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    if (live) await Api.i.delete('/v1/me');
    await signOutAsync();
  }

  Future<void> signOutAsync() async {
    if (live) await AuthService.i.signOut();
    update(() {
      authed = false;
      guest = false;
      _clearAccount();
    });
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setBool('onboarded', onboarded);
    p.setBool('authed', authed);
    p.setBool('guest', guest);
    p.setString('lang', lang);
    p.setString('name', profile.name);
    p.setString('email', profile.email);
    p.setString('phone', profile.phone);
    p.setString('skin', profile.skinNotes);
    p.setString('allergies', profile.allergies);
  }

  void update(VoidCallback change) {
    change();
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------- auth

  void finishOnboarding() => update(() => onboarded = true);

  void signIn({required String name, String email = '', String phone = ''}) => update(() {
        authed = true;
        guest = false;
        profile.name = name;
        if (email.isNotEmpty) profile.email = email;
        if (phone.isNotEmpty) profile.phone = phone;
      });

  void continueAsGuest() => update(() {
        authed = true;
        guest = true;
      });

  void signOut() => update(() {
        authed = false;
        guest = false;
      });

  void setLang(String l) => update(() => lang = l);

  // ------------------------------------------------------------- loyalty

  String get tier => loyaltyPoints >= 5000 ? 'Platinum' : loyaltyPoints >= 2000 ? 'Gold' : 'Silver';
  int get nextTierAt => loyaltyPoints >= 5000 ? 5000 : loyaltyPoints >= 2000 ? 5000 : 2000;

  // ------------------------------------------------------------- bookings

  Appointment? get nextAppointment {
    final up = appointments.where((a) => a.status == ApptStatus.upcoming).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return up.isEmpty ? null : up.first;
  }

  String _id(String prefix) => '$prefix-${10000 + Random().nextInt(89999)}';

  Appointment confirmBooking({required int total, PaymentRecord? payment}) {
    final b = booking;
    final appt = Appointment(
      id: _id('APT'),
      status: ApptStatus.upcoming,
      branchId: b.branchId ?? selectedBranchId,
      serviceIds: List.of(b.serviceIds),
      stylistId: b.stylistId == null || b.stylistId == 'any' ? 'st-amna' : b.stylistId!,
      date: b.date ?? DateTime.now(),
      time: b.time ?? '12:30',
      total: total,
      paid: payment?.amount ?? 0,
      paidBy: payment?.reference,
      notes: b.notes,
    );
    update(() {
      appointments.insert(0, appt);
      loyaltyPoints += (total / 100).floor();
      b.clear();
    });
    return appt;
  }

  void cancelAppointment(Appointment a, String reason) => update(() {
        a.status = ApptStatus.cancelled;
        a.cancelReason = reason;
      });

  void reschedule(Appointment a, DateTime date, String time) => update(() {
        a.date = date;
        a.time = time;
      });

  void rate(Appointment a, int stars, String review) => update(() {
        a.rating = stars;
        a.review = review;
      });

  void payBalance(Appointment a, PaymentRecord p) => update(() {
        a.paid += p.amount;
        a.paidBy = p.reference;
      });

  // ------------------------------------------------------------- payments

  PaymentRecord recordPayment({required int amount, required PayMethod method, required String purpose, required String reference, String status = 'paid'}) {
    final rec = PaymentRecord(
      id: 'PAY-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      at: DateTime.now(),
      amount: amount,
      method: method,
      purpose: purpose,
      status: status,
      reference: reference,
    );
    update(() => payments.insert(0, rec));
    return rec;
  }

  Voucher addVoucher(int value, String recipient) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    final code = 'GV-${List.generate(6, (_) => chars[r.nextInt(chars.length)]).join()}';
    final v = Voucher(code, value, recipient, DateTime.now());
    update(() => vouchers.insert(0, v));
    return v;
  }

  void saveMethod(PayMethod m, String label) {
    if (savedMethods.any((s) => s.label == label)) return;
    update(() => savedMethods.add(SavedMethod('sm${savedMethods.length + 1}', m, label)));
  }

  void removeMethod(SavedMethod s) => update(() => savedMethods.remove(s));

  void makeDefault(SavedMethod s) => update(() {
        for (final x in savedMethods) {
          x.isDefault = x == s;
        }
      });

  // ------------------------------------------------------------- messages

  int unread([String? threadId]) {
    if (live) {
      return threads.where((t) => threadId == null || t.id == threadId).fold(0, (n, t) => n + (t.kind == ThreadKind.announcements ? announcementsUnread : t.serverUnread));
    }
    var n = 0;
    for (final t in threads) {
      if (threadId != null && t.id != threadId) continue;
      final seen = readAt[t.id];
      n += t.messages.where((m) => !m.mine && (seen == null || m.at.isAfter(seen))).length;
    }
    return n;
  }

  void markRead(String threadId) {
    readAt[threadId] = DateTime.now();
    notifyListeners();
  }

  Thread thread(String id) => threads.firstWhere((t) => t.id == id);

  String startThread(ThreadKind kind, {String? branchId}) {
    if (live) {
      final key = kind == ThreadKind.concierge || branchId == null ? 'hq' : branchId;
      if (!threads.any((t) => t.id == key)) {
        final b = branchId == null ? null : branchById(branchId);
        threads.add(Thread(id: key, kind: key == 'hq' ? ThreadKind.concierge : ThreadKind.branch, title: b?.name ?? 'Aura Concierge', subtitle: b == null ? 'Head office · bridal, packages & feedback' : b.address, branchId: b?.id));
      }
      return key;
    }
    for (final t in threads) {
      if (t.kind == kind && t.branchId == branchId) return t.id;
    }
    final b = branchId == null ? null : branchById(branchId);
    final t = Thread(
      id: 'th-${kind.name}-${branchId ?? 'hq'}',
      kind: kind,
      title: b?.name ?? 'Aura Concierge',
      subtitle: b == null ? 'Head office' : 'Front desk',
      branchId: branchId,
    );
    update(() => threads.add(t));
    return t.id;
  }

  Future<void> sendMessage(String threadId, String text, {List<int>? imageBytes, String filename = 'photo.jpg'}) async {
    final t = thread(threadId);
    if (live) {
      if (imageBytes != null) {
        await Api.i.upload('/v1/threads/$threadId/photo', bytes: imageBytes, filename: filename, fields: {'text': text.trim()});
      } else {
        await Api.i.post('/v1/threads/$threadId/messages', {'text': text.trim()});
      }
      await loadMessages(threadId);
      return;
    }
    final msg = ChatMessage(id: 'm${DateTime.now().microsecondsSinceEpoch}', mine: true, author: 'You', text: text.trim(), at: DateTime.now(), imageBytes: imageBytes);
    update(() {
      t.messages.add(msg);
      readAt[threadId] = msg.at;
    });
    // Demo only: a friendly acknowledgement so the conversation feels alive.
    Timer(const Duration(milliseconds: 1600), () {
      t.messages.add(ChatMessage(
        id: 'r${DateTime.now().microsecondsSinceEpoch}',
        mine: false,
        author: t.kind == ThreadKind.branch ? 'Front desk' : 'Hira (Concierge)',
        text: 'Thank you for your message! 🌸 Our team will reply shortly — usually within 15 minutes during salon hours.',
        at: DateTime.now(),
      ));
      notifyListeners();
    });
  }
}
