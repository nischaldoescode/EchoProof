// solana service
// handles on-chain interactions for echoproof
// uses http directly no solana package to avoid version conflicts

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../constants/storage_keys.dart';
import '../utils/logger.dart';

const _rpcUrl = String.fromEnvironment(
  'SOLANA_RPC_URL',
  defaultValue: 'https://api.devnet.solana.com',
);

final RegExp _solanaSignaturePattern = RegExp(
  r'^[1-9A-HJ-NP-Za-km-z]{64,100}$',
);

class SolanaWalletAddress {
  const SolanaWalletAddress(this.base58);
  final String base58;
  @override
  String toString() => base58;
}

class SolanaService {
  SolanaService(this._storage);

  final FlutterSecureStorage _storage;

  Future<SolanaWalletAddress> getWalletAddress() async {
    final stored = await _storage.read(key: StorageKeys.solanaKeypair);

    if (stored != null) {
      AppLogger.debug('solana: loaded existing wallet');
      return SolanaWalletAddress(stored);
    }

    final entropy = DateTime.now().microsecondsSinceEpoch.toString();
    final hash = sha256.convert(utf8.encode(entropy)).toString();
    final address = hash.substring(0, 44);

    await _storage.write(key: StorageKeys.solanaKeypair, value: address);
    AppLogger.info('solana: generated new wallet address');
    return SolanaWalletAddress(address);
  }

  Future<int> getBalance(String walletAddress) async {
    try {
      final response = await http.post(
        Uri.parse(_rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getBalance',
          'params': [
            walletAddress,
            {'commitment': 'confirmed'},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['result']?['value'] as int?) ?? 0;
      }
    } catch (e) {
      AppLogger.error('solana: getBalance failed', e);
    }
    return 0;
  }

  Future<String> writeMemo({
    required String memo,
    required String jwtToken,
  }) async {
    final supabaseUrl = const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'http://127.0.0.1:54321',
    );
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/solana-memo'),
        headers: {
          if (anonKey.isNotEmpty) 'apikey': anonKey,
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'memo': memo}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final sig = data['signature'] as String?;
        if (sig != null) {
          AppLogger.info('solana: memo written tx=$sig');
          return sig;
        }
      }
      final message = response.body.isNotEmpty ? response.body : 'no body';
      throw Exception('solana memo failed (${response.statusCode}): $message');
    } catch (e) {
      AppLogger.error('solana: writeMemo error', e);
      rethrow;
    }
  }

  Future<String> anchorTrustTier({
    required String userId,
    required String trustTier,
    required int trustScore,
    required String jwtToken,
  }) async {
    final memo = 'echoproof:trust:$userId:$trustTier:$trustScore';
    return writeMemo(memo: memo, jwtToken: jwtToken);
  }

  Future<String> createVerifiedEchoRecord({
    required String echoId,
    required String content,
    required double confidenceScore,
    required String jwtToken,
  }) async {
    final contentHash = sha256
        .convert(utf8.encode(content))
        .toString()
        .substring(0, 32);
    final memo =
        'echoproof:verified:$echoId:$contentHash:${confidenceScore.toStringAsFixed(0)}';
    return writeMemo(memo: memo, jwtToken: jwtToken);
  }

  Future<String> mintTruthBond({
    required String echoId,
    required String userId,
    required String jwtToken,
  }) async {
    final memo = 'echoproof:bond:$echoId:$userId';
    return writeMemo(memo: memo, jwtToken: jwtToken);
  }

  /// returns a browser-safe explorer uri for a stored transaction signature.
  ///
  /// transaction signatures are stored as database text, so the app validates
  /// the base58 shape before building the outbound link. this keeps pending,
  /// corrupted, or unexpected rows from becoming arbitrary redirect targets.
  static Uri? explorerUri(String? signature, {String rpcUrl = _rpcUrl}) {
    final normalized = _normalizedSignature(signature);
    if (normalized == null) return null;

    final cluster = _explorerClusterForRpc(rpcUrl);
    if (cluster == null) return null;

    return Uri.https(
      'explorer.solana.com',
      '/tx/$normalized',
      cluster == 'mainnet-beta' ? null : {'cluster': cluster},
    );
  }

  static String explorerUrl(String signature, {String rpcUrl = _rpcUrl}) {
    return explorerUri(signature, rpcUrl: rpcUrl)?.toString() ?? '';
  }

  static bool isValidTransactionSignature(String? signature) {
    return _normalizedSignature(signature) != null;
  }

  static String? _normalizedSignature(String? signature) {
    final value = signature?.trim();
    if (value == null || value.isEmpty) return null;
    if (!_solanaSignaturePattern.hasMatch(value)) return null;
    return value;
  }

  static String? _explorerClusterForRpc(String rpcUrl) {
    final value = rpcUrl.toLowerCase();
    if (value.contains('localhost') || value.contains('127.0.0.1')) {
      return null;
    }
    if (value.contains('mainnet')) return 'mainnet-beta';
    if (value.contains('testnet')) return 'testnet';
    return 'devnet';
  }

  static String shortSignature(String signature) {
    if (signature.length <= 16) return signature;
    return '${signature.substring(0, 8)}...${signature.substring(signature.length - 8)}';
  }

  static String formatSol(int lamports) {
    final sol = lamports / 1000000000;
    return '${sol.toStringAsFixed(4)} SOL';
  }
}
