
// solana record retry service
// @params none

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/logger.dart';

class SolanaRecordRetryService {
  const SolanaRecordRetryService._();

  static Future<String?> retryEchoCreation(String echoId) {
    return _retry(
      kind: 'echo_created',
      body: {'echo_id': echoId},
    );
  }

  static Future<String?> retryEchoVerification(String echoId) {
    return _retry(
      kind: 'echo_verified',
      body: {'echo_id': echoId},
    );
  }

  static Future<String?> retryProof(String proofId) {
    return _retry(
      kind: 'proof_created',
      body: {'proof_id': proofId},
    );
  }

  static Future<String?> retryTruthBond(String bondId) {
    return _retry(
      kind: 'truth_bond',
      body: {'bond_id': bondId},
    );
  }

  static Future<String?> _retry({
    required String kind,
    required Map<String, String> body,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'solana-memo',
      body: {
        'kind': kind,
        ...body,
      },
    );
    final data = response.data;
    AppLogger.info('solana retry: $kind response=$data');
    if (data is Map<String, dynamic>) {
      final signature = data['signature'];
      return signature is String && signature.isNotEmpty ? signature : null;
    }
    if (data is Map) {
      final signature = data['signature'];
      return signature is String && signature.isNotEmpty ? signature : null;
    }
    return null;
  }
}
