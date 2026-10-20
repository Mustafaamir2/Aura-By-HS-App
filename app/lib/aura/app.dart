import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'routes.dart';
import 'screens/auth_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/kit.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class AuraApp extends StatefulWidget {
  const AuraApp({super.key});
  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> {
  @override
  void initState() {
    super.initState();
    // A password-reset email link opens the app signed in: ask for the new password.
    AuraStore.i.passwordRecovery.addListener(_recover);
  }

  @override
  void dispose() {
    AuraStore.i.passwordRecovery.removeListener(_recover);
    super.dispose();
  }

  void _recover() {
    if (!AuraStore.i.passwordRecovery.value) return;
    AuraStore.i.passwordRecovery.value = false;
    final ctx = navigatorKey.currentContext;
    if (ctx != null) showAuraSheet<void>(ctx, builder: (_) => const NewPasswordSheet());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuraStore.i,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Aura by HS',
        debugShowCheckedModeBanner: false,
        theme: buildAuraTheme(),
        locale: Locale(AuraStore.i.lang),
        supportedLocales: const [Locale('en'), Locale('ur')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: Routes.splash,
        onGenerateRoute: onGenerateRoute,
      ),
    );
  }
}
