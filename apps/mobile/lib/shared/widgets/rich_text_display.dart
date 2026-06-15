// renders markdown-style inline formatting from echo content
// supports **bold**, ***bold italic***, _italic_, ~~strikethrough~~,
// [large], [small], @mentions, and ~signals

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
    this.hideUrls = false,
    this.onHashtagTap,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool hideUrls;
  final ValueChanged<String>? onHashtagTap;

  @override
  Widget build(BuildContext context) {
    final base =
        style ??
        GoogleFonts.josefinSans(fontSize: 14, color: AppColors.charcoal);

    return Text.rich(
      _parse(text, base),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  TextSpan _parse(String input, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'\[large\]([\s\S]+?)\[/large\]|\[small\]([\s\S]+?)\[/small\]|\*\*\*([\s\S]+?)\*\*\*|\*\*([\s\S]+?)\*\*|_([\s\S]+?)_|~~([\s\S]+?)~~|(https?:\/\/[^\s<>"{}|\\^`\[\]]+)|(@[A-Za-z0-9_]+)|([#~][A-Za-z0-9][A-Za-z0-9_-]{1,31})',
      dotAll: true,
    );

    int last = 0;
    for (final match in pattern.allMatches(input)) {
      if (match.start > last) {
        spans.add(
          TextSpan(text: input.substring(last, match.start), style: base),
        );
      }
      if (match.group(1) != null) {
        spans.addAll(_parse(match.group(1)!, _largeStyle(base)).children ?? []);
      } else if (match.group(2) != null) {
        spans.addAll(_parse(match.group(2)!, _smallStyle(base)).children ?? []);
      } else if (match.group(3) != null) {
        spans.addAll(
          _parse(
                match.group(3)!,
                base.copyWith(
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ).children ??
              [],
        );
      } else if (match.group(4) != null) {
        spans.addAll(
          _parse(
                match.group(4)!,
                base.copyWith(fontWeight: FontWeight.w700),
              ).children ??
              [],
        );
      } else if (match.group(5) != null) {
        spans.addAll(
          _parse(
                match.group(5)!,
                base.copyWith(fontStyle: FontStyle.italic),
              ).children ??
              [],
        );
      } else if (match.group(6) != null) {
        spans.addAll(
          _parse(
                match.group(6)!,
                base.copyWith(decoration: TextDecoration.lineThrough),
              ).children ??
              [],
        );
      } else if (match.group(7) != null) {
        if (!hideUrls) {
          spans.add(
            TextSpan(
              text: match.group(7),
              style: base.copyWith(
                color: AppColors.fernGreenDark,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.fernGreenDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      } else if (match.group(8) != null) {
        spans.add(
          TextSpan(
            text: match.group(8),
            style: base.copyWith(
              color: AppColors.fernGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else if (match.group(9) != null) {
        final tag = match.group(9)!;
        final searchTag = tag.startsWith('~') ? '#${tag.substring(1)}' : tag;
        final tagStyle = base.copyWith(
          color: AppColors.fernGreenDark,
          fontWeight: FontWeight.w700,
        );
        if (onHashtagTap == null) {
          spans.add(TextSpan(text: tag, style: tagStyle));
        } else {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onHashtagTap!(searchTag),
                child: Text(tag, style: tagStyle),
              ),
            ),
          );
        }
      }
      last = match.end;
    }
    if (last < input.length) {
      spans.add(TextSpan(text: input.substring(last), style: base));
    }
    return TextSpan(children: spans);
  }

  TextStyle _largeStyle(TextStyle base) {
    final size = base.fontSize ?? 14;
    final baseHeight = base.height ?? 1.24;
    return base.copyWith(
      fontSize: size + 2.5,
      height: baseHeight.clamp(1.16, 1.30).toDouble(),
      fontWeight: base.fontWeight ?? FontWeight.w600,
    );
  }

  TextStyle _smallStyle(TextStyle base) {
    final size = base.fontSize ?? 14;
    final next = size - 2 < 11 ? 11.0 : size - 2;
    return base.copyWith(fontSize: next, height: base.height ?? 1.35);
  }
}
