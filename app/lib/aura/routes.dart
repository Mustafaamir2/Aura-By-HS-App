import 'package:flutter/material.dart';

import 'data/mock_data.dart';
import 'screens/auth_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/branches_screen.dart';
import 'screens/catalogue_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/info_screens.dart';
import 'screens/invoices_screen.dart';
import 'screens/main_shell.dart';
import 'screens/notifications_screen.dart';
import 'screens/offers_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/packages_screen.dart';
import 'screens/service_detail_screen.dart';
import 'screens/splash_screen.dart';

class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const auth = '/auth';
  static const main = '/app';
  static const booking = '/booking';
  static const catalogue = '/catalogue';
  static const service = '/service';
  static const packages = '/packages';
  static const gallery = '/gallery';
  static const offers = '/offers';
  static const notifications = '/notifications';
  static const invoices = '/invoices';
  static const branches = '/branches';
  static const chat = '/chat';
  static const editProfile = '/edit-profile';
  static const preferences = '/preferences';
  static const favourites = '/favourites';
  static const help = '/help';
  static const legal = '/legal';
}

Route<dynamic>? onGenerateRoute(RouteSettings s) {
  final a = s.arguments;
  final Widget page = switch (s.name) {
    Routes.splash => const SplashScreen(),
    Routes.onboarding => const OnboardingScreen(),
    Routes.auth => const AuthScreen(),
    Routes.main => MainShell(initialTab: a is int ? a : 0),
    Routes.booking => const BookingScreen(),
    Routes.catalogue => CatalogueScreen(initial: a is Cat ? a : null),
    Routes.service => ServiceDetailScreen(serviceId: a as String),
    Routes.packages => const PackagesScreen(),
    Routes.gallery => const GalleryScreen(),
    Routes.offers => const OffersScreen(),
    Routes.notifications => const NotificationsScreen(),
    Routes.invoices => const InvoicesScreen(),
    Routes.branches => const BranchesScreen(),
    Routes.chat => ChatScreen(threadId: a as String),
    Routes.editProfile => const EditProfileScreen(),
    Routes.preferences => const PreferencesScreen(),
    Routes.favourites => const FavouritesScreen(),
    Routes.help => const HelpScreen(),
    Routes.legal => LegalScreen(privacy: a == 'privacy'),
    _ => const SplashScreen(),
  };
  // Fade-through for the splash/onboarding/auth handoff, native slide elsewhere.
  if (s.name == Routes.onboarding || s.name == Routes.auth || s.name == Routes.main) {
    return PageRouteBuilder(
      settings: s,
      transitionDuration: const Duration(milliseconds: 550),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
    );
  }
  return MaterialPageRoute(settings: s, builder: (_) => page);
}
