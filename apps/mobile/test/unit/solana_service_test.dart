import 'dart:io';

import 'package:echoproof/core/services/solana_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('solana explorer links', () {
    test('uses devnet by default so anchored debug records open correctly', () {
      final signature = List.filled(88, '1').join();

      final uri = SolanaService.explorerUri(signature);

      expect(
        uri.toString(),
        'https://explorer.solana.com/tx/$signature?cluster=devnet',
      );
    });

    test('does not build outbound links from malformed signatures', () {
      expect(SolanaService.explorerUri(''), isNull);
      expect(SolanaService.explorerUri('https://example.com/tx/abc'), isNull);
      expect(SolanaService.explorerUri('not a transaction signature'), isNull);
    });

    test('keeps mainnet urls on the explorer default cluster', () {
      final signature = List.filled(88, '2').join();

      final uri = SolanaService.explorerUri(
        signature,
        rpcUrl: 'https://api.mainnet-beta.solana.com',
      );

      expect(uri.toString(), 'https://explorer.solana.com/tx/$signature');
    });

    test('does not redirect local validator records to a public cluster', () {
      final signature = List.filled(88, '3').join();

      final uri = SolanaService.explorerUri(
        signature,
        rpcUrl: 'http://127.0.0.1:8899',
      );

      expect(uri, isNull);
    });

    test('detail widgets only open validated explorer records', () {
      final statusChip = File(
        'lib/features/echo/presentation/widgets/solana_status_chip.dart',
      ).readAsStringSync();
      final verifiedRecord = File(
        'lib/features/echo/presentation/widgets/verified_echo_record.dart',
      ).readAsStringSync();
      final detailScreen = File(
        'lib/features/echo/presentation/screens/echo_detail_screen.dart',
      ).readAsStringSync();
      final linkLauncher = File(
        'lib/core/utils/link_launcher.dart',
      ).readAsStringSync();

      expect(
        statusChip,
        contains('final hasOpenableSignature = explorerUri != null'),
      );
      expect(statusChip, contains("anchoredWithoutLink"));
      expect(statusChip, contains('launchExternalUrlWithFallback'));
      expect(verifiedRecord, contains('launchExternalUrlWithFallback'));
      expect(detailScreen, contains('final anchored = explorerUri != null'));
      expect(detailScreen, contains('launchExternalUrlWithFallback'));
      expect(linkLauncher, contains('LaunchMode.externalApplication'));
      expect(linkLauncher, contains('LaunchMode.inAppBrowserView'));
      expect(
        detailScreen,
        isNot(contains('final anchored = echo.createdRecordTx?.isNotEmpty')),
      );
    });
  });
}
