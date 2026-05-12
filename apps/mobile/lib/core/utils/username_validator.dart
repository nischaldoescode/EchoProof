// username validator
// enforces banned words, format rules, and reserved names

abstract final class UsernameValidator {
  static const _banned = {
    // explicit (base)
    'fuck', 'shit', 'ass', 'asshole', 'bitch', 'cunt', 'dick',
    'cock', 'pussy', 'whore', 'slut', 'bastard', 'damn', 'hell',
    'piss', 'crap', 'bollocks', 'wanker', 'twat', 'tosser',
    'motherfucker', 'fucker', 'fuckface', 'fuckyou', 'bullshit',
    'dumbass', 'jackass', 'smartass', 'badass', 'shithead',

    // explicit variations / common bypasses
    'fuk', 'fck', 'fucc', 'fking', 'fk', 'sh1t', 'sh!t', 'biatch',
    'btch', 'b1tch', 'p0rn', 's3x', 's3xy', 'slutty', 'sltty',
    'wh0re', 'whr', 'd1ck', 'd!ck', 'c0ck', 'c0k', 'pussie',
    'pussi', 'puss', 'assf', 'a55', 'cum', 'cumm', 'suckmy',

    // nsfw (base)
    'naked', 'nude', 'nudes', 'porn', 'sex', 'sexy', 'nsfw',
    'xxx', 'adult', 'erotic', 'fetish', 'kink', 'horny',

    // nsfw variations
    'n00d', 'n00dz', 'pr0n', 'pron', 'xx', 'onlyfans', 'ofans',

    // slurs (base)
    'nigger', 'nigga', 'faggot', 'fag', 'dyke', 'tranny',
    'retard', 'spastic', 'cripple', 'chink', 'gook', 'spic',
    'wetback', 'kike', 'raghead', 'towelhead', 'cracker',

    // slur variations / bypass attempts
    'n1gga', 'n1gger', 'f4g', 'f4gg0t', 'd!ke', 'tr4nny',
    'r3tard', 'sp4stic', 'cr1pple',

    // hate symbols (base)
    'nazi', 'heil', 'kkk', 'isis', 'jihad',

    // variations
    'naz1', 'h3il', '1sis', 'j1had',

    // spam / impersonation
    'admin', 'administrator', 'moderator', 'mod', 'staff',
    'official', 'support', 'help', 'bot', 'robot',
    'echoproof', 'echo_proof', 'echopr00f',

    // impersonation variations
    'adm1n', 'off1cial', 'supp0rt', 'm0derator', 'm0d',

    // reserved
    'root', 'system', 'null', 'undefined', 'test', 'demo',

    // variations
    'r00t', 'sys', 'undef', 'tester', 'demouser',
  };
  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'username is required';
    }

    final clean = value.trim().toLowerCase();

    if (clean.length < 4) return 'minimum 4 characters';
    if (clean.length > 32) return 'maximum 32 characters';

    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(clean)) {
      return 'only lowercase letters, numbers, and underscores';
    }

    if (clean.startsWith('_') || clean.endsWith('_')) {
      return 'cannot start or end with an underscore';
    }

    if (clean.contains('__')) {
      return 'cannot have consecutive underscores';
    }

    // check if any banned word appears in the username
    for (final word in _banned) {
      if (clean.contains(word)) {
        return 'username contains a word that is not allowed';
      }
    }

    return null;
  }
}
