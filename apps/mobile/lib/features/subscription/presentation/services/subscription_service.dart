// subscription_service.dart
// manages google play subscription state with server-side validation
// security model:
// purchase tokens never grant entitlement locally
// all validation happens in verify-purchase edge function
// edge function calls google play developer api
// pro status read from db, not local state
// obfuscated account id sent with every purchase for fraud prevention
// pbl 8 integration:
// enableautoservicereconnection()
// enablependingpurchases(pendingpurchasesparams) - not the deprecated no-arg version
// queryproductdetailsasync with queryproductdetailsparams
// setobfuscatedaccountid for purchase attribution

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ReplacementMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/logger.dart';

// product ids must match exactly what's in play console
const _kMonthlyId = 'echoproof_pro_monthly';
const _kYearlyId = 'echoproof_pro_yearly';
const _kMonthlyBasePlanId = 'monthly-auto';
const _kYearlyBasePlanId = 'echoproofpro0yearly';
const _kProductIds = {_kMonthlyId, _kYearlyId};
const _kBillingAvailabilityTimeout = Duration(seconds: 8);
const _kProductQueryTimeout = Duration(seconds: 15);
const _kCheckoutOpenTimeout = Duration(seconds: 20);
const _kRestoreStartTimeout = Duration(seconds: 12);
const _kServerValidationTimeout = Duration(seconds: 30);
const _kProductFreshnessWindow = Duration(minutes: 10);
const _kPurchaseResultGraceAfterResume = Duration(seconds: 2);
const _kShowBillingDiagnostics = bool.fromEnvironment(
  'ECHOPROOF_BILLING_DIAGNOSTICS',
  defaultValue: true,
);

class SubscriptionService extends ChangeNotifier {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool _isPro = false;
  bool _isLoading = false;
  bool _isRestoring = false;
  bool _isAvailable = false;
  String? _error;
  String? _currentPlan; // 'pro_monthly' | 'pro_yearly'
  String? _subscriptionStatus;
  DateTime? _expiresAt;
  int _upgradeBonusDays = 0;
  Completer<void>? _restoreCompleter;
  bool _restoreSawPurchase = false;
  Timer? _purchaseWatchdog;
  GooglePlayPurchaseDetails? _currentGooglePurchase;
  DateTime? _checkoutStartedAt;
  String? _activeCheckoutProductId;
  String? _checkoutDiagnostic;
  int _checkoutDiagnosticSerial = 0;
  int _transientUiEpoch = 0;
  final List<String> _billingDebugLog = [];

  // product details from play store
  ProductDetails? _monthlyProduct;
  ProductDetails? _yearlyProduct;
  DateTime? _productsLoadedAt;

  // purchase history for the history screen
  List<Map<String, dynamic>> _purchaseHistory = [];
  bool _historyLoading = false;

  bool get isPro => _isPro;
  bool get isLoading => _isLoading;
  bool get isRestoring => _isRestoring;
  bool get isAvailable => _isAvailable;
  bool get isCheckoutInProgress => _checkoutStartedAt != null;
  String? get checkoutDiagnostic => _checkoutDiagnostic;
  int get checkoutDiagnosticSerial => _checkoutDiagnosticSerial;
  bool get showBillingDiagnostics => _kShowBillingDiagnostics;
  List<String> get billingDebugLog => List.unmodifiable(_billingDebugLog);
  String? get error => _error;
  String? get currentPlan => _currentPlan;
  String? get subscriptionStatus => _subscriptionStatus;
  DateTime? get expiresAt => _expiresAt;
  int get upgradeBonusDays => _upgradeBonusDays;
  ProductDetails? get monthlyProduct => _monthlyProduct;
  ProductDetails? get yearlyProduct => _yearlyProduct;
  bool get hasLoadedProducts =>
      _monthlyProduct != null || _yearlyProduct != null;
  List<Map<String, dynamic>> get purchaseHistory =>
      List.unmodifiable(_purchaseHistory);
  bool get historyLoading => _historyLoading;

  // true if user has ever attempted a purchase (unlocks history screen)
  bool get hasEverAttemptedPurchase => _purchaseHistory.isNotEmpty;

  SubscriptionService() {
    _init();
  }

  Future<void> _init() async {
    AppLogger.info('subscription: init started');
    _recordBillingEvent('service init started');

    // check server-side subscription status on startup
    await checkSubscriptionStatus();
    AppLogger.info('subscription: startup status check finished');
    _recordBillingEvent('startup subscription status check finished');

    // initialize play billing
    _isAvailable = await _iap.isAvailable().timeout(
      _kBillingAvailabilityTimeout,
      onTimeout: () {
        _recordBillingEvent(
          'billing availability timed out after ${_kBillingAvailabilityTimeout.inSeconds}s',
          notify: true,
        );
        return false;
      },
    );
    AppLogger.info('subscription: play billing available=$_isAvailable');
    _recordBillingEvent('billing availability result=$_isAvailable');
    if (!_isAvailable) {
      AppLogger.warn('subscription: Play Billing not available');
      _recordCheckoutDiagnostic(
        'Google Play Billing is not available on this device yet.',
        notify: false,
      );
      return;
    }

    // listen for purchase updates
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) {
        _recordBillingEvent('purchase stream error $e', notify: true);
        AppLogger.error('subscription: purchase stream error $e');
      },
    );
    _recordBillingEvent('purchase stream listener attached');

    // load product details
    await _loadProducts();

    // restore any unprocessed purchases (handles app kills mid-purchase)
    AppLogger.info('subscription: startup restore requested');
    _recordBillingEvent('startup restore requested');
    await _iap.restorePurchases();
  }

  @override
  void dispose() {
    _purchaseWatchdog?.cancel();
    _purchaseSub?.cancel();
    super.dispose();
  }

  // server-side status check
  // called on startup and app resume to keep pro status in sync
  Future<void> checkSubscriptionStatus() async {
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) return;

      final res = await client.functions.invoke('check-subscription');
      final data = res.data as Map<String, dynamic>?;

      if (data != null) {
        _isPro = data['is_pro'] as bool? ?? false;
        _subscriptionStatus = data['status'] as String?;
        _currentPlan = data['plan'] as String?;
        final expiresStr = data['expires_at'] as String?;
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
        AppLogger.info(
          'subscription: status is_pro=$_isPro plan=$_currentPlan status=$_subscriptionStatus expires=$_expiresAt',
        );
      }

      notifyListeners();
    } catch (e) {
      AppLogger.warn('subscription: status check failed $e');
      // fall back to local db read
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
        _subscriptionStatus = _isPro ? 'active' : null;
        _currentPlan = row['pro_plan'] as String?;
        final expiresStr = row['pro_expires_at'] as String?;
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;

        // local expiry check as extra safety
        if (_expiresAt != null && _expiresAt!.isBefore(DateTime.now())) {
          _isPro = false;
        }
      }

      notifyListeners();
    } catch (e) {
      AppLogger.error('subscription: db read failed $e');
    }
  }

  // load product details from play store
  Future<void> _loadProducts() async {
    final requestEpoch = _transientUiEpoch;
    final timer = Stopwatch()..start();
    _isLoading = true;
    _recordCheckoutDiagnostic(
      'Loading subscription plans from Google Play.',
      notify: false,
    );
    notifyListeners();
    AppLogger.info('subscription: loading products ${_kProductIds.join(',')}');
    _recordBillingEvent('query products start ids=${_kProductIds.join(',')}');

    try {
      if (!ConnectivityService.instance.isOnline) {
        _error =
            'You are offline. Subscription options will load when connected.';
        _recordCheckoutDiagnostic(
          'Plan loading stopped because this device is offline.',
          notify: false,
        );
        _finishLoadingIfCurrent(
          requestEpoch,
          reason: 'product load offline',
        );
        _recordBillingEvent('query products stopped offline', notify: true);
        return;
      }

      final resp = await _iap.queryProductDetails(_kProductIds).timeout(
        _kProductQueryTimeout,
        onTimeout: () {
          throw TimeoutException(
            'google play product query timed out',
            _kProductQueryTimeout,
          );
        },
      );
      AppLogger.info(
        'subscription: product query returned products=${resp.productDetails.length} not_found=${resp.notFoundIDs.join(',')} error=${resp.error} elapsed_ms=${timer.elapsedMilliseconds}',
      );
      _recordBillingEvent(
        'query products returned count=${resp.productDetails.length} not_found=${resp.notFoundIDs.join(',').ifEmpty('none')} elapsed_ms=${timer.elapsedMilliseconds}',
        notify: true,
      );
      _recordBillingEvent(
        'query products details=${resp.productDetails.map((p) => '${p.id}:${_basePlanIdFor(p) ?? 'base-none'}').join('|').ifEmpty('none')}',
        notify: true,
      );
      _recordCheckoutDiagnostic(
        'Google Play returned ${resp.productDetails.length} plan${resp.productDetails.length == 1 ? '' : 's'} for this device.',
        notify: false,
      );

      if (resp.error != null) {
        _error = 'Could not load subscription options. Please try again.';
        _recordBillingEvent(
          'query products error ${_iapErrorText(resp.error)}',
          notify: true,
        );
        _recordCheckoutDiagnostic(
          'Google Play plan loading failed before checkout could open.',
          notify: false,
        );
        AppLogger.error('subscription: product query error ${resp.error}');
      } else {
        _monthlyProduct = _pickPlanProduct(
          resp.productDetails,
          productId: _kMonthlyId,
          basePlanId: _kMonthlyBasePlanId,
        );
        _yearlyProduct = _pickPlanProduct(
          resp.productDetails,
          productId: _kYearlyId,
          basePlanId: _kYearlyBasePlanId,
        );
        _productsLoadedAt = DateTime.now();
        AppLogger.info(
            'subscription: loaded ${resp.productDetails.length} products');
        AppLogger.info(
          'subscription: monthly=${_monthlyProduct?.id} monthly_base=${_monthlyProduct == null ? null : _basePlanIdFor(_monthlyProduct!)} yearly=${_yearlyProduct?.id} yearly_base=${_yearlyProduct == null ? null : _basePlanIdFor(_yearlyProduct!)}',
        );
        _recordBillingEvent(
          'selected monthly=${_monthlyProduct?.id ?? 'missing'} base=${_monthlyProduct == null ? 'missing' : _basePlanIdFor(_monthlyProduct!) ?? 'none'} yearly=${_yearlyProduct?.id ?? 'missing'} base=${_yearlyProduct == null ? 'missing' : _basePlanIdFor(_yearlyProduct!) ?? 'none'}',
          notify: true,
        );
        if (resp.notFoundIDs.isNotEmpty) {
          _error =
              'Google Play has not published all Pro plans to this device yet.';
          _recordCheckoutDiagnostic(
            'Some Pro plans are not visible to this Play account yet.',
            notify: false,
          );
          AppLogger.warn(
              'subscription: products not found ${resp.notFoundIDs.join(',')}');
          _recordBillingEvent(
            'query products missing ids=${resp.notFoundIDs.join(',')}',
            notify: true,
          );
        } else {
          _error = null;
        }
      }
    } on TimeoutException catch (e) {
      _error =
          'Google Play is taking too long to load Pro plans. Reopen this screen or update Play Store.';
      _recordCheckoutDiagnostic(
        'Plan loading timed out after ${_kProductQueryTimeout.inSeconds}s before checkout could open.',
        notify: true,
      );
      _recordBillingEvent(
        'query products timeout elapsed_ms=${timer.elapsedMilliseconds} error=$e',
        notify: true,
      );
    } catch (e) {
      _error = 'Failed to load plans';
      _recordCheckoutDiagnostic(
        'Plan loading crashed before checkout could open.',
        notify: false,
      );
      AppLogger.error('subscription: load products failed $e');
      _recordBillingEvent('query products crashed $e', notify: true);
    }

    _finishLoadingIfCurrent(requestEpoch, reason: 'product load finished');
  }

  // reloads play products when console setup has just changed
  Future<void> reloadProducts() => _loadProducts();

  // initiate purchase
  // sends obfuscatedaccountid for fraud prevention and purchase attribution
  // google play returns this in the purchase token verification response
  Future<void> purchase(ProductDetails product) async {
    final timer = Stopwatch()..start();
    var checkoutProduct = product;
    AppLogger.info(
      'subscription: purchase requested product=${product.id} loading=$_isLoading available=$_isAvailable',
    );
    _recordBillingEvent(
      'purchase tapped product=${product.id} loading=$_isLoading available=$_isAvailable',
      notify: true,
    );
    if (_isLoading) {
      AppLogger.warn('subscription: purchase ignored because service is busy');
      _recordBillingEvent('purchase ignored because service is busy');
      return;
    }

    if (!ConnectivityService.instance.isOnline) {
      AppLogger.warn('subscription: purchase blocked offline');
      _error = 'You are offline. Connect to the internet before checkout.';
      _recordCheckoutDiagnostic(
        'Checkout did not start because this device is offline.',
        notify: true,
      );
      _recordBillingEvent('purchase blocked offline', notify: true);
      notifyListeners();
      return;
    }

    if (!_isAvailable) {
      AppLogger.warn('subscription: purchase blocked billing unavailable');
      _error = 'Google Play Billing is not available on this device yet.';
      _recordCheckoutDiagnostic(
        'Checkout did not start because Play Billing is unavailable.',
        notify: true,
      );
      _recordBillingEvent('purchase blocked billing unavailable', notify: true);
      notifyListeners();
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      AppLogger.warn('subscription: purchase blocked no signed-in user');
      _error = 'Please sign in to subscribe';
      _recordCheckoutDiagnostic(
        'Checkout did not start because there is no signed-in user.',
        notify: true,
      );
      _recordBillingEvent('purchase blocked no signed-in user', notify: true);
      notifyListeners();
      return;
    }

    if (_productDetailsAreStale) {
      _recordBillingEvent(
        'refreshing stale product before checkout product=${product.id}',
        notify: true,
      );
      _recordCheckoutDiagnostic(
        'Refreshing the Pro plan with Google Play before checkout.',
        notify: true,
      );
      await _loadProducts();
      final freshProduct =
          product.id == _kYearlyId ? _yearlyProduct : _monthlyProduct;
      if (freshProduct == null) {
        _error ??= 'Google Play could not refresh this Pro plan. Try again.';
        _recordCheckoutDiagnostic(
          'Checkout stopped because Google Play did not return a fresh plan.',
          notify: true,
        );
        _recordBillingEvent('purchase stopped no fresh product', notify: true);
        notifyListeners();
        return;
      }
      if (_productDetailsAreStale) {
        _error = 'Google Play could not refresh this Pro plan. Try again.';
        _recordCheckoutDiagnostic(
          'Checkout stopped because the Play plan refresh did not complete.',
          notify: true,
        );
        _recordBillingEvent(
          'purchase stopped product refresh did not update timestamp',
          notify: true,
        );
        notifyListeners();
        return;
      }
      checkoutProduct = freshProduct;
      _error = null;
    }

    final targetPlan =
        checkoutProduct.id.contains('yearly') ? 'pro_yearly' : 'pro_monthly';
    AppLogger.info(
      'subscription: target plan=$targetPlan current_plan=$_currentPlan is_pro=$_isPro',
    );
    _recordBillingEvent(
      'target plan=$targetPlan current=$_currentPlan is_pro=$_isPro',
      notify: true,
    );
    if (_isPro && _currentPlan == targetPlan) {
      AppLogger.info('subscription: purchase blocked same active plan');
      _error = 'You already have this Pro plan active.';
      _recordBillingEvent('purchase blocked same active plan', notify: true);
      notifyListeners();
      return;
    }
    if (_isPro && _currentPlan == 'pro_yearly' && targetPlan == 'pro_monthly') {
      AppLogger.info('subscription: purchase blocked yearly to monthly');
      _error = 'Yearly Pro is already active. Manage changes in Google Play.';
      _recordBillingEvent('purchase blocked yearly to monthly', notify: true);
      notifyListeners();
      return;
    }

    _error = null;
    _isLoading = true;
    _checkoutStartedAt = DateTime.now();
    _activeCheckoutProductId = checkoutProduct.id;
    _recordCheckoutDiagnostic(
      'Opening Google Play checkout for ${_planLabelForProduct(checkoutProduct.id)}.',
      notify: true,
    );
    notifyListeners();

    Timer? slowOpenTimer;
    try {
      // google play accepts an obfuscated account id up to 64 chars
      // prepare it inside the guarded checkout block so sync prep failures
      // cannot leave a fake pending checkout behind
      final obfuscatedId = _obfuscateUserId(userId);
      _recordBillingEvent(
        'obfuscated account id prepared length=${obfuscatedId.length}',
        notify: true,
      );

      PurchaseParam purchaseParam;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final changeParam = _changeParamFor(checkoutProduct);
        if (_currentPlan == 'pro_monthly' &&
            targetPlan == 'pro_yearly' &&
            changeParam == null) {
          _clearCheckoutTracking();
          _error =
              'Restore your current monthly purchase first, then upgrade to yearly.';
          _recordCheckoutDiagnostic(
            'Yearly upgrade needs the current monthly purchase restored first.',
            notify: false,
          );
          _isLoading = false;
          _recordBillingEvent(
            'purchase blocked upgrade missing old monthly purchase',
            notify: true,
          );
          notifyListeners();
          return;
        }

        // pbl 8 uses googleplaypurchaseparam with obfuscated ids and offers
        AppLogger.info(
          'subscription: android purchase param product=${checkoutProduct.id} base_plan=${_basePlanIdFor(checkoutProduct)} has_offer=${_offerTokenFor(checkoutProduct) != null} has_change=${changeParam != null}',
        );
        _recordBillingEvent(
          'checkout params product=${checkoutProduct.id} base=${_basePlanIdFor(checkoutProduct) ?? 'none'} offer=${_offerTokenFor(checkoutProduct) != null} change=${changeParam != null}',
          notify: true,
        );
        purchaseParam = GooglePlayPurchaseParam(
          productDetails: checkoutProduct,
          applicationUserName: obfuscatedId,
          changeSubscriptionParam: changeParam,
          offerToken: _offerTokenFor(checkoutProduct),
        );
      } else {
        purchaseParam = PurchaseParam(
          productDetails: checkoutProduct,
          applicationUserName: obfuscatedId,
        );
      }

      _startPurchaseWatchdog();
      slowOpenTimer = Timer(const Duration(seconds: 4), () {
        if (_checkoutStartedAt == null || !_isLoading) return;
        _recordCheckoutDiagnostic(
          'Google Play is still opening checkout. Play Store may be checking the account or plan.',
          notify: true,
        );
      });
      _recordCheckoutDiagnostic(
        'Sent checkout request to Google Play.',
        notify: true,
      );
      AppLogger.info('subscription: opening google play checkout');
      _recordBillingEvent('launching google play checkout', notify: true);
      final opened = await _iap
          .buyNonConsumable(purchaseParam: purchaseParam)
          .timeout(_kCheckoutOpenTimeout, onTimeout: () {
        _recordBillingEvent(
          'checkout open timeout product=$_activeCheckoutProductId elapsed_ms=${timer.elapsedMilliseconds}',
          notify: true,
        );
        _recordCheckoutDiagnostic(
          'Google Play did not open checkout within ${_kCheckoutOpenTimeout.inSeconds}s. If Play confirms payment later, Pro will activate automatically.',
          notify: true,
        );
        return false;
      });
      slowOpenTimer.cancel();
      AppLogger.info(
        'subscription: buyNonConsumable returned opened=$opened elapsed_ms=${timer.elapsedMilliseconds}',
      );
      _recordBillingEvent(
        'checkout open returned opened=$opened elapsed_ms=${timer.elapsedMilliseconds}',
        notify: true,
      );
      if (!opened) {
        _clearCheckoutTracking();
        _isLoading = false;
        _error =
            'Google Play checkout did not open. Update Play Store or try again.';
        _recordCheckoutDiagnostic(
          'Google Play did not confirm that a checkout window opened. No charge was confirmed in the app.',
          notify: false,
        );
        _recordBillingEvent('checkout open returned false', notify: true);
        notifyListeners();
      } else {
        _recordCheckoutDiagnostic(
          'Google Play checkout opened in ${timer.elapsedMilliseconds}ms. Waiting for purchase, cancel, or error.',
          notify: true,
        );
        _recordBillingEvent(
          'checkout marked opened waiting for purchase stream',
          notify: true,
        );
      }
      // purchase result arrives in _onpurchaseupdate via stream
    } catch (e, stack) {
      _clearCheckoutTracking();
      _error = 'Could not initiate purchase. Please try again.';
      _isLoading = false;
      _recordCheckoutDiagnostic(
        'Checkout failed before Google Play could take over.',
        notify: false,
      );
      AppLogger.error('subscription: purchase initiation failed', e, stack);
      _recordBillingEvent('purchase initiation exception $e', notify: true);
      notifyListeners();
    } finally {
      slowOpenTimer?.cancel();
    }
  }

  // handle purchase stream updates
  // this is called for new purchases and restored purchases
  void _completeRestoreWait({required bool sawPurchase}) {
    final completer = _restoreCompleter;
    if (completer == null) return;

    _restoreSawPurchase = _restoreSawPurchase || sawPurchase;
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    AppLogger.info(
      'subscription: purchase stream received count=${purchases.length}',
    );
    _recordBillingEvent(
      'purchase stream received count=${purchases.length}',
      notify: true,
    );
    for (final purchase in purchases) {
      AppLogger.info(
        'subscription: purchase update product=${purchase.productID} status=${purchase.status.name} pending_complete=${purchase.pendingCompletePurchase}',
      );
      _recordBillingEvent(
        'purchase stream update product=${purchase.productID} status=${purchase.status.name} pending_complete=${purchase.pendingCompletePurchase} error=${_iapErrorText(purchase.error)}',
        notify: true,
      );
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _clearCheckoutTracking();
          // user is in the purchase flow show loading
          AppLogger.info(
              'subscription: purchase pending ${purchase.productID}');
          _isLoading = false;
          _error =
              'Payment is pending. Pro will activate after Google confirms it.';
          _recordCheckoutDiagnostic(
            'Google Play marked the payment pending. Pro activates after confirmation.',
            notify: false,
          );
          _recordBillingEvent('purchase pending recorded', notify: true);
          await _recordPendingPurchase(purchase);
          notifyListeners();
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _clearCheckoutTracking();
          _recordCheckoutDiagnostic(
            'Google Play returned a purchase. Validating it with Echoproof.',
            notify: true,
          );
          if (purchase is GooglePlayPurchaseDetails) {
            _currentGooglePurchase = purchase;
          }
          _recordBillingEvent(
            'purchase confirmed by stream status=${purchase.status.name}',
            notify: true,
          );
          // send to server for validation never grant entitlement locally
          await _serverValidatePurchase(purchase);
          _completeRestoreWait(sawPurchase: true);
          break;

        case PurchaseStatus.error:
          _clearCheckoutTracking();
          _isLoading = false;
          _error = _friendlyBillingError(purchase.error);
          _recordCheckoutDiagnostic(
            'Google Play returned an error before Pro could activate.',
            notify: false,
          );
          AppLogger.error('subscription: purchase error ${purchase.error}');
          _recordBillingEvent(
            'purchase stream error ${_iapErrorText(purchase.error)}',
            notify: true,
          );

          // record failed attempt in history
          await _recordFailedPurchase(purchase);
          _completeRestoreWait(sawPurchase: false);
          notifyListeners();
          break;

        case PurchaseStatus.canceled:
          _clearCheckoutTracking();
          _isLoading = false;
          _error = 'Checkout was cancelled. You were not charged.';
          _recordCheckoutDiagnostic(
            'Google Play reported checkout cancelled. No charge was confirmed.',
            notify: false,
          );
          AppLogger.info('subscription: purchase canceled by user');
          _recordBillingEvent('purchase stream canceled', notify: true);
          _completeRestoreWait(sawPurchase: false);
          notifyListeners();
          break;
      }

      // complete the purchase on the play side
      if (purchase.pendingCompletePurchase) {
        AppLogger.info(
          'subscription: completing purchase product=${purchase.productID}',
        );
        _recordBillingEvent(
          'complete purchase called product=${purchase.productID}',
          notify: true,
        );
        await _iap.completePurchase(purchase);
      }
    }
  }

  // send purchase to server for validation
  Future<void> _serverValidatePurchase(PurchaseDetails purchase) async {
    try {
      AppLogger.info(
        'subscription: validating purchase product=${purchase.productID}',
      );
      _recordBillingEvent(
        'server validation start product=${purchase.productID}',
        notify: true,
      );
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      // extract android-specific purchase details
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
      ).timeout(_kServerValidationTimeout);

      final data = res.data as Map<String, dynamic>?;

      if (data?['success'] == true) {
        _isPro = true;
        _subscriptionStatus = 'active';
        _currentPlan = data?['plan'] as String?;
        _upgradeBonusDays = (data?['upgrade_bonus_days'] as num?)?.toInt() ?? 0;
        final expiresStr = data?['expires_at'] as String?;
        _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
        _error = null;
        _recordCheckoutDiagnostic(
          'Server validation succeeded. Echoproof Pro is active.',
          notify: false,
        );
        AppLogger.info(
            'subscription: server validation succeeded — isPro=true');
        _recordBillingEvent(
          'server validation success plan=$_currentPlan expires=$_expiresAt',
          notify: true,
        );
      } else {
        _error = data?['error'] as String? ?? 'Verification failed';
        _recordCheckoutDiagnostic(
          'Server validation rejected the purchase response.',
          notify: false,
        );
        AppLogger.error('subscription: server validation failed: $_error');
        _recordBillingEvent('server validation rejected $_error', notify: true);
      }
    } on TimeoutException catch (e) {
      _error =
          'Purchase reached Google Play, but validation timed out. Pro will activate after the server confirms it.';
      _recordCheckoutDiagnostic(
        'Echoproof validation timed out after ${_kServerValidationTimeout.inSeconds}s.',
        notify: false,
      );
      _recordBillingEvent('server validation timeout $e', notify: true);
    } catch (e) {
      _error = 'Purchase validation failed. Please contact support.';
      _recordCheckoutDiagnostic(
        'Server validation could not finish. Contact support if Play charged you.',
        notify: false,
      );
      AppLogger.error('subscription: server validate failed $e');
      _recordBillingEvent('server validation exception $e', notify: true);
    }

    _isLoading = false;
    notifyListeners();
  }

  // restore purchases (google play)
  Future<void> restorePurchases() async {
    AppLogger.info(
      'subscription: restore requested loading=$_isLoading available=$_isAvailable',
    );
    _recordBillingEvent(
      'restore tapped loading=$_isLoading available=$_isAvailable',
      notify: true,
    );
    if (_isLoading) {
      AppLogger.warn('subscription: restore ignored because service is busy');
      return;
    }

    if (!ConnectivityService.instance.isOnline) {
      _error = 'You are offline. Connect to the internet before restoring.';
      _recordCheckoutDiagnostic(
        'Restore did not start because this device is offline.',
        notify: true,
      );
      notifyListeners();
      return;
    }

    if (!_isAvailable) {
      _error = 'Google Play Billing is not available on this device yet.';
      _recordCheckoutDiagnostic(
        'Restore did not start because Play Billing is unavailable.',
        notify: true,
      );
      notifyListeners();
      return;
    }

    final restoreCompleter = Completer<void>();
    final restoreEpoch = _transientUiEpoch;
    _restoreCompleter = restoreCompleter;
    _restoreSawPurchase = false;
    _isRestoring = true;
    _isLoading = true;
    _error = null;
    _recordCheckoutDiagnostic(
      'Asking Google Play for previous Pro purchases.',
      notify: false,
    );
    notifyListeners();

    try {
      await _iap.restorePurchases().timeout(_kRestoreStartTimeout);
      _recordBillingEvent('restore request sent to google play', notify: true);
      // google play emits restored purchases through purchasestream. if there
      // are no previous purchases, no event may arrive, so do not wait forever
      await restoreCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );

      if (_transientUiEpoch == restoreEpoch && !_restoreSawPurchase) {
        _error = 'No previous Pro purchase found to restore.';
        _recordCheckoutDiagnostic(
          'Google Play did not return a previous Pro purchase.',
          notify: false,
        );
      } else if (_transientUiEpoch != restoreEpoch) {
        AppLogger.info('subscription: restore result ignored after ui release');
        _recordBillingEvent('restore ignored after ui release');
      }
    } catch (e) {
      if (_transientUiEpoch == restoreEpoch) {
        _error = 'Could not restore purchases. Try again.';
        _recordCheckoutDiagnostic(
          'Restore failed before Google Play returned a usable result.',
          notify: false,
        );
      }
      AppLogger.error('subscription: restore failed $e');
      _recordBillingEvent('restore failed $e', notify: true);
    } finally {
      if (identical(_restoreCompleter, restoreCompleter)) {
        _restoreCompleter = null;
        _restoreSawPurchase = false;
      }
      _isRestoring = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  // load purchase history from server
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

  // record a failed purchase attempt for the history screen
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

  Future<void> _recordPendingPurchase(PurchaseDetails purchase) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      await client.from('purchase_history').upsert({
        'user_id': userId,
        'order_id': purchase.purchaseID ??
            'pending_${DateTime.now().millisecondsSinceEpoch}',
        'product_id': purchase.productID,
        'purchase_token': purchase.verificationData.serverVerificationData,
        'plan_type': _planTypeForProductId(purchase.productID),
        'status': 'pending',
        'purchase_time_ms': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'order_id');
    } catch (e) {
      AppLogger.warn('subscription: failed to record pending purchase $e');
    }
  }

  // helpers

  // records a safe billing event for internal test builds
  // never include purchase tokens, order ids, emails, or raw user ids here
  void _recordBillingEvent(String message, {bool notify = false}) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.twoDigits}:${now.minute.twoDigits}:${now.second.twoDigits}';
    final line = '$stamp  $message';
    _billingDebugLog.add(line);
    if (_billingDebugLog.length > 28) {
      _billingDebugLog.removeRange(0, _billingDebugLog.length - 28);
    }
    AppLogger.audit('subscription api: $message');
    if (notify && _kShowBillingDiagnostics) notifyListeners();
  }

  // formats plugin errors without exposing sensitive purchase payloads
  String _iapErrorText(IAPError? error) {
    if (error == null) return 'none';
    final details = error.details;
    final detailsText = details == null ? 'none' : details.toString();
    return 'source=${error.source} code=${error.code} message=${error.message} details=$detailsText';
  }

  bool get _productDetailsAreStale {
    final loadedAt = _productsLoadedAt;
    if (loadedAt == null) return true;
    return DateTime.now().difference(loadedAt) > _kProductFreshnessWindow;
  }

  ProductDetails? _pickPlanProduct(
    List<ProductDetails> products, {
    required String productId,
    required String basePlanId,
  }) {
    final matchingProductIds = products.where((p) => p.id == productId);

    for (final product in matchingProductIds) {
      if (_basePlanIdFor(product) == basePlanId) return product;
    }

    return matchingProductIds.isEmpty ? null : matchingProductIds.first;
  }

  String? _basePlanIdFor(ProductDetails product) {
    if (product is! GooglePlayProductDetails) return null;
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) return null;
    return offers[index].basePlanId;
  }

  String? _offerTokenFor(ProductDetails product) {
    if (product is GooglePlayProductDetails) return product.offerToken;
    return null;
  }

  ChangeSubscriptionParam? _changeParamFor(ProductDetails product) {
    final oldPurchase = _currentGooglePurchase;
    if (oldPurchase == null) return null;
    if (oldPurchase.productID == product.id) return null;
    if (_currentPlan != 'pro_monthly' || !product.id.contains('yearly')) {
      return null;
    }

    return ChangeSubscriptionParam(
      oldPurchaseDetails: oldPurchase,
      replacementMode: ReplacementMode.withTimeProration,
    );
  }

  String _planTypeForProductId(String productId) {
    return productId.contains('yearly') ? 'pro_yearly' : 'pro_monthly';
  }

  String _planLabelForProduct(String productId) {
    return productId.contains('yearly') ? 'Yearly Pro' : 'Monthly Pro';
  }

  void _recordCheckoutDiagnostic(String message, {required bool notify}) {
    _checkoutDiagnostic = message;
    _checkoutDiagnosticSerial++;
    AppLogger.info('subscription diagnostic: $message');
    if (notify) notifyListeners();
  }

  void _startPurchaseWatchdog() {
    _purchaseWatchdog?.cancel();
    AppLogger.info(
      'subscription: checkout watchdog armed product=$_activeCheckoutProductId',
    );
    _purchaseWatchdog = Timer(const Duration(minutes: 2), () {
      if (!_isLoading) return;
      _isLoading = false;
      _checkoutStartedAt = null;
      _activeCheckoutProductId = null;
      _error =
          'Google Play did not send a checkout result. You were not confirmed as charged in the app. If Play later confirms payment, Pro will activate automatically.';
      _recordCheckoutDiagnostic(_error!, notify: false);
      AppLogger.warn('subscription: checkout watchdog fired');
      notifyListeners();
    });
  }

  // clears subscribe-screen loaders without cancelling google play work
  void releaseCheckoutUi({required String reason}) {
    releaseTransientLoadingUi(reason: reason);
  }

  // clears subscribe-screen loaders without cancelling google play work
  void releaseTransientLoadingUi({required String reason}) {
    if (!_isLoading && !_isRestoring && _checkoutStartedAt == null) return;

    _transientUiEpoch++;
    AppLogger.info(
      'subscription: transient ui released reason=$reason loading=$_isLoading restoring=$_isRestoring checkout=${_checkoutStartedAt != null} product=$_activeCheckoutProductId',
    );
    _clearCheckoutTracking();
    _completeRestoreWait(sawPurchase: false);
    _restoreCompleter = null;
    _restoreSawPurchase = false;
    _isRestoring = false;
    _isLoading = false;
    _error = null;
    _checkoutDiagnostic = null;
    _checkoutDiagnosticSerial++;
    notifyListeners();
  }

  // handles focus returning from the native google play billing surface
  // this can happen even when the user never manually backgrounds the app
  // android treats the play checkout as an external billing surface
  // if no purchase stream event arrives after a short grace window, the app
  // clears the loader and records a safe internal diagnostic
  Future<void> recoverCheckoutAfterResume() async {
    final startedAt = _checkoutStartedAt;
    final productId = _activeCheckoutProductId;
    if (startedAt == null || !_isLoading || _isRestoring) {
      await checkSubscriptionStatus();
      return;
    }

    final ageMs = DateTime.now().difference(startedAt).inMilliseconds;
    AppLogger.info(
      'subscription: resume while checkout pending product=$productId age_ms=$ageMs',
    );
    _recordBillingEvent(
      'resume while checkout pending product=$productId age_ms=$ageMs',
      notify: true,
    );
    _recordCheckoutDiagnostic(
      'Returned from Google Play after ${(ageMs / 1000).round()}s. Checking Pro status.',
      notify: true,
    );

    await checkSubscriptionStatus();
    if (_isPro || !_isLoading || _checkoutStartedAt != startedAt) return;

    await Future<void>.delayed(_kPurchaseResultGraceAfterResume);
    if (_isPro || !_isLoading || _checkoutStartedAt != startedAt) return;

    _clearCheckoutTracking();
    _isLoading = false;
    _error =
        'Checkout closed before Google Play sent a purchase result. No charge was confirmed in the app. If Play confirms payment later, Pro will activate automatically.';
    _recordBillingEvent(
      'checkout returned without stream result product=$productId age_ms=$ageMs',
      notify: true,
    );
    _recordCheckoutDiagnostic(
      'Checkout closed without a confirmed purchase result from Google Play.',
      notify: true,
    );
    notifyListeners();
  }

  void _clearCheckoutTracking() {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = null;
    _checkoutStartedAt = null;
    _activeCheckoutProductId = null;
  }

  void _finishLoadingIfCurrent(int requestEpoch, {required String reason}) {
    if (_transientUiEpoch != requestEpoch) {
      AppLogger.info(
        'subscription: $reason finished after ui release epoch=$requestEpoch current=$_transientUiEpoch',
      );
      return;
    }

    _isLoading = false;
    notifyListeners();
  }

  // creates a consistent obfuscated id for google play fraud checks
  // this is deterministic and contains no plain user id or email
  // google play requires at most 64 characters
  String _obfuscateUserId(String userId) {
    final bytes = utf8.encode('echoproof_play_billing:$userId');
    return sha256.convert(bytes).toString();
  }

  // converts google play billing error codes to user-friendly messages
  String _friendlyBillingError(IAPError? error) {
    if (error == null) return 'Purchase failed. Please try again.';
    final code = error.code;

    // billingresponsecode values as strings from the plugin
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

extension _BillingIntFormat on int {
  String get twoDigits => toString().padLeft(2, '0');
}

extension _BillingStringFormat on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
