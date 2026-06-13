// app copy
// @params none

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../features/onboarding/presentation/services/onboarding_service.dart';

extension AppCopyX on BuildContext {
  String tx(String key) {
    final language = _appLanguage();
    return AppCopy.text(language, key);
  }

  String l(String english, [Map<String, Object?> args = const {}]) {
    final language = _appLanguage();
    return AppCopy.phrase(language, english, args);
  }

  String _appLanguage() {
    try {
      // `context.l(...)` is used from builds, callbacks, async catches, and
      // snack helpers. always read without subscribing; echoproofapp already
      // watches the language and rebuilds materialapp when it changes
      return Provider.of<OnboardingService>(this, listen: false).language;
    } on ProviderNotFoundException {
      return 'en';
    } on FlutterError {
      return 'en';
    }
  }
}

abstract final class AppCopy {
  static const _copy = <String, Map<String, String>>{
    'en': {
      'login.subtitle': 'Verified claims. Human proof.',
      'login.subtitleLead': 'Verified claims.',
      'login.subtitleTail': 'Human proof.',
      'login.signIn': 'Sign in',
      'login.emailHint': 'name@email.com',
      'login.emailHelp': 'Share proof. Find trust.',
      'login.continueEmail': 'Continue with email',
      'login.continueGoogle': 'Continue with Google',
      'login.termsPrefix': 'I agree to the ',
      'login.terms': 'Terms',
      'login.privacy': 'Privacy Policy',
      'login.secureCopy': 'Proof becomes trust.',
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
      'nav.rooms': 'Rooms',
      'nav.alerts': 'Alerts',
      'nav.profile': 'Profile',
      'onboarding.languageTitle': 'Choose your language',
      'onboarding.languageHelp': 'You can change this any time in Settings.',
      'common.continue': 'Continue',
    },
    'hi': {
      'login.subtitle': 'सत्यापित दावे. असली भरोसा.',
      'login.subtitleLead': 'सत्यापित दावे.',
      'login.subtitleTail': 'असली भरोसा.',
      'login.signIn': 'साइन इन',
      'login.emailHint': 'name@email.com',
      'login.emailHelp': 'सबूत बांटें. भरोसा पाएं.',
      'login.continueEmail': 'ईमेल से जारी रखें',
      'login.continueGoogle': 'Google से जारी रखें',
      'login.termsPrefix': 'मैं सहमत हूं ',
      'login.terms': 'शर्तों',
      'login.privacy': 'Privacy Policy',
      'login.secureCopy': 'सबूत से भरोसा बने.',
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

  static String phrase(
    String language,
    String english, [
    Map<String, Object?> args = const {},
  ]) {
    var value = _phrase(language, english);
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static String _phrase(String language, String english) {
    if (language == 'en') return english;

    final languageCopy = _copy[language];
    final englishCopy = _copy['en']!;
    if (languageCopy != null) {
      for (final entry in englishCopy.entries) {
        if (entry.value == english) {
          return languageCopy[entry.key] ?? english;
        }
      }
    }

    return _phrases[language]?[english] ?? english;
  }

  static const _phrases = <String, Map<String, String>>{
    'hi': {
      'Cancel': 'रद्द करें',
      'Delete': 'हटाएं',
      'Save': 'सेव करें',
      'Edit': 'एडिट',
      'Reset': 'रीसेट',
      'Back': 'वापस',
      'Submit': 'सबमिट',
      'Try again': 'फिर कोशिश करें',
      'Search': 'खोजें',
      'Filter': 'फिल्टर',
      'Refresh feed': 'फीड रीफ्रेश करें',
      'Loading feed': 'फीड लोड हो रही है',
      'Loading profile': 'प्रोफाइल लोड हो रही है',
      'Pull down and try again.': 'नीचे खींचकर फिर कोशिश करें.',
      'Nothing yet': 'अभी कुछ नहीं',
      'Be the first to create an echo.': 'पहला echo आप बनाएं.',
      'No echoes match your filters': 'आपके फिल्टर से कोई echo नहीं मिला',
      'Try adjusting or clearing your filters.': 'फिल्टर बदलें या साफ करें.',
      'Clear filters': 'फिल्टर साफ करें',
      'Could not load feed': 'फीड लोड नहीं हुई',
      'Create Echo': 'Echo बनाएं',
      'Title': 'शीर्षक',
      'Content': 'कंटेंट',
      'Category': 'कैटेगरी',
      'Short, clear claim or opinion': 'छोटा, साफ दावा या राय',
      'Field name': 'फील्ड नाम',
      'Pro writing guide': 'Pro लेखन गाइड',
      'Discover': 'डिस्कवर',
      'Finding signals': 'संकेत ढूंढ रहे हैं',
      'Notifications': 'नोटिफिकेशन',
      'Mark all read': 'सब पढ़ा हुआ करें',
      'Accept': 'स्वीकार करें',
      'Ignore': 'अनदेखा करें',
      'Thread': 'थ्रेड',
      'Reply': 'जवाब',
      'Like': 'लाइक',
      'Challenge': 'चैलेंज',
      'Bonds': 'बॉन्ड',
      'More actions': 'और विकल्प',
      'Share echo': 'Echo शेयर करें',
      'Copy link': 'लिंक कॉपी करें',
      'Report echo': 'Echo रिपोर्ट करें',
      'Delete echo': 'Echo हटाएं',
      'Not interested': 'रुचि नहीं है',
      'Delete this echo?': 'यह echo हटाएं?',
      'Spam': 'स्पैम',
      'Misinformation': 'गलत जानकारी',
      'Harassment': 'उत्पीड़न',
      'Fake proof': 'नकली सबूत',
      'Other': 'अन्य',
      'App language': 'ऐप भाषा',
      'Edit profile': 'प्रोफाइल एडिट करें',
      'Profile menu': 'प्रोफाइल मेन्यू',
      'Blocked users': 'ब्लॉक किए गए यूज़र',
      'Echoproof Pro': 'Echoproof Pro',
      'Push notifications': 'पुश नोटिफिकेशन',
      'In-app notifications': 'इन-ऐप नोटिफिकेशन',
      'Photo library': 'फोटो लाइब्रेरी',
      'Camera': 'कैमरा',
      'End-to-end encryption': 'एंड-टू-एंड एन्क्रिप्शन',
      'Delete account': 'अकाउंट हटाएं',
      'About Echoproof': 'Echoproof के बारे में',
      'Terms of service': 'सेवा की शर्तें',
      'Privacy policy': 'प्राइवेसी पॉलिसी',
      'Contact support': 'सपोर्ट से संपर्क करें',
      'Delete account?': 'अकाउंट हटाएं?',
      'your email address': 'आपका ईमेल पता',
      'Echoes': 'Echoes',
      'Followers': 'फॉलोअर्स',
      'Following': 'फॉलोइंग',
      'Proofs': 'सबूत',
      'Score': 'स्कोर',
      'Edit bio': 'बायो एडिट करें',
      'Write something about yourself...': 'अपने बारे में कुछ लिखें...',
      'Male': 'पुरुष',
      'Female': 'महिला',
      'Non-binary': 'नॉन-बाइनरी',
      'Prefer not to say': 'न बताना पसंद करूंगा',
      'Private': 'प्राइवेट',
      'Human': 'मानव',
      'Trust lift': 'ट्रस्ट बढ़त',
      'Search people or echoes...': 'लोग या echoes खोजें...',
      'Post echoes': 'Echoes पोस्ट करें',
      'Support & challenge echoes': 'Echoes सपोर्ट और चैलेंज करें',
      'Character limit': 'कैरेक्टर सीमा',
      'Edit your echoes': 'अपने echoes एडिट करें',
      'Ad-free experience': 'विज्ञापन-मुक्त अनुभव',
      'Truth bonds': 'Truth bonds',
      'Priority in feed': 'फीड में प्राथमिकता',
      'Analytics on your echoes': 'आपके echoes पर analytics',
      'Monthly': 'मासिक',
      'Yearly': 'वार्षिक',
      'Continue': 'जारी रखें',
      'Got it, continue': 'समझ गया, जारी रखें',
      'Understood': 'समझ गया',
      'Stay': 'रुकें',
      'Leave': 'छोड़ें',
      'Cancel setup?': 'सेटअप रद्द करें?',
      'Your name': 'आपका नाम',
      'username': 'यूज़रनेम',
      'Global': 'ग्लोबल',
      'India': 'भारत',
      'United States': 'संयुक्त राज्य',
      'United Kingdom': 'यूनाइटेड किंगडम',
      'Germany': 'जर्मनी',
      'Japan': 'जापान',
      'Nigeria': 'नाइजीरिया',
      'Brazil': 'ब्राज़ील',
      'Indonesia': 'इंडोनेशिया',
      'Pakistan': 'पाकिस्तान',
      'and': 'और',
      'Accept the Privacy Policy and Terms of Service to continue.':
          'जारी रखने के लिए Privacy Policy और Terms of Service स्वीकार करें.',
      'Press back again to exit': 'बाहर निकलने के लिए फिर Back दबाएं',
      'Filter feed': 'फीड फिल्टर करें',
      'Sort by': 'इसके अनुसार क्रमबद्ध करें',
      'Quick filters': 'त्वरित फिल्टर',
      'Status': 'स्थिति',
      'Categories': 'कैटेगरी',
      'Apply filters': 'फिल्टर लागू करें',
      'Verified only': 'केवल सत्यापित',
      'Unverified only': 'केवल असत्यापित',
      'Trending': 'ट्रेंडिंग',
      'Newest': 'सबसे नया',
      'Most support': 'सबसे अधिक सपोर्ट',
      'Most debated': 'सबसे अधिक बहस',
      'Most confident': 'सबसे अधिक भरोसेमंद',
      'Awaiting echoes...': 'Echoes का इंतज़ार...',
      'Under community review': 'कम्युनिटी समीक्षा में',
      'Verified by community': 'कम्युनिटी द्वारा सत्यापित',
      'Controversial — community split': 'विवादित — कम्युनिटी बंटी हुई',
      'Hidden': 'छिपा हुआ',
      'Rejected': 'अस्वीकृत',
      'No signals trending yet': 'अभी कोई संकेत ट्रेंड नहीं कर रहा',
      'Trending signals in {country}': '{country} में ट्रेंडिंग संकेत',
      'Trending signals globally': 'दुनिया भर में ट्रेंडिंग संकेत',
      '{echoes} echoes · {voices} voices': '{echoes} echoes · {voices} आवाजें',
      'Fair {score}': 'Fair {score}',
      'Opening echo bonds and evidence.': 'Echo bonds और सबूत खोल रहे हैं.',
      'You cannot support or challenge your own echo.':
          'आप अपने echo को support या challenge नहीं कर सकते.',
      'Set your identity': 'अपनी पहचान सेट करें',
      'Your display name is what people see. Your username is your unique handle.':
          'लोग आपका display name देखते हैं. Username आपका unique handle है.',
      'Display name': 'डिस्प्ले नाम',
      'Enter your name': 'अपना नाम डालें',
      'Enter a username': 'यूज़रनेम डालें',
      'At least 3 characters': 'कम से कम 3 अक्षर',
      'Only letters, numbers, and underscores':
          'केवल अक्षर, नंबर और underscore',
      'Username taken': 'यूज़रनेम पहले से लिया गया है',
      'Username already taken': 'यूज़रनेम पहले से लिया गया है',
      'Check username': 'यूज़रनेम जांचें',
      'Available!': 'उपलब्ध है!',
      'Failed to save. Please try again.':
          'सेव नहीं हुआ. कृपया फिर कोशिश करें.',
      'Your account won\'t be fully set up. You\'ll need to complete this next time.':
          'आपका अकाउंट पूरा सेट नहीं होगा. अगली बार आपको इसे पूरा करना होगा.',
      'What matters to you?': 'आपके लिए क्या मायने रखता है?',
      'Pick at least {count} areas. Your feed will show echoes from these communities.':
          'कम से कम {count} क्षेत्र चुनें. आपका feed इन communities के echoes दिखाएगा.',
      'Select {count} more': '{count} और चुनें',
      '{count} selected': '{count} चुने गए',
      'Tech': 'टेक',
      'Finance': 'फाइनेंस',
      'Startups': 'स्टार्टअप्स',
      'Social Issues': 'सामाजिक मुद्दे',
      'Web3': 'Web3',
      'AI': 'AI',
      'Gaming': 'गेमिंग',
      'Education': 'शिक्षा',
      'You stay anonymous.': 'आप anonymous रहते हैं.',
      'We verify your identity privately. Your real name never appears publicly — only your trust level does.':
          'हम आपकी पहचान privately verify करते हैं. आपका असली नाम public नहीं दिखता — केवल आपका trust level दिखता है.',
      'Your identity is verified privately':
          'आपकी पहचान privately verify होती है',
      'Your public profile stays anonymous':
          'आपकी public profile anonymous रहती है',
      'Your trust level grows with your activity':
          'आपकी activity से trust level बढ़ता है',
      'Your interactions shape truth.':
          'आपकी interactions truth को shape करती हैं.',
      'Higher trust tier = more weight. Votes from elite users move echoes more than unverified ones.':
          'जितना higher trust tier, उतना ज्यादा weight. Elite users के votes echoes को unverified users से ज्यादा प्रभावित करते हैं.',
      'Default starting level': 'शुरुआती default level',
      'Active, not yet verified': 'Active, अभी verified नहीं',
      'Consistent, helpful contributions': 'लगातार helpful contributions',
      'Identity verified + trusted': 'Identity verified + trusted',
      'Top contributors — 5x vote weight': 'Top contributors — 5x vote weight',
      'Here\'s how it works': 'यह ऐसे काम करता है',
      'Swipe through to see what you can do.':
          'आप क्या कर सकते हैं देखने के लिए swipe करें.',
      'Create an Echo': 'एक Echo बनाएं',
      'An Echo is a claim, story, or observation. Post it — the community rates its credibility.':
          'Echo कोई claim, story या observation है. इसे post करें — community इसकी credibility rate करती है.',
      'Proof it': 'Proof जोड़ें',
      'Attach links, screenshots, or sources. More proof = higher trust score for you.':
          'Links, screenshots या sources जोड़ें. ज्यादा proof = आपका higher trust score.',
      'Signal on others': 'दूसरों पर signal दें',
      'Mark Echoes as True, False, or Unverified. Your rating history builds your credibility.':
          'Echoes को True, False या Unverified mark करें. आपकी rating history credibility बनाती है.',
      'Your trust level': 'आपका trust level',
      'Start as Unverified. Verify your identity privately to unlock higher trust tiers.':
          'Unverified से शुरुआत करें. Higher trust tiers unlock करने के लिए identity privately verify करें.',
      'Discover topics': 'Topics discover करें',
      'Follow categories you care about. Your feed surfaces the most-debated stories.':
          'अपनी पसंद की categories follow करें. आपका feed सबसे debated stories दिखाता है.',
      'Next': 'आगे',
      'Let\'s go!': 'चलें!',
      'Share your first Echo': 'अपना पहला Echo शेयर करें',
      'Optional — you can always create one later from the feed.':
          'Optional — आप feed से बाद में भी बना सकते हैं.',
      'What do you want the community to verify?':
          'आप community से क्या verify करवाना चाहते हैं?',
      'Publish and enter': 'Publish करें और अंदर जाएं',
      'Skip for now': 'अभी छोड़ें',
      'Setting up your account...': 'आपका अकाउंट सेट हो रहा है...',
      'Content warning': 'Content warning',
      'Your echo looks like it might be flagged by our community filters. Review your content and make sure it follows our guidelines before posting.':
          'आपका echo community filters में flag हो सकता है. Post करने से पहले content review करें और guidelines follow करें.',
      'Post anyway': 'फिर भी post करें',
      'Save this draft?': 'यह draft सेव करें?',
      'Your echo is not published. You can save it as a draft or discard it.':
          'आपका echo publish नहीं हुआ है. आप इसे draft के रूप में save या discard कर सकते हैं.',
      'Save draft': 'Draft सेव करें',
      'Discard': 'Discard करें',
      'Maximum 2 attachments allowed': 'अधिकतम 2 attachments allowed हैं',
      'File could not be attached': 'File attach नहीं हो सकी',
      'That attachment is already selected':
          'यह attachment पहले से selected है',
      'Echo created — awaiting community signals':
          'Echo बन गया — community signals का इंतज़ार',
      'Thanks for supporting Echoproof — 1 hour ad-free!':
          'Echoproof support करने के लिए धन्यवाद — 1 hour ad-free!',
      'title cannot be empty': 'Title खाली नहीं हो सकता',
      'Other field must be 10 characters or less.':
          'Other field 10 characters या कम होना चाहिए.',
      'Other field is required.': 'Other field required है.',
      'Save changes': 'Changes सेव करें',
      'Profile updated.': 'Profile update हो गई.',
      'Profile changes are cooling down. Try again in {time}.':
          'Profile changes cooldown में हैं. {time} में फिर कोशिश करें.',
      'Profile changes are cooling down. Please try again later.':
          'Profile changes cooldown में हैं. कृपया बाद में कोशिश करें.',
      'Failed to save changes. Please try again.':
          'Changes save नहीं हुए. कृपया फिर कोशिश करें.',
      'Verify your email': 'अपना email verify करें',
      'A verification code was sent to {email}. Enter it to confirm the username change.':
          '{email} पर verification code भेजा गया है. Username change confirm करने के लिए code डालें.',
      'Verify': 'Verify करें',
      'Date of birth': 'जन्मतिथि',
      'select your date of birth': 'अपनी जन्मतिथि चुनें',
      'Not set': 'सेट नहीं',
      'Gender': 'Gender',
      'Username and date of birth changes require email verification.':
          'Username और date of birth changes के लिए email verification चाहिए.',
      'Your display name': 'आपका display name',
      'Could not load profile': 'Profile load नहीं हुई',
      'Could not load list.': 'List load नहीं हुई.',
      'Replies': 'जवाब',
      'Media': 'मीडिया',
      'Analytics': 'Analytics',
      'Name, username, birthday, and gender':
          'Name, username, birthday और gender',
      'Public profile': 'Public profile',
      'Private profile': 'Private profile',
      'Profile blocked': 'Profile blocked',
      'Anyone can view your profile': 'कोई भी आपकी profile देख सकता है',
      'Only accepted followers can view it':
          'केवल accepted followers इसे देख सकते हैं',
      'Review and unblock accounts': 'Accounts review और unblock करें',
      'Settings': 'Settings',
      'Account, ads, privacy, and support': 'Account, ads, privacy और support',
      'Requested': 'Requested',
      'Request follow': 'Follow request करें',
      'Follow': 'Follow',
      'Unblock': 'Unblock',
      'Block': 'Block',
      'Block user': 'User block करें',
      'Unblock user': 'User unblock करें',
      'Unblock this user before following.':
          'Follow करने से पहले इस user को unblock करें.',
      'Follow request canceled': 'Follow request cancel हो गई',
      'Follow request sent': 'Follow request भेजी गई',
      'Could not update follow status.': 'Follow status update नहीं हो पाया.',
      'Block @{username}?': '@{username} को block करें?',
      'You will stop seeing each other in profiles, feeds, replies, and interactions. Existing follow links are removed.':
          'आप दोनों profiles, feeds, replies और interactions में एक-दूसरे को नहीं देखेंगे. Existing follow links हट जाएंगे.',
      'User blocked': 'User blocked',
      'Could not block user.': 'User block नहीं हो पाया.',
      'User unblocked': 'User unblocked',
      'Could not unblock user.': 'User unblock नहीं हो पाया.',
      'Visible on your public profile.': 'आपकी public profile पर दिखेगा.',
      'Save bio': 'Bio सेव करें',
      'No {kind} yet.': 'अभी कोई {kind} नहीं.',
      'No matching accounts.': 'कोई matching account नहीं मिला.',
      'Try another name or username.': 'दूसरा name या username खोजकर देखें.',
      'Follower lists are visible only on public profiles.':
          'Follower lists सिर्फ public profiles पर दिखती हैं.',
      '{followers} followers · {following} following':
          '{followers} followers · {following} following',
      'No blocked users': 'कोई blocked users नहीं',
      'Blocked accounts will appear here.':
          'Blocked accounts यहां दिखाई देंगे.',
      'No bio yet.': 'अभी bio नहीं है.',
      'Add bio': 'Bio जोड़ें',
      'Follow request required to view echoes, replies, followers, and following.':
          'Echoes, replies, followers और following देखने के लिए follow request required है.',
      'Reset zoom': 'Zoom reset करें',
      'Zoom in': 'Zoom in',
      'Center image': 'Image center करें',
      'Anyone can see your echoes': 'कोई भी आपके echoes देख सकता है',
      'Only you can see your echoes': 'केवल आप अपने echoes देख सकते हैं',
      'This account is private': 'यह account private है',
      '@{username} has set their profile to private.':
          '@{username} ने profile private रखी है.',
      'Your follow request is pending.': 'आपकी follow request pending है.',
      'Send a follow request to view their echoes and social graph.':
          'उनके echoes और social graph देखने के लिए follow request भेजें.',
      'Verification in progress — usually takes a few minutes':
          'Verification चल रहा है — आमतौर पर कुछ minutes लगते हैं',
      'Verify your identity to increase your trust weight':
          'Trust weight बढ़ाने के लिए identity verify करें',
      'No echoes yet.': 'अभी कोई echoes नहीं.',
      'Published echoes will appear here.':
          'Published echoes यहां दिखाई देंगे.',
      'No replies yet.': 'अभी कोई replies नहीं.',
      'Replies to other echoes will appear here.':
          'दूसरे echoes पर replies यहां दिखाई देंगे.',
      'Replying to "{title}"': '"{title}" को reply कर रहे हैं',
      '@{username} is private': '@{username} private है',
      'Accepted followers can view echoes, replies, media, followers, and following.':
          'Accepted followers echoes, replies, media, followers और following देख सकते हैं.',
      'No media yet.': 'अभी कोई media नहीं.',
      'Echoes with photos or videos will appear here.':
          'Photos या videos वाले echoes यहां दिखाई देंगे.',
      'Account Overview': 'Account overview',
      'Engagement Summary': 'Engagement summary',
      'Top Echoes by Trust Score': 'Trust score के हिसाब से top echoes',
      'Trust Score': 'Trust score',
      'Support': 'Support',
      'Support ratio': 'Support ratio',
      '{percent}% supportive': '{percent}% supportive',
      '{confidence}% confidence · {support} ↑ {challenge} ↓':
          '{confidence}% confidence · {support} ↑ {challenge} ↓',
      'Untitled': 'बिना title',
      'Settled': 'Settled',
      'Contested': 'Contested',
      'Back to echo': 'Echo पर वापस',
      'Video link is missing.': 'Video link missing है.',
      'No evidence attached yet. Be the first to add proof.':
          'अभी कोई evidence attached नहीं है. पहला proof आप जोड़ें.',
      'No replies yet. Start the conversation.':
          'अभी कोई replies नहीं. Conversation शुरू करें.',
      'View {count} more': '{count} और देखें',
      'Other: {detail}': 'अन्य: {detail}',
      'Username': 'यूज़रनेम',
      'Profile': 'प्रोफाइल',
      'followers': 'फॉलोअर्स',
      'following': 'फॉलोइंग',
      'You blocked @{username}': 'आपने @{username} को block किया है',
      'Pro Writing Guide': 'Pro writing guide',
      'Rich Text Formatting': 'Rich text formatting',
      'Link Previews': 'Link previews',
      'Mentions & Signals': 'Mentions और signals',
      'Media Attachments': 'Media attachments',
      'Getting Verified': 'Verified होना',
      'content cannot be empty': 'Content खाली नहीं हो सकता',
      'Explain your opinion or claim.\n\nUse @username to mention, ~signal to tag.':
          'अपनी राय या claim समझाएं.\n\nMention के लिए @username, tag के लिए ~signal use करें.',
      'Explain your opinion or claim.\n\nUse @username and #topic-name to connect it.':
          'अपनी राय या claim समझाएं.\n\nConnect करने के लिए @username और #topic-name use करें.',
      'Pro preview': 'Pro preview',
      'Pro rich text': 'Pro rich text',
      'Publish': 'Publish करें',
      'Other category: {value}': 'Other category: {value}',
      '{count}/2 attachments': '{count}/2 attachments',
      'Require verification': 'Verification required',
      'Community members will be asked to support or challenge this echo':
          'Community members से इस echo को support या challenge करने को कहा जाएगा',
      'Replying to @{username}': '@{username} को reply कर रहे हैं',
      'Reply to @{username}...': '@{username} को reply करें...',
      'Add a reply...': 'Reply जोड़ें...',
      'Search failed. Please try again.':
          'Search failed. कृपया फिर कोशिश करें.',
      'No people found': 'लोग नहीं मिले',
      'Try a username, display name, or profile bio.':
          'Username, display name या profile bio try करें.',
      'No results found': 'कोई result नहीं मिला',
      'Try fewer words, a username, or a phrase from the echo.':
          'कम शब्द, username या echo की phrase try करें.',
      'People': 'लोग',
      'View all': 'सभी देखें',
      'No echoes found': 'Echoes नहीं मिले',
      'Try words from the title or the echo body.':
          'Title या echo body के words try करें.',
      '{count} media': '{count} media',
      'Under Review': 'Review में',
      'The search request could not complete.':
          'Search request complete नहीं हो सकी.',
      'Keep typing': 'Typing जारी रखें',
      'Search Echoproof': 'Echoproof खोजें',
      'Type at least 2 characters': 'कम से कम 2 characters type करें',
      'Find people, echo titles, and proof-backed claims.':
          'लोग, echo titles और proof-backed claims खोजें.',
      'Cancel account setup?': 'Account setup cancel करें?',
      'If you leave now, your account setup will not be complete. You will need to start again next time.':
          'अगर आप अभी छोड़ते हैं, account setup पूरा नहीं होगा. अगली बार फिर शुरू करना होगा.',
      'date of birth': 'जन्मतिथि',
      'Age requirement': 'Age requirement',
      'Echoproof requires users to be at least 13 years old. We cannot create an account for you at this time.':
          'Echoproof के लिए users की उम्र कम से कम 13 साल होनी चाहिए. इस समय हम आपका account create नहीं कर सकते.',
      'Quick profile setup': 'Quick profile setup',
      'This helps us keep Echoproof safe and relevant. None of this is public.':
          'इससे Echoproof safe और relevant रहता है. यह public नहीं है.',
      'Select your date of birth': 'अपनी जन्मतिथि चुनें',
      '{age} yrs': '{age} साल',
      'A few permissions': 'कुछ permissions',
      'Echoproof needs these to work properly. You can change them anytime in your phone settings.':
          'Echoproof को ठीक से चलने के लिए ये permissions चाहिए. आप इन्हें phone settings में कभी भी बदल सकते हैं.',
      'Get notified when your echoes are supported or challenged':
          'जब आपके echoes support या challenge हों तब notification पाएं',
      'Take photos to attach as evidence to your echoes':
          'अपने echoes में evidence के लिए photos लें',
      'Photos': 'Photos',
      'Attach images from your gallery': 'Gallery से images attach करें',
      'Allow permissions': 'Permissions allow करें',
      'A few quick permissions': 'कुछ quick permissions',
      'We only ask for what we actually need. Tap each one to learn why.':
          'हम केवल वही मांगते हैं जो सच में चाहिए. Reason जानने के लिए tap करें.',
      'Allow all and continue': 'सब allow करें और continue',
      'Allowed': 'Allowed',
      'Denied — open settings to allow':
          'Denied — allow करने के लिए settings खोलें',
      'Tap to allow': 'Allow करने के लिए tap करें',
      'Open settings': 'Settings खोलें',
      'Allow': 'Allow',
      'Please complete or cancel verification first.':
          'पहले verification complete या cancel करें.',
      'Could not start verification. Please try again.':
          'Verification start नहीं हो पाया. कृपया फिर कोशिश करें.',
      'You can re-apply after your 30-day cooldown period.':
          'आप 30-day cooldown के बाद फिर apply कर सकते हैं.',
      'Too many attempts today. Please try again tomorrow.':
          'आज बहुत attempts हो गए. कृपया कल कोशिश करें.',
      'Identity verified!': 'Identity verified!',
      'Your identity has been confirmed. Your trust tier has been updated.':
          'आपकी identity confirm हो गई. आपका trust tier update हो गया है.',
      'Your identity has been confirmed. Your trust tier will update shortly.':
          'आपकी identity confirm हो गई. आपका trust tier जल्द update होगा.',
      'Verification declined': 'Verification declined',
      'We could not verify your identity. Please try again with a valid ID.':
          'हम आपकी identity verify नहीं कर सके. Valid ID के साथ फिर कोशिश करें.',
      'Verification Canceled': 'Verification cancel हो गया',
      'Verification failed': 'Verification failed',
      'Great!': 'Great!',
      'Got it': 'समझ गया',
      'Verify identity': 'Identity verify करें',
      'Verify your identity': 'अपनी identity verify करें',
      'What Didit verifies': 'Didit क्या verify करता है',
      'Higher trust weight': 'Higher trust weight',
      'Verified badge': 'Verified badge',
      'Portable reputation': 'Portable reputation',
      'Starting verification...': 'Verification start हो रहा है...',
      'Start verification': 'Verification start करें',
      'Scan ID': 'ID scan करें',
      'Liveness': 'Liveness',
      'Trust update': 'Trust update',
      'New password': 'नया password',
      'Enter new password (min 8 chars)':
          'नया password डालें (कम से कम 8 characters)',
      'Update password': 'Password update करें',
    },
  };
}
