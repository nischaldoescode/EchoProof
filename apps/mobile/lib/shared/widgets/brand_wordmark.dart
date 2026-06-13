// brand wordmark
// @params size controls the rendered text size

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';

class EchoProofWordmark extends StatelessWidget {
  const EchoProofWordmark({
    super.key,
    this.fontSize = 22,
    this.proofColor = const Color(0xFF2E6FAE),
    this.weight = FontWeight.w800,
  });

  final double fontSize;
  final Color proofColor;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.josefinSans(
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: 0,
      height: 1,
    );

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style.copyWith(color: AppColors.charcoal),
        children: [
          const TextSpan(text: 'Echo'),
          TextSpan(
            text: 'Proof',
            style: style.copyWith(color: proofColor),
          ),
        ],
      ),
    );
  }
}
