import 'package:aura_by_hs/aura/data/mock_data.dart';
import 'package:aura_by_hs/aura/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rupee formatting', () {
    expect(rs(45000), 'Rs 45,000');
    expect(rs(1200), 'Rs 1,200');
    expect(fmtTime('16:00'), '4:00 PM');
  });

  test('offers apply only above minimum spend', () {
    final bride = offers.firstWhere((o) => o.code == 'BRIDE2026');
    expect(bride.discountOn(40000), 0);
    expect(bride.discountOn(60000), 5000);
    expect(offers.firstWhere((o) => o.code == 'AURA15').discountOn(10000), 1500);
  });

  test('booking confirmation adds an upcoming appointment and points', () {
    final s = AuraStore.i;
    final before = s.appointments.length;
    final pts = s.loyaltyPoints;
    s.booking
      ..branchId = 'dha'
      ..stylistId = 'st-sana'
      ..date = DateTime.now().add(const Duration(days: 3))
      ..time = '14:00';
    s.booking.serviceIds.add('svc-cut');
    final pay = s.recordPayment(amount: 700, method: PayMethod.easypaisa, purpose: 'Advance', reference: 'Easypaisa •••• 4567');
    final a = s.confirmBooking(total: 3500, payment: pay);
    expect(s.appointments.length, before + 1);
    expect(a.paid, 700);
    expect(s.loyaltyPoints, pts + 35);
    expect(s.booking.serviceIds, isEmpty);
  });

  test('messages count unread until read', () {
    final s = AuraStore.i;
    expect(s.unread('th-announce'), greaterThan(0));
    s.markRead('th-announce');
    expect(s.unread('th-announce'), 0);
  });
}
