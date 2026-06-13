// google play licensing constants
// @params none
// keep licensing material in one place so billing code can reference it safely

import 'dart:convert';

abstract final class PlayLicensing {
  // lightly obfuscated rsa public key from play console licensing
  // this is public key material and server validation is still the source of truth
  static String get publicKey {
    final bytes = base64Decode(_payload);
    final mask = utf8.encode(_mask);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = bytes[i] ^ mask[i % mask.length];
    }
    return utf8.decode(bytes);
  }

  static const _mask = 'echoproof-play-license';
  static const _payload =
      'KCohLTkYLiEkShsdCRJEK1AUVSwyNCAlKS4/MS4+Xmw9JSg7bgsiICQ/NiQLEQIYRAYiNTYcEzs4QWcoGTYRIyRSLDEhPDoVFypUYyRHUxxYFVkUJBYLAQFaAR0aFjZfPlcTWBMQayksDS0UWDY0NFg/HAYeWxJBPxhTAFteKyYiDwoIPBUCPzIoXT8IYTMZNEloGFs1JBQ/VQctMB82Iw0cU0YqCSM3GzQuOwsLSi8mBRkaQh8fNSVHMgcFH0QhAiY2PUJVEA5HFjU1PF4iSAhZF0haFjMEE1c7JxwSMCcxGRY/D3c2JAseGxUNMw8HRTcOFwMNGAc1FzN5IzknKRQjADEzLQYKDzJeHh0zFycSaV8ZME9sKC8lIFslAgBaLi4qCAk1KUQpWSwNHw4uFVQFPFJcLF8jIUM6CSReKlU4AxsBMwg9LSVWKTsrJAlFXSVWWAIWVjZEDVpRUyQeLQoCIykAS1g/MU9DIwcMYl4PJA48QVYgKzkWSUI5XC0CGD0oPWw9KCE=';
}
