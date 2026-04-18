// truth bond button — shown on verified echoes only
// lets users stake their reputation on a verified claim
// calls solana service to mint a compressed nft
// updates truth_bonds table in supabase

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/utils/logger.dart';

class TruthBondButton extends ConsumerStatefulWidget {
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
  ConsumerState<TruthBondButton> createState() => _TruthBondButtonState();
}

class _TruthBondButtonState extends ConsumerState<TruthBondButton>
    with SingleTickerProviderStateMixin {

  bool _hasBonded    = false;
  bool _isLoading    = false;
  late final AnimationController _pulseController;
  late final Animation<double>   _pulse;

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
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;

      final result = await client
          .from('truth_bonds')
          .select('id')
          .eq('echo_id', widget.echoId)
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) setState(() => _hasBonded = result != null);
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
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('not authenticated');

      // insert the bond record
      // mint_tx is null for now — solana minting happens asynchronously
      // the on-truth-bond edge function handles the actual nft mint
      await client.from('truth_bonds').insert({
        'echo_id': widget.echoId,
        'user_id': userId,
      });

      // increment bond count on echo
      await client.rpc('increment_bond_count', params: {'p_echo_id': widget.echoId});

      await _pulseController.forward();
      await _pulseController.reverse();

      if (mounted) setState(() { _hasBonded = true; _isLoading = false; });

      AppLogger.info('truth bond created for echo ${widget.echoId}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bond created — you are staking your reputation on this truth'),
            backgroundColor: AppColors.fernGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('truth bond failed', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('duplicate') ? 'already bonded' : 'bond failed, try again'),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status != EchoStatus.verified) return const SizedBox.shrink();

    return ScaleTransition(
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
            color: _hasBonded ? AppColors.fernGreenLight : AppColors.softSand,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(
              color: _hasBonded
                  ? AppColors.fernGreen.withOpacity(0.5)
                  : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isLoading
                  ? const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.fernGreen),
                    )
                  : Icon(
                      _hasBonded
                          ? Icons.verified_outlined
                          : Icons.link_outlined,
                      size: 13,
                      color: _hasBonded ? AppColors.fernGreen : AppColors.textTertiary,
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
                  color: _hasBonded ? AppColors.fernGreenDark : AppColors.textSecondary,
                  fontFamily: AppTypography.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}