// Renders markdown-style inline formatting from echo content.
// Supports **bold**, _italic_, ~~strikethrough~~, @mentions, ~signals.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';

class RichTextDisplay extends StatelessWidget {
  const RichTextDisplay({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final base = style ??
        GoogleFonts.josefinSans(fontSize: 14, color: AppColors.charcoal);

    return Text.rich(
      _parse(text, base),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  TextSpan _parse(String input, TextStyle base) {
    final spans = <InlineSpan>[];
    // Pattern: **bold**, _italic_, ~~strike~~, @mention, ~signal
    final pattern = RegExp(
      r'\*\*(.+?)\*\*|_(.+?)_|~~(.+?)~~|(@\w+)|(~\w+)',
      dotAll: true,
    );

    int last = 0;
    for (final match in pattern.allMatches(input)) {
      if (match.start > last) {
        spans.add(TextSpan(text: input.substring(last, match.start), style: base));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: match.group(1),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
          text: match.group(3),
          style: base.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(
          text: match.group(4),
          style: base.copyWith(color: AppColors.fernGreen, fontWeight: FontWeight.w600),
        ));
      } else if (match.group(5) != null) {
        spans.add(TextSpan(
          text: match.group(5),
          style: base.copyWith(color: AppColors.fernGreen),
        ));
      }
      last = match.end;
    }
    if (last < input.length) {
      spans.add(TextSpan(text: input.substring(last), style: base));
    }
    return TextSpan(children: spans);
  }
}