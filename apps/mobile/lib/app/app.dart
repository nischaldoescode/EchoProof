// root app widget — handles back button behavior
// double-tap back to exit only from root screens
// prevents accidental back to login when logged in

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import '../shared/widgets/connectivity_wrapper.dart';
import '../features/onboarding/presentation/services/onboarding_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class EchoProofApp extends StatelessWidget {
  const EchoProofApp({super.key, required this.router});
  final GoRouter router;

  static const _localeMap = {
    'en': Locale('en'),
    'hi': Locale('hi'),
    'ta': Locale('ta'),
    'te': Locale('te'),
    'kn': Locale('kn'),
    'mr': Locale('mr'),
    'bn': Locale('bn'),
    'es': Locale('es'),
    'fr': Locale('fr'),
    'de': Locale('de'),
    'ar': Locale('ar'),
    'zh': Locale('zh'),
  };

  @override
  Widget build(BuildContext context) {
    final langCode = context.watch<OnboardingService>().language;
    final locale = _localeMap[langCode] ?? const Locale('en');

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(
        key: ValueKey(langCode),
        child: MaterialApp.router(
          title: 'Echoproof',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: locale,
          supportedLocales: _localeMap.values.toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
          builder: (context, child) => ConnectivityWrapper(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

// wrap root screens with this to handle double-tap back to exit
class ExitConfirmWrapper extends StatefulWidget {
  const ExitConfirmWrapper({super.key, required this.child});
  final Widget child;

  @override
  State<ExitConfirmWrapper> createState() => _ExitConfirmWrapperState();
}

class _ExitConfirmWrapperState extends State<ExitConfirmWrapper> {
  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        final now = DateTime.now();
        final isDoubleTap = _lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2);

        if (isDoubleTap) {
          // exit the app
          await SystemNavigator.pop();
        } else {
          _lastBackPress = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Press back again to exit',
                  style: TextStyle(
                    fontFamily: 'Josefin Sans',
                    fontSize: 13,
                  ),
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
                backgroundColor: const Color(0xFF2D2D2D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      },
      child: widget.child,
    );
  }
}
