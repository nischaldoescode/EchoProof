import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../features/onboarding/presentation/services/onboarding_service.dart';

extension AppCopyX on BuildContext {
  String tx(String key) {
    final language = watch<OnboardingService>().language;
    return AppCopy.text(language, key);
  }
}

abstract final class AppCopy {
  static const _copy = <String, Map<String, String>>{
    'en': {
      'login.subtitle': 'Verified claims, real people.',
      'login.signIn': 'Sign in',
      'login.emailHint': 'name@email.com',
      'login.emailHelp': 'Enter your email and we will send a 6-digit code.',
      'login.continueEmail': 'Continue with email',
      'login.continueGoogle': 'Continue with Google',
      'login.termsPrefix': 'I agree to the ',
      'login.terms': 'Terms',
      'login.privacy': 'Privacy Policy',
      'login.secureCopy':
          'Secure email codes. Native Google sign-in. No password to remember.',
      'otp.title': 'Check your email',
      'otp.sentPrefix': 'We sent a 6-digit code to',
      'otp.verify': 'Verify',
      'otp.resend': 'Resend code',
      'otp.resendIn': 'Resend in {s}s',
      'otp.backCooldown': 'You can go back in {s}s.',
      'otp.incorrect': 'Incorrect code. Please try again.',
      'echoDetail.replies': 'Replies',
      'echoDetail.addReply': 'Add reply',
      'echoDetail.viewThread': 'View thread',
      'echoDetail.evidence': 'Evidence',
      'echoDetail.communitySignals': 'Community signals',
      'nav.feed': 'Feed',
      'nav.discover': 'Discover',
      'nav.alerts': 'Alerts',
      'nav.profile': 'Profile',
      'onboarding.languageTitle': 'Choose your language',
      'onboarding.languageHelp': 'You can change this any time in Settings.',
      'common.continue': 'Continue',
    },
    'hi': {
      'login.subtitle': 'सत्यापित दावे, असली लोग.',
      'login.signIn': 'साइन इन',
      'login.emailHint': 'name@email.com',
      'login.emailHelp': 'अपना ईमेल डालें, हम 6 अंकों का कोड भेजेंगे.',
      'login.continueEmail': 'ईमेल से जारी रखें',
      'login.continueGoogle': 'Google से जारी रखें',
      'login.termsPrefix': 'मैं सहमत हूं ',
      'login.terms': 'शर्तों',
      'login.privacy': 'Privacy Policy',
      'login.secureCopy': 'सुरक्षित ईमेल कोड. पासवर्ड याद रखने की जरूरत नहीं.',
      'otp.title': 'अपना ईमेल देखें',
      'otp.sentPrefix': 'हमने 6 अंकों का कोड भेजा है',
      'otp.verify': 'वेरिफाई',
      'otp.resend': 'कोड फिर भेजें',
      'otp.resendIn': '{s}s में फिर भेजें',
      'otp.backCooldown': 'आप {s}s में वापस जा सकते हैं.',
      'otp.incorrect': 'कोड गलत है. फिर कोशिश करें.',
      'echoDetail.replies': 'जवाब',
      'echoDetail.addReply': 'जवाब जोड़ें',
      'echoDetail.viewThread': 'थ्रेड देखें',
      'echoDetail.evidence': 'सबूत',
      'echoDetail.communitySignals': 'कम्युनिटी संकेत',
      'nav.feed': 'फीड',
      'nav.discover': 'डिस्कवर',
      'nav.alerts': 'अलर्ट',
      'nav.profile': 'प्रोफाइल',
      'onboarding.languageTitle': 'अपनी भाषा चुनें',
      'onboarding.languageHelp': 'इसे आप Settings में कभी भी बदल सकते हैं.',
      'common.continue': 'जारी रखें',
    },
  };

  static String text(String language, String key) {
    return _copy[language]?[key] ?? _copy['en']![key] ?? key;
  }
}
