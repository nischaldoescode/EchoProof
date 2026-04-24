// subscription service
// handles in-app purchases for echoproof pro
// uses in_app_purchase package — works on both android (play billing) and ios (storekit)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';

const _kProMonthly  = 'echoproof_pro_monthly';
const _kProYearly   = 'echoproof_pro_yearly';
const _kProductIds  = {_kProMonthly, _kProYearly};

class SubscriptionService extends ChangeNotifier {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool   _isAvailable = false;
  bool   _isPro       = false;
  bool   _isLoading   = true;
  String? _error;

  List<ProductDetails> _products = [];

  bool              get isAvailable => _isAvailable;
  bool              get isPro       => _isPro;
  bool              get isLoading   => _isLoading;
  String?           get error       => _error;
  List<ProductDetails> get products => List.unmodifiable(_products);

  ProductDetails? get monthlyProduct =>
      _products.where((p) => p.id == _kProMonthly).firstOrNull;

  ProductDetails? get yearlyProduct =>
      _products.where((p) => p.id == _kProYearly).firstOrNull;

  SubscriptionService() {
    _initialize();
  }

  Future<void> _initialize() async {
    _isAvailable = await _iap.isAvailable();

    if (!_isAvailable) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    // listen to purchase updates
    _subscription = _iap.purchaseStream.listen(
      _handlePurchases,
      onError: (e) => AppLogger.error('iap stream error', e),
    );

    await Future.wait([
      _loadProducts(),
      _checkExistingSubscription(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(_kProductIds);
      _products = response.productDetails;
    } catch (e) {
      AppLogger.error('iap: load products failed', e);
    }
  }

  Future<void> _checkExistingSubscription() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final result = await client
          .from('subscriptions')
          .select('status, expires_at')
          .eq('user_id', userId)
          .maybeSingle();

      if (result != null) {
        final status    = result['status'] as String?;
        final expiresAt = result['expires_at'] as String?;
        final isExpired = expiresAt != null &&
            DateTime.parse(expiresAt).isBefore(DateTime.now());

        _isPro = status == 'active' && !isExpired;
      }
    } catch (e) {
      AppLogger.error('iap: check subscription failed', e);
    }
  }

  Future<void> purchase(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyAndGrant(purchase);
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    // verify with supabase edge function
    // the edge function validates with Play/AppStore and grants subscription
    final client = Supabase.instance.client;

    try {
      final response = await client.functions.invoke(
        'verify-purchase',
        body: {
          'product_id':           purchase.productID,
          'purchase_token':       purchase.verificationData.serverVerificationData,
          'platform':             defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : 'ios',
        },
      );

      if (response.data?['success'] == true) {
        _isPro = true;
        notifyListeners();
        AppLogger.info('iap: subscription granted');
      }
    } catch (e) {
      AppLogger.error('iap: verify purchase failed', e);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}