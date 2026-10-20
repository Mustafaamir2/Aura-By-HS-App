import 'package:flutter/widgets.dart';

import 'state/app_state.dart';

/// English / Urdu strings for the app chrome. Service and package names stay
/// as the salon writes them. Urdu also flips the layout to right-to-left.
const Map<String, Map<String, String>> _strings = {
  'en': {
    'home': 'Home',
    'bookings': 'Bookings',
    'messages': 'Messages',
    'wallet': 'Wallet',
    'profile': 'Profile',
    'bookAppointment': 'Book appointment',
    'bookNow': 'Book now',
    'bridal': 'Bridal',
    'bridalPackages': 'Bridal packages',
    'ourServices': 'Our services',
    'seeAll': 'See all',
    'offersForYou': 'Offers for you',
    'allOffers': 'All offers',
    'upcoming': 'Upcoming',
    'past': 'Past',
    'cancelled': 'Cancelled',
    'upcomingAppointment': 'UPCOMING APPOINTMENT',
    'bookAgain': 'Book again',
    'meetArtists': 'Meet our artists',
    'lookbook': 'The Aura lookbook',
    'continue': 'Continue',
    'search': 'Search services, stylists, packages…',
    'goodMorning': 'Good morning',
    'goodAfternoon': 'Good afternoon',
    'goodEvening': 'Good evening',
    'welcome': 'Welcome',
    'enhance': 'Enhance your',
    'naturalBeauty': 'natural beauty',
    'language': 'Language',
    'logout': 'Log out',
  },
  'ur': {
    'home': 'ہوم',
    'bookings': 'بکنگز',
    'messages': 'پیغامات',
    'wallet': 'والٹ',
    'profile': 'پروفائل',
    'bookAppointment': 'اپائنٹمنٹ بک کریں',
    'bookNow': 'ابھی بک کریں',
    'bridal': 'برائیڈل',
    'bridalPackages': 'برائیڈل پیکجز',
    'ourServices': 'ہماری سروسز',
    'seeAll': 'سب دیکھیں',
    'offersForYou': 'آپ کے لیے آفرز',
    'allOffers': 'تمام آفرز',
    'upcoming': 'آنے والی',
    'past': 'گزشتہ',
    'cancelled': 'منسوخ',
    'upcomingAppointment': 'آنے والی اپائنٹمنٹ',
    'bookAgain': 'دوبارہ بک کریں',
    'meetArtists': 'ہمارے آرٹسٹ',
    'lookbook': 'آورا لُک بُک',
    'continue': 'آگے بڑھیں',
    'search': 'سروسز، اسٹائلسٹ، پیکجز تلاش کریں…',
    'goodMorning': 'صبح بخیر',
    'goodAfternoon': 'سلام',
    'goodEvening': 'شام بخیر',
    'welcome': 'خوش آمدید',
    'enhance': 'نکھاریں اپنی',
    'naturalBeauty': 'قدرتی خوبصورتی',
    'language': 'زبان',
    'logout': 'لاگ آؤٹ',
  },
};

extension AuraL10n on BuildContext {
  String t(String key) => _strings[AuraStore.i.lang]?[key] ?? _strings['en']![key] ?? key;
  bool get isUrdu => AuraStore.i.lang == 'ur';
}
