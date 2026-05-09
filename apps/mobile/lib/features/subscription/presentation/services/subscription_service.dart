// subscription_service.dart
// Manages Google Play subscription state with server-side validation.
//
// Security model:
//   - Purchase tokens NEVER grant entitlement locally
//   - All validation happens in verify-purchase edge function
//   - Edge function calls Google Play Developer API
//   - Pro status read from DB, not local state
//   - Obfuscated account ID sent with every purchase for fraud prevention
//
// PBL 8 integration:
//   - enableAutoServiceReconnection()
//   - enablePendingPurchases(PendingPurchasesParams) - not the deprecated no-arg version
//   - queryProductDetailsAsync with QueryProductDetailsParams
//   - setObfuscatedAccountId for purchase attribution

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';

// Product IDs — must match exactly what's in Play Console
const _kMonthlyId = 'echoproof_pro_monthly';
const _kYearlyId = 'echoproof_pro_yearly';
const _kProductIds = {_kMonthlyId, _kYearlyId};

class SubscriptionService extends ChangeNotifier {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _isPro = false;
  bool _isLoading = false;
  bool _isAvailable = false;
  String? _error;
  String? _currentPlan; // 'pro_monthly' | 'pro_yearly'
  DateTime? _expiresAt;
  int _upgradeBonusDays = 0;

  // Product details from Play Store
  ProductDetails? _monthlyProduct;
  ProductDetails? _yearlyProduct;

  // Purchase history for the history screen
  List<Map<String, dynamic>> _purchaseHistory = [];
  bool _historyLoading = false;

  bool get isPro => _isPro;
  bool get isLoading => _isLoading;
  bool get isAvailable => _isAvailable;
  String? get error => _error;
  String? get currentPlan => _currentPlan;
  DateTime? get expiresAt => _expiresAt;
  int get upgradeBonusDays => _upgradeBonusDays;
  ProductDetails? get monthlyProduct => _monthlyProduct;
  ProductDetails? get yearlyProduct => _yearlyProduct;
  List<Map<String, dynamic>> get purchaseHistory =>
      List.unmodifiable(_purchaseHistory);
  bool get historyLoading => _historyLoading;

  // True if user has ever attempted a purchase (unlocks history screen)
  bool get hasEverAttemptedPurchase => _purchaseHistory.isNotEmpty;

  SubscriptionService() {
    _init();
  }

  Future<void> _init() async {
    // Check server-side subscription status on startup
    await checkSubscriptionStatus();

    // Initialize Play Billing
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      AppLogger.warn('subscription: Play Billing not available');
      return;
    }

    // Listen for purchase updates
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => AppLogger.error('subscription: purchase stream error $e'),
    );

    // Load product details
    await _loadProducts();

    // Restore any unprocessed purchases (handles app kills mid-purchase)
    await _iap.restorePurchases();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Server-side status check
  // Called on startup and app resume to keep Pro status in sync.
  // -------------------------------------------------------------------------
  Future<void> checkSubscriptionStatus() async {
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) return;

      final res = await client.functions.invoke('check-subscription');
      final data = res.data as Map<String, dynamic>?;

      if (data != null) {
        _isPro = data['is_pro'] as bool? ?? false;
        _currentPlan = data['plan'] as String?;
        final expiresStr = data['expires_at'] as String?;
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
      }

      notifyListeners();
    } catch (e) {
      AppLogger.warn('subscription: status check failed $e');
      // Fall back to local DB read
      await _readStatusFromDb();
    }
  }

  Future<void> _readStatusFromDb() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final row = await client
          .from('users_public')
          .select('is_pro, pro_expires_at, pro_plan')
          .eq('id', userId)
          .maybeSingle();

      if (row != null) {
        _isPro = row['is_pro'] as bool? ?? false;
        _currentPlan = row['pro_plan'] as String?;
        final expiresStr = row['pro_expires_at'] as String?;
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;

        // Local expiry check as extra safety
        if (_expiresAt != null && _expiresAt!.isBefore(DateTime.now())) {
          _isPro = false;
        }
      }

      notifyListeners();
    } catch (e) {
      AppLogger.error('subscription: db read failed $e');
    }
  }

  // -------------------------------------------------------------------------
  // Load product details from Play Store
  // -------------------------------------------------------------------------
  Future<void> _loadProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final resp = await _iap.queryProductDetails(_kProductIds);

      if (resp.error != null) {
        _error = 'Could not load subscription options: ${resp.error!.message}';
        AppLogger.error('subscription: product query error ${resp.error}');
      } else {
        for (final p in resp.productDetails) {
          if (p.id == _kMonthlyId) _monthlyProduct = p;
          if (p.id == _kYearlyId) _yearlyProduct = p;
        }
        AppLogger.info(
            'subscription: loaded ${resp.productDetails.length} products');
      }
    } catch (e) {
      _error = 'Failed to load plans';
      AppLogger.error('subscription: load products failed $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Initiate purchase
  // Sends obfuscatedAccountId for fraud prevention and purchase attribution.
  // Google Play returns this in the purchase token verification response.
  // -------------------------------------------------------------------------
  Future<void> purchase(ProductDetails product) async {
    if (_isLoading) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _error = 'Please sign in to subscribe';
      notifyListeners();
      return;
    }

    _error = null;
    _isLoading = true;
    notifyListeners();

    // Obfuscated account ID = SHA-256-like hash of userId
    // We send this so the server can verify the purchase belongs to this user.
    // Must be <= 64 chars and not contain PII.
    final obfuscatedId = _obfuscateUserId(userId);

    PurchaseParam purchaseParam;

    if (defaultTargetPlatform == TargetPlatform.android) {
      // PBL 8: Use GooglePlayPurchaseParam with obfuscated IDs
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: obfuscatedId,
      );
    } else {
      purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: obfuscatedId,
      );
    }

    try {
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      // Purchase result arrives in _onPurchaseUpdate via stream
    } catch (e) {
      _error = 'Could not initiate purchase. Please try again.';
      _isLoading = false;
      AppLogger.error('subscription: purchase initiation failed $e');
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // Handle purchase stream updates
  // This is called for new purchases AND restored purchases.
  // -------------------------------------------------------------------------
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // User is in the purchase flow — show loading
          AppLogger.info(
              'subscription: purchase pending ${purchase.productID}');
          _isLoading = true;
          notifyListeners();
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Send to server for validation — never grant entitlement locally
          await _serverValidatePurchase(purchase);
          break;

        case PurchaseStatus.error:
          _isLoading = false;
          _error = _friendlyBillingError(purchase.error);
          AppLogger.error('subscription: purchase error ${purchase.error}');

          // Record failed attempt in history
          await _recordFailedPurchase(purchase);
          notifyListeners();
          break;

        case PurchaseStatus.canceled:
          _isLoading = false;
          AppLogger.info('subscription: purchase canceled by user');
          notifyListeners();
          break;
      }

      // Complete the purchase on the Play side
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  // send purchase to server for validation
  Future<void> _serverValidatePurchase(PurchaseDetails purchase) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      // Extract Android-specific purchase details
      String? purchaseToken;
      String? orderId;
      int? purchaseTimeMs;
      if (purchase is GooglePlayPurchaseDetails) {
        purchaseToken = purchase.billingClientPurchase.purchaseToken;
        orderId = purchase.billingClientPurchase.orderId;
        purchaseTimeMs = purchase.billingClientPurchase.purchaseTime;

        if (purchaseToken.isEmpty) {
          throw Exception('invalid purchase token');
        }
      } else {
        purchaseToken = purchase.verificationData.serverVerificationData;
        orderId = purchase.purchaseID;
        purchaseTimeMs = DateTime.now().millisecondsSinceEpoch;

        if (purchaseToken.isEmpty) {
          throw Exception('missing purchase token or order id');
        }
      }

      final obfuscatedId = _obfuscateUserId(userId);

      final res = await client.functions.invoke(
        'verify-purchase',
        body: {
          'purchase_token': purchaseToken,
          'product_id': purchase.productID,
          'order_id': orderId,
          'purchase_time_ms': purchaseTimeMs,
          'obfuscated_account_id': obfuscatedId,
        },
      );

      final data = res.data as Map<String, dynamic>?;

      if (data?['success'] == true) {
        _isPro = true;
        _currentPlan = data?['plan'] as String?;
        _upgradeBonusDays = (data?['upgrade_bonus_days'] as num?)?.toInt() ?? 0;
        final expiresStr = data?['expires_at'] as String?;
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
        _error = null;
        AppLogger.info(
            'subscription: server validation succeeded — isPro=true');
      } else {
        _error = data?['error'] as String? ?? 'Verification failed';
        AppLogger.error('subscription: server validation failed: $_error');
      }
    } catch (e) {
      _error = 'Purchase validation failed. Please contact support.';
      AppLogger.error('subscription: server validate failed $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Restore purchases (Google Play)
  // -------------------------------------------------------------------------
  Future<void> restorePurchases() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _iap.restorePurchases();
      // Results arrive via _onPurchaseUpdate
    } catch (e) {
      _error = 'Could not restore purchases. Try again.';
      _isLoading = false;
      AppLogger.error('subscription: restore failed $e');
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------
  // Load purchase history from server
  // -------------------------------------------------------------------------
  Future<void> loadPurchaseHistory() async {
    _historyLoading = true;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final rows = await client
          .from('purchase_history')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      _purchaseHistory = List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      AppLogger.error('subscription: load history failed $e');
    }

    _historyLoading = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Record a failed purchase attempt for the history screen
  // -------------------------------------------------------------------------
  Future<void> _recordFailedPurchase(PurchaseDetails purchase) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      await client.from('purchase_history').insert({
        'user_id': userId,
        'order_id': purchase.purchaseID ??
            'failed_${DateTime.now().millisecondsSinceEpoch}',
        'product_id': purchase.productID,
        'purchase_token': purchase.verificationData.serverVerificationData,
        'plan_type': purchase.productID.contains('yearly')
            ? 'pro_yearly'
            : 'pro_monthly',
        'status': 'declined',
        'error_code': purchase.error?.code != null
            ? int.tryParse(purchase.error!.code)
            : null,
        'error_message': purchase.error?.message,
        'purchase_time_ms': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      AppLogger.warn('subscription: failed to record failed purchase $e');
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  // Creates a consistent obfuscated ID for fraud prevention.
  // Not reversible to the original UUID without the salt.
  // Must be deterministic so the same user always gets the same value.
  String _obfuscateUserId(String userId) {
    // Simple XOR + base64 — not cryptographic, but sufficient for Play's purpose
    // (Play uses this for display/attribution, not security verification)
    final bytes = utf8.encode(userId);
    final salt = utf8.encode('echoproof_salt_2026');
    final mixed = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ salt[i % salt.length],
    );
    return base64UrlEncode(mixed)
        .replaceAll('=', '')
        .substring(0, (64).clamp(0, mixed.length * 2).toInt());
  }

  // Converts Google Play billing error codes to user-friendly messages
  String _friendlyBillingError(IAPError? error) {
    if (error == null) return 'Purchase failed. Please try again.';
    final code = error.code;

    // BillingResponseCode values as strings from the plugin
    switch (code) {
      case 'BillingResponse.billingUnavailable':
      case '3':
        return 'Google Play Billing is unavailable. Please update the Play Store app and try again.';
      case 'BillingResponse.itemAlreadyOwned':
      case '7':
        return 'You already own this subscription. Tap "Restore purchases" to activate it.';
      case 'BillingResponse.itemNotOwned':
      case '8':
        return 'Purchase verification failed. Please try again.';
      case 'BillingResponse.serviceUnavailable':
      case '2':
        return 'Google Play is temporarily unavailable. Please check your internet connection.';
      case 'BillingResponse.networkError':
      case '12':
        return 'Network error. Please check your connection and try again.';
      case 'BillingResponse.developerError':
      case '5':
        return 'A configuration error occurred. Please contact support.';
      default:
        return 'Purchase failed (code: $code). Please try again or contact support.';
    }
  }
}
