// purchase_history_screen.dart
// shows all purchase attempts with status, error codes, and invoice download
// only accessible to users who have at least attempted a purchase
// pro-only for full history; all users see their own failed attempts

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../services/subscription_service.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/utils/snack.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionService>().loadPurchaseHistory();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      appBar: AppBar(
        title: Text(
          'Purchase History',
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
      ),
      body: sub.historyLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.fernGreen,
              ),
            )
          : sub.purchaseHistory.isEmpty
              ? _EmptyHistory()
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: sub.purchaseHistory.length,
                  itemBuilder: (ctx, i) {
                    final delay = i * 0.06;
                    final end = (delay + 0.3).clamp(0.0, 1.0);
                    final anim = Tween<double>(begin: 0, end: 1).animate(
                      CurvedAnimation(
                        parent: _entranceCtrl,
                        curve: Interval(delay, end, curve: Curves.easeOut),
                      ),
                    );
                    return AnimatedBuilder(
                      animation: anim,
                      builder: (_, child) => Opacity(
                        opacity: anim.value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - anim.value) * 20),
                          child: child,
                        ),
                      ),
                      child: _PurchaseCard(
                        record: sub.purchaseHistory[i],
                        onDownloadInvoice: () =>
                            _downloadInvoice(ctx, sub.purchaseHistory[i]),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _downloadInvoice(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    try {
      final orderId = record['order_id'] as String? ?? 'N/A';
      final productId = record['product_id'] as String? ?? '';
      final status = record['status'] as String? ?? '';
      final purchaseTimeMs = record['purchase_time_ms'] as int? ?? 0;
      final expiresTimeMs = record['expires_time_ms'] as int?;
      final amountMicros = record['amount_micros'] as int?;
      final currencyCode = record['currency_code'] as String? ?? 'USD';
      final upgradeBonusDays = record['upgrade_bonus_days'] as int? ?? 0;
      final isYearly = productId.contains('yearly');
      final purchaseDate = DateTime.fromMillisecondsSinceEpoch(purchaseTimeMs);
      final expiryDate = expiresTimeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(expiresTimeMs)
          : null;
      final amount = amountMicros != null
          ? (amountMicros / 1000000).toStringAsFixed(2)
          : 'N/A';
      final fmt = DateFormat('dd MMM yyyy');

      // build pdf
      final pdf = pw.Document();

      // brand colors as pdf colors
      const brandGreen = PdfColor.fromInt(0xFF4CAF6E);
      const brandDark = PdfColor.fromInt(0xFF1A1A1A);
      const brandLight = PdfColor.fromInt(0xFFE8F5EE);
      const textSecondary = PdfColor.fromInt(0xFF5A5A5A);
      const borderColor = PdfColor.fromInt(0xFFE6E6E6);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // header
                pw.Container(
                  padding: const pw.EdgeInsets.all(24),
                  decoration: pw.BoxDecoration(
                    color: brandDark,
                    borderRadius: pw.BorderRadius.circular(12),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'ECHOPROOF',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Subscription Invoice',
                            style: pw.TextStyle(
                              color: brandGreen,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'support@echoproof.online',
                            style: pw.TextStyle(
                              color: PdfColor.fromInt(0x99FFFFFF),
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            'https://echoproof.online',
                            style: pw.TextStyle(
                              color: PdfColor.fromInt(0x99FFFFFF),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 32),

                // invoice details table
                pw.Container(
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderColor),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      _pdfRow('Order ID', orderId, brandDark, textSecondary),
                      _pdfDivider(borderColor),
                      _pdfRow(
                          'Plan',
                          isYearly
                              ? 'Echoproof Pro — Yearly'
                              : 'Echoproof Pro — Monthly',
                          brandDark,
                          textSecondary),
                      _pdfDivider(borderColor),
                      _pdfRow('Status', status.toUpperCase(), brandGreen,
                          textSecondary),
                      _pdfDivider(borderColor),
                      _pdfRow('Amount', '$currencyCode $amount', brandDark,
                          textSecondary),
                      _pdfDivider(borderColor),
                      _pdfRow('Purchase Date', fmt.format(purchaseDate),
                          brandDark, textSecondary),
                      if (expiryDate != null) ...[
                        _pdfDivider(borderColor),
                        _pdfRow('Valid Until', fmt.format(expiryDate),
                            brandDark, textSecondary),
                      ],
                      if (upgradeBonusDays > 0) ...[
                        _pdfDivider(borderColor),
                        _pdfRow('Upgrade Bonus', '+$upgradeBonusDays days free',
                            brandGreen, textSecondary),
                      ],
                    ],
                  ),
                ),

                pw.SizedBox(height: 24),

                // note
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: brandLight,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'This is an automatically generated receipt. Billing is handled by Google Play. '
                    'For billing disputes or refund requests, please contact Google Play support. '
                    'For app-related support, contact us at support@echoproof.online.',
                    style: pw.TextStyle(
                      color: textSecondary,
                      fontSize: 9,
                      lineSpacing: 1.4,
                    ),
                  ),
                ),

                pw.Spacer(),

                // footer
                pw.Divider(color: borderColor),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Generated on ${fmt.format(DateTime.now())}',
                      style: pw.TextStyle(color: textSecondary, fontSize: 9),
                    ),
                    pw.Text(
                      'Echoproof · echoproof.online',
                      style: pw.TextStyle(color: textSecondary, fontSize: 9),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // save to downloads/echoproof invoices
      final bytes = await pdf.save();
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final invoiceDir = Directory('${dir.path}/Echoproof Invoices');
      if (!invoiceDir.existsSync()) await invoiceDir.create(recursive: true);

      final safeOrderId = orderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${invoiceDir.path}/invoice_$safeOrderId.pdf');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);

      if (context.mounted) {
        showSuccessSnack(
            context, 'Invoice saved to Downloads/Echoproof Invoices/');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(
            context, 'Could not generate invoice. Please try again.');
      }
    }
  }

  // pdf helper rows
  pw.Widget _pdfRow(
      String label, String value, PdfColor valueColor, PdfColor labelColor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(color: labelColor, fontSize: 11)),
          pw.Text(value,
              style: pw.TextStyle(
                  color: valueColor,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  pw.Widget _pdfDivider(PdfColor color) {
    return pw.Divider(color: color, height: 1);
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.record,
    required this.onDownloadInvoice,
  });

  final Map<String, dynamic> record;
  final VoidCallback onDownloadInvoice;

  Color get _statusColor {
    return switch (record['status'] as String? ?? '') {
      'acknowledged' || 'active' => AppColors.fernGreen,
      'declined' ||
      'expired' ||
      'canceled' ||
      'refunded' =>
        AppColors.sunsetCoral,
      'pending' => AppColors.statusUnderReview,
      'grace_period' => AppColors.statusControversial,
      _ => AppColors.textTertiary,
    };
  }

  String get _statusLabel {
    return switch (record['status'] as String? ?? '') {
      'acknowledged' => 'Active',
      'active' => 'Active',
      'declined' => 'Declined',
      'expired' => 'Expired',
      'canceled' => 'Cancelled',
      'refunded' => 'Refunded',
      'pending' => 'Pending',
      'grace_period' => 'Grace Period',
      'on_hold' => 'On Hold',
      'paused' => 'Paused',
      _ => 'Unknown',
    };
  }

  // translates billing error codes to human-readable explanations
  String? get _errorExplanation {
    final code = record['error_code'] as int?;
    if (code == null) return null;
    return switch (code) {
      2 =>
        'Google Play service was temporarily unavailable. Your payment was not charged.',
      3 =>
        'Google Play Billing was unavailable. Your Play Store app may need updating.',
      6 => 'An internal Google Play error occurred. No charge was made.',
      7 => 'You already own this subscription.',
      8 => 'Purchase verification failed.',
      12 => 'Network connection failed. Please check your internet.',
      _ => 'Error code $code. No payment was taken. Please try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final productId = record['product_id'] as String? ?? '';
    final isYearly = productId.contains('yearly');
    final purchaseTimeMs = record['purchase_time_ms'] as int? ?? 0;
    final expiresTimeMs = record['expires_time_ms'] as int?;
    final amountMicros = record['amount_micros'] as int?;
    final currencyCode = record['currency_code'] as String? ?? 'USD';
    final upgradeBonusDays = record['upgrade_bonus_days'] as int? ?? 0;

    final purchaseDate = DateTime.fromMillisecondsSinceEpoch(purchaseTimeMs);
    final expiryDate = expiresTimeMs != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresTimeMs)
        : null;
    final amount = amountMicros != null
        ? '$currencyCode ${(amountMicros / 1000000).toStringAsFixed(2)}'
        : null;
    final fmt = DateFormat('dd MMM yyyy');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          // header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isYearly ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: _statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isYearly
                            ? 'Echoproof Pro — Yearly'
                            : 'Echoproof Pro — Monthly',
                        style: GoogleFonts.josefinSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.charcoal,
                        ),
                      ),
                      Text(
                        fmt.format(purchaseDate),
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel,
                    style: GoogleFonts.josefinSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              children: [
                if (amount != null) _DetailRow(label: 'Amount', value: amount),
                if (expiryDate != null)
                  _DetailRow(
                    label: 'Valid until',
                    value: fmt.format(expiryDate),
                  ),
                if (upgradeBonusDays > 0)
                  _DetailRow(
                    label: 'Upgrade bonus',
                    value: '+$upgradeBonusDays days free',
                    valueColor: AppColors.fernGreen,
                  ),
                _DetailRow(
                  label: 'Order ID',
                  value: (record['order_id'] as String? ?? 'N/A').substring(
                      0,
                      ((record['order_id'] as String? ?? '').length)
                          .clamp(0, 24)),
                ),
                // error explanation for declined purchases
                if (_errorExplanation != null)
                  Container(
                    margin: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                    ),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.sunsetCoralLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppColors.sunsetCoral,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorExplanation!,
                            style: GoogleFonts.josefinSans(
                              fontSize: 12,
                              color: AppColors.sunsetCoralDark,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // invoice download button (only for successful purchases)
          if (record['status'] == 'acknowledged' ||
              record['status'] == 'active')
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onDownloadInvoice,
                  icon: const Icon(
                    Icons.download_outlined,
                    size: 16,
                  ),
                  label: Text(
                    'Download invoice',
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.charcoal,
                    side: const BorderSide(color: AppColors.borderMedium),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.josefinSans(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.josefinSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No purchases yet',
              style: GoogleFonts.josefinSans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your purchase history will appear here once you subscribe to Echoproof Pro.',
              style: GoogleFonts.josefinSans(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
