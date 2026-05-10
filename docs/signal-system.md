# signals system

signals are echoproof's equivalent of hashtags.
they use the ~ prefix instead of # to differentiate from standard social media
and reinforce the echo wave brand identity.

## naming

| traditional social | echoproof |
|--------------------|-----------|
| #hashtag | ~signal |
| trending topics | trending signals |
| topic page | signal feed |

## format

signals follow this pattern: ~word or ~multi_word
- tilde prefix (~) required
- lowercase only
- letters, numbers, underscores only
- maximum 32 characters
- maximum 5 per echo

examples: ~web3, ~ai_safety, ~startup_fraud, ~verified_claim

## discovery screen

the discover screen shows trending signals in two modes:

global — signals trending across all countries in the last 24 hours
by country — signals trending within a specific country (iso 3166-1 alpha-2 code)

country is detected from the device locale on first launch.
users can manually switch country in the discover screen.

country detection in flutter:
```dart
import 'dart:io';
final country = Platform.localeName.split('_').last; // e.g. 'IN', 'US'
```

## signal weight

signals are indexed with country_code from the user's locale.
each echo tagged with ~signal adds 1 to that signal's count.
trending is calculated over the last 24 hours.

signals with more echoes from verified users rank higher.
the trending_signals_global and trending_signals_by_country views
handle this automatically.

## signal responses

users can reply to echoes with signal responses (renamed from comments).
each response includes a stance: supporting / neutral / challenging.
this stance contributes to the echo's trust score calculation.

| traditional | echoproof |
|-------------|-----------|
| comment | signal response |
| like comment | amplify response |
| reply | nested signal |