/// Catalogue and sample content. In demo mode (no servers configured) the app
/// runs on these lists; when connected, they are replaced by the live catalogue
/// from the Aura API (see services/live.dart) — the screens read the same lists.
library;

class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.timings,
    required this.isOpenNow,
    required this.phone,
    required this.lat,
    required this.lng,
  });
  final String id, name, city, address, timings, phone;
  final bool isOpenNow;
  final double lat, lng;
}

final branches = <Branch>[
  Branch(id: 'gulberg', name: 'Aura Gulberg', city: 'Lahore', address: '14-C, MM Alam Road, Gulberg III, Lahore', timings: '11:00 AM – 9:00 PM', isOpenNow: true, phone: '+924235771420', lat: 31.5204, lng: 74.3587),
  Branch(id: 'dha', name: 'Aura DHA Phase 6', city: 'Lahore', address: '12-C, Main Boulevard, DHA Phase 6, Lahore', timings: '11:00 AM – 9:00 PM', isOpenNow: true, phone: '+924235771421', lat: 31.4697, lng: 74.4142),
  Branch(id: 'clifton', name: 'Aura Clifton', city: 'Karachi', address: 'Shop 5, Block 4, Khayaban-e-Roomi, Clifton, Karachi', timings: '12:00 PM – 10:00 PM', isOpenNow: false, phone: '+922135306611', lat: 24.8138, lng: 67.0299),
  Branch(id: 'f7', name: 'Aura F-7 Markaz', city: 'Islamabad', address: 'Jinnah Super, F-7 Markaz, Islamabad', timings: '11:00 AM – 9:00 PM', isOpenNow: true, phone: '+92512650990', lat: 33.7177, lng: 73.0583),
  Branch(id: 'bahria', name: 'Aura Bahria Town', city: 'Rawalpindi', address: 'Civic Center, Phase 4, Bahria Town, Rawalpindi', timings: '11:00 AM – 8:00 PM', isOpenNow: true, phone: '+92515730990', lat: 33.5651, lng: 73.1348),
];

enum Cat { bridal, makeup, salon, hair, skin, nails, mehndi, photography }

class Category {
  const Category(this.id, this.label, this.labelUr, this.image, this.from, this.blurb);
  final Cat id;
  final String label, labelUr, image, blurb;
  final int from;
}

const String img = 'assets/images';

/// The eight disciplines from aurabyhs.
const categories = <Category>[
  Category(Cat.bridal, 'Bridal Make-Up', 'برائیڈل میک اپ', '$img/bridal-makeup.jpg', 45000, 'Signature HD bridal artistry crafted for your biggest day.'),
  Category(Cat.makeup, 'Party Make-Up', 'پارٹی میک اپ', '$img/party-makeup.jpg', 8000, 'Engagements, mehndi guests, dinners and shoots.'),
  Category(Cat.salon, 'Salon Services', 'سیلون سروسز', '$img/salon.jpg', 1200, 'Everyday luxury — grooming, threading, waxing and polish.'),
  Category(Cat.hair, 'Hair Styling', 'ہیئر اسٹائلنگ', '$img/hair.jpg', 3500, 'Editorial updos, blowouts and event-ready styling.'),
  Category(Cat.skin, 'Skin & Facial', 'اسکن اور فیشل', '$img/facial.jpg', 6500, 'Glow protocols and facials for flawless bridal skin.'),
  Category(Cat.nails, 'Nails', 'نیلز', '$img/nails.jpg', 3000, 'Manicures, pedicures, gel and nail art.'),
  Category(Cat.mehndi, 'Mehndi', 'مہندی', '$img/mehndi.jpg', 2500, 'Bridal and guest mehndi artistry.'),
  Category(Cat.photography, 'Photography Studio', 'فوٹوگرافی اسٹوڈیو', '$img/studio.jpg', 10000, 'Bridal portraits and studio sessions.'),
];

/// Categories that have at least one service on the current menu.
List<Category> get menuCategories => categories.where((c) => services.any((s) => s.cat == c.id)).toList();

Category categoryOf(Cat id) => categories.firstWhere((c) => c.id == id);

class AddOn {
  const AddOn(this.id, this.name, this.price);
  final String id, name;
  final int price;
}

class Service {
  const Service({
    required this.id,
    required this.cat,
    required this.name,
    required this.minutes,
    required this.price,
    required this.description,
    this.priceFrom = false,
    this.addOns = const [],
    this.popular = false,
  });
  final String id, name, description;
  final Cat cat;
  final int minutes, price;
  final bool priceFrom, popular;
  final List<AddOn> addOns;
  String get image => categoryOf(cat).image;
}

final services = <Service>[
  Service(id: 'svc-bridal-sig', cat: Cat.bridal, name: 'Signature Bridal Make-Up', minutes: 240, price: 45000, priceFrom: true, popular: true, description: 'Full bridal look with lashes and dupatta draping by our senior artist.', addOns: [AddOn('ao-trial', 'Bridal trial session', 10000), AddOn('ao-family', 'Family member make-up', 8000)]),
  Service(id: 'svc-bridal-hd', cat: Cat.bridal, name: 'HD Bridal Make-Up', minutes: 240, price: 60000, priceFrom: true, description: 'High-definition finish made for close-up photography and video.', addOns: [AddOn('ao-trial', 'Bridal trial session', 10000)]),
  Service(id: 'svc-bridal-air', cat: Cat.bridal, name: 'Airbrush Bridal Make-Up', minutes: 270, price: 75000, priceFrom: true, description: 'Weightless, long-wear airbrush base that lasts from nikah to rukhsati.', addOns: [AddOn('ao-trial', 'Bridal trial session', 10000)]),
  Service(id: 'svc-bridal-trial', cat: Cat.bridal, name: 'Bridal Trial', minutes: 120, price: 10000, description: 'Try your look before the wedding — adjusted until it is perfect.'),
  Service(id: 'svc-party', cat: Cat.makeup, name: 'Party Make-Up', minutes: 90, price: 12000, popular: true, description: 'Full glam with long-wear base for events and dinners.', addOns: [AddOn('ao-lashes', 'Mink lashes', 1500)]),
  Service(id: 'svc-engagement', cat: Cat.makeup, name: 'Engagement / Nikah Make-Up', minutes: 150, price: 25000, description: 'Soft-glam look for engagement or nikah with hair styling.', addOns: [AddOn('ao-lashes', 'Mink lashes', 1500)]),
  Service(id: 'svc-family', cat: Cat.makeup, name: 'Family Member Make-Up', minutes: 75, price: 8000, description: 'Make-up for the bride’s mother, sisters and friends.'),
  Service(id: 'svc-thread', cat: Cat.salon, name: 'Threading (Full Face)', minutes: 20, price: 1200, description: 'Eyebrows, upper lip and full face.'),
  Service(id: 'svc-wax', cat: Cat.salon, name: 'Full Body Waxing', minutes: 90, price: 6500, description: 'Gentle rica wax, suitable for sensitive skin.'),
  Service(id: 'svc-groom', cat: Cat.salon, name: 'Grooming & Polish', minutes: 60, price: 3500, description: 'Cleanup, threading and polish in one visit.'),
  Service(id: 'svc-cut', cat: Cat.hair, name: 'Haircut & Blow-Dry', minutes: 60, price: 3500, popular: true, description: 'Precision cut finished with a blow-dry styled to your face shape.', addOns: [AddOn('ao-scalp', 'Scalp massage', 800)]),
  Service(id: 'svc-style', cat: Cat.hair, name: 'Event Hair Styling', minutes: 60, price: 8000, description: 'Curls, waves or sleek styling for your event.'),
  Service(id: 'svc-updo', cat: Cat.hair, name: 'Bridal Updo & Draping', minutes: 90, price: 12000, description: 'Editorial updo with dupatta setting and accessories.'),
  Service(id: 'svc-colour', cat: Cat.hair, name: 'Hair Colour', minutes: 150, price: 15000, priceFrom: true, description: 'Global colour, balayage or highlights with bond protection.'),
  Service(id: 'svc-keratin', cat: Cat.hair, name: 'Keratin Treatment', minutes: 180, price: 25000, priceFrom: true, description: 'Frizz-free smoothening for all hair lengths.', addOns: [AddOn('ao-serum', 'Finishing serum', 1500)]),
  Service(id: 'svc-glow', cat: Cat.skin, name: 'Glow Facial', minutes: 60, price: 6500, popular: true, description: 'Brightening facial for an instant glow.'),
  Service(id: 'svc-hydra', cat: Cat.skin, name: 'Hydra Facial', minutes: 75, price: 12000, description: 'Deep cleanse, extraction and hydration.'),
  Service(id: 'svc-prebridal', cat: Cat.skin, name: 'Pre-Bridal Facial', minutes: 90, price: 15000, description: 'One session of the pre-bridal skin programme.'),
  Service(id: 'svc-mani', cat: Cat.nails, name: 'Manicure', minutes: 45, price: 3000, description: 'Shaping, cuticle care, hand massage and polish.', addOns: [AddOn('ao-gel', 'Gel polish upgrade', 1500)]),
  Service(id: 'svc-pedi', cat: Cat.nails, name: 'Pedicure', minutes: 60, price: 3500, description: 'Soak, scrub, massage and polish.', addOns: [AddOn('ao-gel', 'Gel polish upgrade', 1500)]),
  Service(id: 'svc-gel', cat: Cat.nails, name: 'Gel Polish / Nail Art', minutes: 60, price: 4500, description: 'Long-lasting gel colour or custom nail art.'),
  Service(id: 'svc-mehndi-bridal', cat: Cat.mehndi, name: 'Bridal Mehndi (Hands & Feet)', minutes: 240, price: 25000, priceFrom: true, description: 'Intricate bridal mehndi by our in-house artist.'),
  Service(id: 'svc-mehndi-guest', cat: Cat.mehndi, name: 'Guest Mehndi (per hand)', minutes: 30, price: 2500, description: 'Elegant design for guests and family.'),
  Service(id: 'svc-portrait', cat: Cat.photography, name: 'Bridal Studio Portraits', minutes: 120, price: 30000, description: 'Studio session with edited portraits delivered in 7 days.', addOns: [AddOn('ao-album', 'Printed album (30 pages)', 12000)]),
  Service(id: 'svc-mini', cat: Cat.photography, name: 'Mini Studio Session', minutes: 45, price: 10000, description: 'Short portrait session — perfect for birthdays and couples.'),
];

Service? serviceById(String id) {
  for (final s in services) {
    if (s.id == id) return s;
  }
  return null;
}

class Stylist {
  const Stylist(this.id, this.name, this.role, this.specialties, this.rating, this.reviews, this.branchIds);
  final String id, name, role;
  final List<Cat> specialties;
  final double rating;
  final int reviews;
  final List<String> branchIds;
}

final stylists = <Stylist>[
  Stylist('st-amna', 'Amna Khalid', 'Lead Bridal Artist', [Cat.bridal, Cat.makeup], 4.9, 312, ['gulberg', 'dha']),
  Stylist('st-sana', 'Sana Tariq', 'Senior Hair Stylist', [Cat.hair, Cat.salon], 4.8, 198, ['gulberg', 'dha', 'f7']),
  Stylist('st-fatima', 'Fatima Noor', 'Skin Therapist', [Cat.skin, Cat.salon, Cat.nails], 4.7, 150, ['clifton', 'bahria', 'gulberg']),
  Stylist('st-hira', 'Hira Shahzad', 'Mehndi Artist', [Cat.mehndi], 5.0, 87, ['gulberg', 'dha', 'f7']),
  Stylist('st-zara', 'Zara Ahmed', 'Make-Up Artist', [Cat.makeup, Cat.bridal], 4.8, 140, ['clifton', 'f7', 'bahria']),
  Stylist('st-usman', 'Usman Raza', 'Photographer', [Cat.photography], 4.9, 210, ['gulberg', 'dha', 'clifton', 'f7', 'bahria']),
];

Stylist? stylistById(String id) {
  for (final s in stylists) {
    if (s.id == id) return s;
  }
  return null;
}

Branch? branchById(String id) {
  for (final b in branches) {
    if (b.id == id) return b;
  }
  return null;
}

class BridalPackage {
  const BridalPackage(this.id, this.name, this.occasion, this.price, this.includes, this.image, {this.popular = false});
  final String id, name, occasion, image;
  final int price;
  final List<String> includes;
  final bool popular;
  int get deposit => (price * 0.3).round();
}

/// The four bridal packages exactly as published on aurabyhs.
final packages = <BridalPackage>[
  BridalPackage('pkg-essential', 'Bride Essential', 'Single event · 4 hrs', 55000, ['Signature bridal make-up', 'Hair styling & draping', 'Basic skin prep', 'Lashes included'], '$img/bridal-makeup.jpg'),
  BridalPackage('pkg-signature', 'Bride Signature', 'Two events · 1 day', 95000, ['HD bridal make-up', 'Advanced hair styling', 'Pre-bridal facial', 'Manicure & pedicure', 'Trial session'], '$img/hair.jpg'),
  BridalPackage('pkg-royal', 'Bride Royal', 'Three events · 2 days', 165000, ['Airbrush bridal make-up', 'Mehndi & Baraat looks', 'Bridal mehndi artistry', '3-session skin programme', 'Nails & grooming'], '$img/mehndi.jpg'),
  BridalPackage('pkg-premium', 'Aura Premium', 'Full wedding week', 245000, ['All four events covered', 'Lead artist personally', 'Full pre-bridal programme', 'Bridal mehndi & nails', 'Studio portrait session', 'Dedicated coordinator'], '$img/party-makeup.jpg', popular: true),
];

class Offer {
  const Offer(this.id, this.code, this.title, this.description, this.daysLeft, {this.pct = 0, this.flat = 0, this.minSpend = 0});
  final String id, code, title, description;
  final int daysLeft, pct, flat, minSpend;
  int discountOn(int subtotal) {
    if (subtotal < minSpend) return 0;
    return pct > 0 ? (subtotal * pct / 100).round() : (flat > subtotal ? subtotal : flat);
  }
}

final offers = <Offer>[
  Offer('off-welcome', 'AURA15', '15% off your first booking', 'Valid on all services for new customers.', 20, pct: 15),
  Offer('off-bridal', 'BRIDE2026', 'Rs 5,000 off bridal packages', 'On bookings above Rs 50,000.', 45, flat: 5000, minSpend: 50000),
  Offer('off-weekday', 'WEEKDAY10', '10% off weekday visits', 'Monday to Thursday appointments only.', 10, pct: 10),
  Offer('off-glow', 'GLOW20', '20% off facials', 'Any Skin & Facial service this month.', 25, pct: 20),
];

class GalleryItem {
  const GalleryItem(this.id, this.cat, this.before, this.after, this.stylistId, this.caption);
  final String id, before, after, stylistId, caption;
  final Cat cat;
}

const gallery = <GalleryItem>[
  GalleryItem('g1', Cat.bridal, '$img/facial.jpg', '$img/bride-hero.jpg', 'st-amna', 'Barat look — Amna'),
  GalleryItem('g2', Cat.makeup, '$img/party-makeup.jpg', '$img/bridal-makeup.jpg', 'st-zara', 'Soft glam'),
  GalleryItem('g3', Cat.hair, '$img/salon.jpg', '$img/hair.jpg', 'st-sana', 'Bridal updo'),
  GalleryItem('g4', Cat.mehndi, '$img/nails.jpg', '$img/mehndi.jpg', 'st-hira', 'Bridal mehndi'),
  GalleryItem('g5', Cat.nails, '$img/salon.jpg', '$img/nails.jpg', 'st-fatima', 'Bridal nails'),
  GalleryItem('g6', Cat.photography, '$img/studio.jpg', '$img/bride-hero.jpg', 'st-usman', 'Studio portrait'),
];

// ------------------------------------------------------------ appointments

enum ApptStatus { upcoming, past, cancelled }

class Appointment {
  Appointment({
    required this.id,
    required this.status,
    required this.branchId,
    required this.serviceIds,
    required this.stylistId,
    required this.date,
    required this.time,
    required this.total,
    this.paid = 0,
    this.paidBy,
    this.notes = '',
    this.rating,
    this.review,
    this.cancelReason,
    this.rawStatus,
    this.canCancel = true,
    this.canPay = true,
    this.canReview = true,
    this.receiptNo,
    this.shopName,
    this.staffName,
    this.serviceNames = const [],
  });
  final String id;
  ApptStatus status;
  final String branchId, stylistId;
  final List<String> serviceIds;
  DateTime date;
  String time;
  final int total;
  int paid;
  String? paidBy;
  String notes;
  int? rating;
  String? review;
  String? cancelReason;
  /// The POS status (pending, confirmed, checked-in, …) when connected.
  String? rawStatus;
  bool canCancel, canPay, canReview;
  String? receiptNo, shopName, staffName;
  List<String> serviceNames;

  int get due => (total - paid).clamp(0, total);

  DateTime get startsAt {
    final p = time.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(p[0]), int.parse(p[1]));
  }

  String get title => serviceNames.isNotEmpty ? serviceNames.join(' + ') : serviceIds.map((id) => serviceById(id)?.name ?? 'Service').join(' + ');
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

List<Appointment> seedAppointments() => [
      Appointment(id: 'APT-10234', status: ApptStatus.upcoming, branchId: 'gulberg', serviceIds: ['svc-party', 'svc-style'], stylistId: 'st-amna', date: _day(2), time: '16:00', total: 20000, paid: 6000, paidBy: 'Easypaisa •••• 4567'),
      Appointment(id: 'APT-10198', status: ApptStatus.past, branchId: 'gulberg', serviceIds: ['svc-glow'], stylistId: 'st-fatima', date: _day(-14), time: '13:00', total: 6500, paid: 6500, paidBy: 'Card •••• 4242', rating: 5, review: 'Loved the glow afterwards!'),
      Appointment(id: 'APT-10150', status: ApptStatus.past, branchId: 'dha', serviceIds: ['svc-mani'], stylistId: 'st-fatima', date: _day(-30), time: '11:30', total: 3000, paid: 3000, paidBy: 'Cash at salon'),
      Appointment(id: 'APT-10102', status: ApptStatus.cancelled, branchId: 'f7', serviceIds: ['svc-wax'], stylistId: 'st-fatima', date: _day(-40), time: '15:00', total: 6500, cancelReason: 'Travelling'),
    ];

/// Slots the salon has open; a few are taken to show the real picker.
const timeSlots = ['10:00', '11:00', '12:30', '14:00', '15:30', '17:00', '18:30', '20:00'];
const takenSlots = {'11:00': 'Booked', '15:30': 'Stylist on break', '20:00': 'Branch closing'};

// ---------------------------------------------------------------- messages

class ChatMessage {
  ChatMessage({required this.id, required this.mine, required this.author, required this.text, required this.at, this.imagePath, this.imageBytes, this.imageUrl, this.seen = false});
  final String id, author, text;
  final bool mine;
  final DateTime at;
  final String? imagePath;
  final List<int>? imageBytes;
  /// A photo stored online (signed link from the API).
  final String? imageUrl;
  /// The other side has read it.
  final bool seen;
}

enum ThreadKind { announcements, concierge, branch }

class Thread {
  Thread({required this.id, required this.kind, required this.title, required this.subtitle, this.branchId, List<ChatMessage>? messages, this.serverUnread = 0, this.lastText, this.lastAt})
      : messages = messages ?? [];
  /// Unread count reported by the server (live mode).
  int serverUnread;
  String? lastText;
  DateTime? lastAt;
  final String id, title, subtitle;
  final ThreadKind kind;
  final String? branchId;
  final List<ChatMessage> messages;
  bool get readOnly => kind == ThreadKind.announcements;
}

DateTime _ago(double hours) => DateTime.now().subtract(Duration(minutes: (hours * 60).round()));

List<Thread> seedThreads() => [
      Thread(id: 'th-announce', kind: ThreadKind.announcements, title: 'Aura Updates', subtitle: 'News & offers from Aura by HS', messages: [
        ChatMessage(id: 'a1', mine: false, author: 'Aura by HS', text: '✨ Bridal season 2026 bookings are now open. Lock your dates with a 30% advance — Bride Signature and Bride Royal slots fill fast!', at: _ago(50)),
        ChatMessage(id: 'a2', mine: false, author: 'Aura by HS', text: '🎁 New: gift vouchers. Gift a pamper session to someone special — straight from your Wallet.', at: _ago(20), imagePath: '$img/party-makeup.jpg'),
        ChatMessage(id: 'a3', mine: false, author: 'Aura by HS', text: 'Use code AURA15 for 15% off your first booking this month 💐', at: _ago(3)),
      ]),
      Thread(id: 'th-concierge', kind: ThreadKind.concierge, title: 'Aura Concierge', subtitle: 'Head office · bridal & packages', messages: [
        ChatMessage(id: 'c1', mine: false, author: 'Hira (Concierge)', text: 'Assalam o Alaikum! Welcome to Aura by HS 🌸 Ask us anything about bridal packages, trials or availability.', at: _ago(26)),
      ]),
      Thread(id: 'th-gulberg', kind: ThreadKind.branch, title: 'Aura Gulberg', subtitle: 'Front desk', branchId: 'gulberg', messages: [
        ChatMessage(id: 'd1', mine: false, author: 'Front desk', text: 'Your appointment is confirmed for this week. Please arrive 10 minutes early. See you soon!', at: _ago(10)),
        ChatMessage(id: 'd2', mine: true, author: 'You', text: 'Thank you! Can I bring my reference photos?', at: _ago(9.5)),
        ChatMessage(id: 'd3', mine: false, author: 'Front desk', text: 'Of course — share them here and Amna will review before you arrive 💄', at: _ago(9.2)),
      ]),
    ];

const quickReplies = ['Is my slot confirmed?', 'Can I reschedule?', 'What’s included in the package?', 'Do you offer home service?'];

class AppNotification {
  const AppNotification(this.title, this.body, this.hoursAgo, this.kind);
  final String title, body, kind;
  final double hoursAgo;
}

const seedNotifications = <AppNotification>[
  AppNotification('Appointment reminder', 'Party Make-Up with Amna at Aura Gulberg in 2 days.', 2, 'reminder'),
  AppNotification('New offer: GLOW20', '20% off all facials this month.', 8, 'offer'),
  AppNotification('Payment received', 'Rs 6,000 advance paid by Easypaisa.', 30, 'payment'),
  AppNotification('Rate your visit', 'How was your Glow Facial with Fatima?', 340, 'review'),
];

const faqs = <(String, String)>[
  ('How do I confirm a bridal booking?', 'Pay a 30% advance in the app or at the branch. Your dates are held as soon as the advance is received.'),
  ('Can I reschedule?', 'Yes — from My Bookings, up to 4 hours before your appointment, free of charge.'),
  ('What is the cancellation policy?', 'Cancel more than 24 hours ahead for a full refund of any advance. Bridal advances are non-refundable within 30 days of the event.'),
  ('Do you offer home or venue service?', 'Yes, for bridal and party make-up. A travel charge applies depending on the location.'),
  ('Which payment methods do you accept?', 'JazzCash, Easypaisa, debit/credit cards, bank transfer (IBFT/Raast) and cash at the salon.'),
];

String rs(num n) {
  final s = n.round().toString();
  final buf = StringBuffer();
  // Pakistani grouping: 1,23,456 is uncommon in PKR retail; use 123,456.
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return 'Rs $buf';
}

String mins(int m) => m >= 60 ? '${m ~/ 60}h${m % 60 > 0 ? ' ${m % 60}m' : ''}' : '${m}m';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Sat, 14 Dec"
String fmtDate(DateTime d) => '${weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
String fmtDateLong(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "16:00" → "4:00 PM"
String fmtTime(String t) {
  final p = t.split(':');
  final h = int.parse(p[0]);
  return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h < 12 ? 'AM' : 'PM'}';
}

String fmtClock(DateTime d) => fmtTime('${d.hour}:${d.minute.toString().padLeft(2, '0')}');

String agoLabel(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'now';
  if (m < 60) return '${m}m';
  if (m < 1440) return '${m ~/ 60}h';
  return '${m ~/ 1440}d';
}
