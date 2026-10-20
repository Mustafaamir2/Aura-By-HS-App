import '../data/mock_data.dart';
import 'api.dart';

/// Turns the Aura API's JSON into the app's models. The catalogue replaces the
/// built-in lists (branches, services, stylists, packages, offers) in place, so
/// every screen shows the salon's real menu without knowing where it came from.

// ----------------------------------------------------------------- config

class PayConfig {
  PayConfig({this.enabled = true, this.methods = const ['jazzcash', 'easypaisa', 'card', 'bank-transfer'], this.advancePct = 20, this.bridalAdvancePct = 30, this.minPartial = 500, this.bank = const {}});
  final bool enabled;
  final List<String> methods;
  final num advancePct, bridalAdvancePct, minPartial;
  final Map<String, String> bank;

  factory PayConfig.fromJson(Map<String, dynamic> j) => PayConfig(
        enabled: j['enabled'] != false,
        methods: List<String>.from(j['methods'] ?? const []),
        advancePct: j['advancePct'] ?? 20,
        bridalAdvancePct: j['bridalAdvancePct'] ?? 30,
        minPartial: j['minPartial'] ?? 500,
        bank: {for (final e in Map<String, dynamic>.from(j['bank'] ?? const {}).entries) e.key: '${e.value ?? ''}'},
      );
}

class AppLinks {
  AppLinks({this.playStoreUrl = '', this.appStoreUrl = '', this.websiteUrl = '', this.whatsapp = ''});
  final String playStoreUrl, appStoreUrl, websiteUrl, whatsapp;
  factory AppLinks.fromJson(Map<String, dynamic> j) => AppLinks(
        playStoreUrl: '${j['playStoreUrl'] ?? ''}',
        appStoreUrl: '${j['appStoreUrl'] ?? ''}',
        websiteUrl: '${j['websiteUrl'] ?? ''}',
        whatsapp: '${j['whatsapp'] ?? ''}',
      );
}

class Announcement {
  Announcement(this.id, this.title, this.body, this.imageUrl, this.at);
  final String id, title, body;
  final String? imageUrl;
  final DateTime at;
}

// ---------------------------------------------------------------- catalogue

Cat catFor(String id, String name) {
  final s = '$id $name'.toLowerCase();
  if (s.contains('bridal') || s.contains('bride')) return Cat.bridal;
  if (s.contains('party') || s.contains('event') || s.contains('make')) return Cat.makeup;
  if (s.contains('hair')) return Cat.hair;
  if (s.contains('skin') || s.contains('facial')) return Cat.skin;
  if (s.contains('nail')) return Cat.nails;
  if (s.contains('mehndi') || s.contains('henna')) return Cat.mehndi;
  if (s.contains('photo') || s.contains('studio')) return Cat.photography;
  return Cat.salon;
}

const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String _timings(List hours) {
  final today = DateTime.now().weekday % 7; // Sunday = 0, like the POS
  final h = hours.cast<Map>().where((x) => x['weekday'] == today).firstOrNull;
  if (h == null || h['closed'] == true) return 'Closed today (${_weekdays[today]})';
  return '${fmtTime('${h['open']}')} – ${fmtTime('${h['close']}')}';
}

class CatalogExtras {
  CatalogExtras({required this.pay, required this.links, required this.announcements, required this.businessName, required this.cancelHours, required this.pointValue});
  final PayConfig pay;
  final AppLinks links;
  final List<Announcement> announcements;
  final String businessName;
  final num cancelHours;
  final num pointValue;
}

CatalogExtras applyCatalog(Map<String, dynamic> j) {
  final cats = <String, Cat>{
    for (final c in (j['categories'] as List? ?? const []).cast<Map<String, dynamic>>()) '${c['id']}': catFor('${c['id']}', '${c['name']}'),
  };

  branches
    ..clear()
    ..addAll((j['shops'] as List? ?? const []).cast<Map<String, dynamic>>().map((s) => Branch(
          id: '${s['id']}',
          name: '${s['name']}',
          city: '${s['city'] ?? ''}',
          address: [s['addressLine'], s['city']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
          timings: _timings(s['businessHours'] as List? ?? const []),
          isOpenNow: s['isOpenNow'] == true,
          phone: '${s['phone'] ?? ''}',
          lat: 0,
          lng: 0,
        )));

  final svc = (j['services'] as List? ?? const []).cast<Map<String, dynamic>>();
  services
    ..clear()
    ..addAll(svc.map((s) {
      final price = (s['price'] as num) * (1 - ((s['discountPct'] ?? 0) as num) / 100);
      return Service(
        id: '${s['id']}',
        cat: cats['${s['categoryId']}'] ?? catFor('', '${s['name']}'),
        name: '${s['name']}',
        minutes: (s['durationMin'] as num).toInt(),
        price: price.round(),
        description: '${s['description'] ?? ''}',
      );
    }));

  final svcCat = {for (final s in services) s.id: s.cat};
  stylists
    ..clear()
    ..addAll((j['staff'] as List? ?? const []).cast<Map<String, dynamic>>().map((s) => Stylist(
          '${s['id']}',
          '${s['name']}',
          '${s['role'] ?? ''}',
          {for (final id in (s['specializations'] as List? ?? const [])) svcCat['$id']}.whereType<Cat>().toList(),
          ((s['rating'] ?? 0) as num).toDouble(),
          ((s['reviews'] ?? 0) as num).toInt(),
          ['${s['shopId']}'],
        )));

  const pics = ['bridal-makeup', 'hair', 'mehndi', 'party-makeup'];
  final pk = (j['packages'] as List? ?? const []).cast<Map<String, dynamic>>();
  packages
    ..clear()
    ..addAll([
      for (var i = 0; i < pk.length; i++)
        () {
          final d = '${pk[i]['description'] ?? ''}';
          final parts = d.split(' — ');
          final includes = (parts.length > 1 ? parts.sublist(1).join(' — ') : d).split(RegExp(r',\s*')).map((x) => x.trim().replaceAll(RegExp(r'\.$'), '')).where((x) => x.isNotEmpty).toList();
          return BridalPackage('${pk[i]['id']}', '${pk[i]['name']}', parts.length > 1 ? parts.first : '', (pk[i]['price'] as num).round(), includes, '$img/${pics[i % pics.length]}.jpg');
        }(),
    ]);

  final today = DateTime.now();
  offers
    ..clear()
    ..addAll((j['offers'] as List? ?? const []).cast<Map<String, dynamic>>().map((c) {
      final ends = c['endsOn'] == null ? null : DateTime.tryParse('${c['endsOn']}');
      final pct = c['mode'] == 'percent';
      final value = (c['value'] as num).round();
      final min = ((c['minSpend'] ?? 0) as num).round();
      return Offer(
        '${c['id']}',
        '${c['code']}',
        '${c['name'] ?? ''}'.isNotEmpty ? '${c['name']}' : (pct ? '$value% off' : '${rs(value)} off'),
        [if (min > 0) 'On bills of ${rs(min)} or more.' else 'On any booking.', if (ends != null) 'Valid until ${fmtDateLong(ends)}.'].join(' '),
        ends == null ? 30 : ends.difference(today).inDays.clamp(0, 999),
        pct: pct ? value : 0,
        flat: pct ? 0 : value,
        minSpend: min,
      );
    }));

  final ann = (j['announcements'] as List? ?? const []).cast<Map<String, dynamic>>();
  return CatalogExtras(
    pay: PayConfig.fromJson(Map<String, dynamic>.from(j['payments'] ?? const {})),
    links: AppLinks.fromJson(Map<String, dynamic>.from(j['app'] ?? const {})),
    announcements: [for (final a in ann) Announcement('${a['id']}', '${a['title']}', '${a['body'] ?? ''}', a['imageUrl'] as String?, DateTime.tryParse('${a['createdAt']}')?.toLocal() ?? today)],
    businessName: '${(j['business'] ?? const {})['name'] ?? 'Aura by HS'}',
    cancelHours: (j['rules'] ?? const {})['cancellationWindowHours'] ?? 4,
    pointValue: (j['loyalty'] ?? const {})['pointValue'] ?? 1,
  );
}

// ------------------------------------------------------------------ bookings

/// The salons are in Pakistan (UTC+5, no daylight saving). Booking times are
/// shown in salon time on every phone, even one set to another time zone.
const salonOffset = Duration(hours: 5);

DateTime salonTime(String iso) {
  final u = DateTime.parse(iso).toUtc().add(salonOffset);
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

ApptStatus _bucket(String s) => switch (s) {
      'cancelled' => ApptStatus.cancelled,
      'completed' || 'no-show' => ApptStatus.past,
      _ => ApptStatus.upcoming,
    };

Appointment appointmentFromJson(Map<String, dynamic> j) {
  final start = salonTime('${j['startAt']}');
  final svcs = (j['services'] as List? ?? const []).cast<Map<String, dynamic>>();
  final review = j['review'] as Map<String, dynamic>?;
  final pays = (j['payments'] as List? ?? const []).cast<Map<String, dynamic>>().where((p) => p['status'] == 'paid').toList();
  return Appointment(
    id: '${j['id']}',
    status: _bucket('${j['status']}'),
    rawStatus: '${j['status']}',
    branchId: '${j['shopId']}',
    serviceIds: [for (final s in svcs) '${s['serviceId']}'],
    serviceNames: [for (final s in svcs) '${s['name']}'],
    stylistId: '${j['staffId'] ?? ''}',
    staffName: '${j['staffName'] ?? ''}',
    shopName: '${j['shopName'] ?? ''}',
    date: DateTime(start.year, start.month, start.day),
    time: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
    total: ((j['total'] ?? 0) as num).round(),
    paid: ((j['paid'] ?? 0) as num).round(),
    paidBy: pays.isEmpty ? null : _methodLabel('${pays.last['method']}'),
    notes: '${j['notes'] ?? ''}',
    rating: review == null ? null : (review['rating'] as num).toInt(),
    review: review?['comment'] as String?,
    cancelReason: j['cancelReason'] as String?,
    canCancel: j['canCancel'] == true,
    canPay: j['canPay'] == true,
    canReview: j['canReview'] == true,
    receiptNo: j['receiptNo'] as String?,
  );
}

String _methodLabel(String m) => switch (m) {
      'jazzcash' => 'JazzCash',
      'easypaisa' => 'Easypaisa',
      'card' => 'Card',
      'bank-transfer' => 'Bank transfer',
      'cash' => 'Cash',
      _ => m,
    };

String methodLabel(String m) => _methodLabel(m);

class BridalBooking {
  BridalBooking(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get bookingNo => '${j['bookingNo'] ?? ''}';
  String get packageName => '${j['packageName'] ?? 'Bridal booking'}';
  String get shopName => '${j['shopName'] ?? ''}';
  String get status => '${j['status']}';
  int get total => ((j['total'] ?? 0) as num).round();
  int get paid => ((j['paid'] ?? 0) as num).round();
  int get due => ((j['due'] ?? 0) as num).round();
  int get advanceDue => ((j['advanceDue'] ?? 0) as num).round();
  bool get canPay => j['canPay'] == true;
  List<Map<String, dynamic>> get events => (j['events'] as List? ?? const []).cast<Map<String, dynamic>>();
  bool get verifying => (j['onlinePayments'] as List? ?? const []).any((p) => p['status'] == 'verifying');
}

class Invoice {
  Invoice(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get receiptNo => '${j['receiptNo']}';
  DateTime get at => DateTime.parse('${j['soldAt']}').toLocal();
  String get shopName => '${j['shopName'] ?? ''}';
  String get shopAddress => '${j['shopAddress'] ?? ''}';
  int get total => ((j['total'] ?? 0) as num).round();
  int get balanceDue => ((j['balanceDue'] ?? 0) as num).round();
  String get status => '${j['status']}';
  int get pointsEarned => ((j['pointsEarned'] ?? 0) as num).round();
  List<Map<String, dynamic>> get items => (j['items'] as List? ?? const []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get payments => (j['payments'] as List? ?? const []).cast<Map<String, dynamic>>();
  num get discount => ((j['itemDiscountTotal'] ?? 0) as num) + ((j['billDiscount'] ?? 0) as num) + ((j['membershipDiscount'] ?? 0) as num);
  num get tax => (j['taxAmount'] ?? 0) as num;
}

class Slot {
  Slot(this.time, this.startAt, this.available, this.reason);
  final String time, startAt;
  final bool available;
  final String? reason;
}

Future<List<Slot>> fetchSlots({required String shopId, required DateTime day, required List<String> serviceIds, String? staffId, String? exclude}) async {
  final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  final r = await Api.i.get('/v1/availability', {
    'shopId': shopId,
    'date': d,
    'serviceIds': serviceIds.join(','),
    if (staffId != null && staffId != 'any') 'staffId': staffId,
    'excludeAppointmentId': ?exclude,
  });
  return [for (final s in (r['slots'] as List).cast<Map<String, dynamic>>()) Slot('${s['time']}', '${s['startAt']}', s['available'] == true, s['reasonLabel'] as String?)];
}
