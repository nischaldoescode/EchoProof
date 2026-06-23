// root app widget handles back button behavior
// double-tap back to exit only from root screens
// prevents accidental back to login when logged in

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import '../shared/widgets/connectivity_wrapper.dart';
import '../features/onboarding/presentation/services/onboarding_service.dart';
import '../core/localization/app_copy.dart';
import '../core/utils/logger.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/utils/snack.dart';
import 'package:flutter_quill/flutter_quill.dart';

class EchoProofApp extends StatelessWidget {
  const EchoProofApp({super.key, required this.router});
  final GoRouter router;

  static const _systemBars = SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.white,
    systemNavigationBarContrastEnforced: true,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

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

    // do not wrap materialapp.router in animatedswitcher it creates
    // duplicate globalkeys during the cross-fade because gorouter uses
    // globalobjectkey internally. instead let materialapp.router react
    // to locale changes directly. the locale prop itself is reactive since
    // build() is called whenever onboardingservice notifies
    return MaterialApp.router(
      title: 'Echoproof',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: locale,
      supportedLocales: _localeMap.values.toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _systemBars,
        child: ConnectivityWrapper(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

// wrap root screens with this to handle double-tap back to exit
class ExitConfirmWrapper extends StatefulWidget {
  const ExitConfirmWrapper({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<ExitConfirmWrapper> createState() => _ExitConfirmWrapperState();
}

class _ExitConfirmWrapperState extends State<ExitConfirmWrapper> {
  DateTime? _lastBackPress;
  DateTime? _lastBackEvent;
  bool _handlingBack = false;

  Future<bool> _handleBackIntent() async {
    if (!widget.enabled) {
      AppLogger.debug('exit-back: ignored because wrapper disabled');
      return false;
    }
    if (_handlingBack) {
      AppLogger.debug('exit-back: ignored re-entrant back callback');
      return true;
    }

    _handlingBack = true;
    try {
      return await _processBackIntent();
    } finally {
      _handlingBack = false;
    }
  }

  Future<bool> _processBackIntent() async {
    final now = DateTime.now();
    final route = ModalRoute.of(context);
    AppLogger.info(
      'exit-back: received route=${route?.settings.name} '
      'isCurrent=${route?.isCurrent} canPop=${route?.canPop}',
    );

    final lastBackEvent = _lastBackEvent;
    _lastBackEvent = now;
    if (lastBackEvent != null &&
        now.difference(lastBackEvent) < const Duration(milliseconds: 300)) {
      AppLogger.debug(
        'exit-back: duplicate callback ignored '
        'deltaMs=${now.difference(lastBackEvent).inMilliseconds}',
      );
      return true;
    }

    final keyboardOpen =
        (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0) > 0;
    if (keyboardOpen) {
      AppLogger.info('exit-back: closing keyboard instead of exiting');
      FocusManager.instance.primaryFocus?.unfocus();
      return true;
    }

    if (route != null && !route.isCurrent) {
      AppLogger.info('exit-back: top route is not current, trying pop modal');
      await Navigator.of(context).maybePop();
      return true;
    }

    final isDoubleTap =
        _lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2);

    if (isDoubleTap) {
      AppLogger.info('exit-back: second back within window, exiting app');
      await SystemNavigator.pop();
      return true;
    }

    _lastBackPress = now;
    if (mounted) {
      final bottomMargin = _rootSnackBottomMargin(context);
      AppLogger.info(
        'exit-back: showing root exit HyperSnackbar '
        'bottomMargin=$bottomMargin',
      );
      showInfoSnack(
        context,
        context.l('Press back again to exit'),
        bottomMargin: bottomMargin,
      );
    }
    return true;
  }

  double _rootSnackBottomMargin(BuildContext context) {
    // root screens need to clear the navigation bar without moving the exit
    // prompt above the compose action on short or split-screen windows.
    final size = MediaQuery.sizeOf(context);
    final chromeMargin = size.shortestSide >= 600 ? 56.0 : 68.0;
    return (size.height * 0.10).clamp(48.0, chromeMargin).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final shouldHandleExit = widget.enabled && !(route?.canPop ?? false);
    AppLogger.debug(
      'exit-back: build route=${route?.settings.name} '
      'enabled=${widget.enabled} canPop=${route?.canPop} '
      'shouldHandleExit=$shouldHandleExit',
    );

    return PopScope(
      canPop: !shouldHandleExit,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !shouldHandleExit) return;
        await _handleBackIntent();
      },
      child: widget.child,
    );
  }
}
