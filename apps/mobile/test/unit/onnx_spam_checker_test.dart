import 'package:echoproof/core/services/onnx_spam_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnnxSpamChecker fallback checks', () {
    test('empty text is not warned by the quick fallback', () {
      expect(OnnxSpamChecker.quickScore('', ''), 0);
      expect(OnnxSpamChecker.shouldWarnQuick('', ''), isFalse);
    });

    test('repeated promotional link text receives a higher quick score', () {
      final score = OnnxSpamChecker.quickScore(
        'Guaranteed income',
        'FREE MONEY!!! click here https://example.com https://promo.test',
      );

      expect(score, greaterThan(0));
    });

    test('checkText uses fail-safe fallback when ONNX is not enabled',
        () async {
      final result = await OnnxSpamChecker.checkText(
        'Normal update',
        'The city report was published this morning.',
      );

      expect(result.source, 'heuristic');
      expect(result.reason, 'onnx_disabled_for_build');
    });
  });
}
