// truth bond button — shown on verified echoes only
// plain StatefulWidget — no riverpod

import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_status.dart';
import '../../../../core/utils/logger.dart';
import 'solana_status_chip.dart';

class TruthBondButton extends StatefulWidget {
  const TruthBondButton({
    super.key,
    required this.echoId,
    required this.status,
    required this.bondCount,
  });

  final String echoId;
  final EchoStatus status;
  final int bondCount;

  @override
  State<TruthBondButton> createState() => _TruthBondButtonState();
}

class _TruthBondButtonState extends State<TruthBondButton>
    with SingleTickerProviderStateMixin {
  bool _hasBonded = false;
  bool _isLoading = false;
  String? _bondTx;
  String _solanaStatus = 'pending';

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _checkExistingBond();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingBond() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final result = await client
          .from('truth_bonds')
          .select('id, mint_tx, solana_status')
          .eq('echo_id', widget.echoId)
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _hasBonded = result != null;
          _bondTx = result?['mint_tx'] as String?;
          _solanaStatus = result?['solana_status'] as String? ?? 'pending';
        });
      }
    } catch (e) {
      AppLogger.error('truth bond check failed', e);
    }
  }

  Future<void> _bond() async {
    if (_hasBonded || _isLoading) return;
    if (widget.status != EchoStatus.verified) return;

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      final inserted = await client
          .from('truth_bonds')
          .insert({
            'echo_id': widget.echoId,
            'user_id': userId,
          })
          .select('id, mint_tx, solana_status')
          .single();

      final bondId = inserted['id'] as String;
      var bondTx = inserted['mint_tx'] as String?;
      var solanaStatus = inserted['solana_status'] as String? ?? 'pending';

      await client.rpc(
        'increment_bond_count',
        params: {'p_echo_id': widget.echoId},
      );

      try {
        final response = await client.functions.invoke(
          'solana-memo',
          body: {
            'kind': 'truth_bond',
            'bond_id': bondId,
          },
        );
        final data = response.data;
        if (data is Map) {
          bondTx = data['signature'] as String? ?? bondTx;
          solanaStatus = bondTx == null ? 'recording' : 'anchored';
        }
      } catch (e) {
        solanaStatus = 'failed';
        AppLogger.warn('truth bond solana anchor failed $e');
      }

      await _pulseController.forward();
      await _pulseController.reverse();

      if (mounted) {
        setState(() {
          _hasBonded = true;
          _isLoading = false;
          _bondTx = bondTx;
          _solanaStatus = solanaStatus;
        });
      }

      AppLogger.info('truth bond created for echo ${widget.echoId}');

      if (mounted) {
        showSuccessSnack(
          context,
          solanaStatus == 'anchored'
              ? 'Bond created and anchored on Solana'
              : 'Bond created; Solana anchor is pending',
        );
      }
    } catch (e) {
      AppLogger.error('truth bond failed', e);
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorSnack(
            context,
            e.toString().contains('duplicate')
                ? 'already bonded'
                : 'bond failed, try again');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status != EchoStatus.verified) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScaleTransition(
          scale: _pulse,
          child: GestureDetector(
            onTap: _bond,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color:
                    _hasBonded ? AppColors.fernGreenLight : AppColors.softSand,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(
                  color: _hasBonded
                      ? AppColors.fernGreen.withValues(alpha: 0.5)
                      : AppColors.borderSubtle,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isLoading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.fernGreen,
                          ),
                        )
                      : Icon(
                          _hasBonded
                              ? Icons.verified_outlined
                              : Icons.link_outlined,
                          size: 13,
                          color: _hasBonded
                              ? AppColors.fernGreen
                              : AppColors.textTertiary,
                        ),
                  const SizedBox(width: 4),
                  Text(
                    _hasBonded
                        ? 'Bonded'
                        : widget.bondCount > 0
                            ? '${widget.bondCount} bonds'
                            : 'Bond this truth',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _hasBonded
                          ? AppColors.fernGreenDark
                          : AppColors.textSecondary,
                      fontFamily: AppTypography.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_hasBonded || _isLoading) ...[
          const SizedBox(height: AppSpacing.sm),
          SolanaStatusChip(
            status: _isLoading ? 'recording' : _solanaStatus,
            signature: _bondTx,
            label: 'Solana bond',
          ),
        ],
      ],
    );
  }
}
