// verified identity badge
// shown next to usernames when is_identity_verified = true
// subtle not flashy matches the trust-first design ethos

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 14.0});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.verified_outlined,
      size: size,
      color: AppColors.fernGreen,
    );
  }
}
