import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import 'avatar_image_provider.dart';

class SafeCircleAvatar extends StatelessWidget {
  const SafeCircleAvatar({
    super.key,
    required this.radius,
    this.avatarUrl,
    this.backgroundColor = AppColors.softSand,
    this.iconColor = AppColors.textTertiary,
    this.icon,
    this.semanticLabel,
  });

  final double radius;
  final String? avatarUrl;
  final Color backgroundColor;
  final Color iconColor;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final uri = url == null || url.isEmpty ? null : Uri.tryParse(url);
    final canLoad =
        uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    final size = radius * 2;
    final useLocalLogo = isEchoProofOfficialLogoUrl(url);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: useLocalLogo
          ? Image.asset(
              echoProofLogoAsset,
              fit: BoxFit.cover,
              semanticLabel: semanticLabel,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : canLoad
              ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  semanticLabel: semanticLabel,
                  errorBuilder: (_, __, ___) => _fallback(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _fallback(opacity: 0.55);
                  },
                )
              : _fallback(),
    );
  }

  Widget _fallback({double opacity = 1}) {
    return Opacity(
      opacity: opacity,
      child: Icon(
        icon ?? Icons.person_outline,
        size: radius * 0.72,
        color: iconColor,
      ),
    );
  }
}
