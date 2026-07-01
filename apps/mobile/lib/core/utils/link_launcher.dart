// link launcher
// @params none

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import 'logger.dart';
import 'snack.dart';

Future<bool> launchAppUrl(
  BuildContext context,
  String url, {
  LaunchMode mode = LaunchMode.inAppBrowserView,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    if (context.mounted) showErrorSnack(context, 'That link is not valid.');
    return false;
  }

  try {
    final launched = await launchUrl(uri, mode: mode);
    if (!launched && context.mounted) {
      showErrorSnack(context, 'Could not open the link.');
    }
    return launched;
  } catch (e) {
    AppLogger.warn('link launcher: could not open $url: $e');
    if (context.mounted) showErrorSnack(context, 'Could not open the link.');
    return false;
  }
}

Future<bool> launchExternalUrlWithFallback(
  BuildContext context,
  String url, {
  String errorMessage = 'Could not open the link.',
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    if (context.mounted) showErrorSnack(context, 'That link is not valid.');
    return false;
  }

  try {
    // android devices can have missing, disabled, or policy-blocked external
    // browser handlers. try the user's browser first, then fall back to the
    // in-app browser so a valid public record tap still has somewhere to go.
    final external = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (external) return true;

    final inApp = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (inApp) return true;

    if (context.mounted) showErrorSnack(context, errorMessage);
    return false;
  } catch (e) {
    AppLogger.warn('link launcher: external fallback failed $url: $e');
    try {
      final inApp = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (inApp) return true;
    } catch (fallbackError) {
      AppLogger.warn(
        'link launcher: in-app fallback failed $url: $fallbackError',
      );
    }
    if (context.mounted) showErrorSnack(context, errorMessage);
    return false;
  }
}

void showOpenLinkSheet(
  BuildContext context, {
  required String url,
  String? title,
}) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.isNotEmpty == true ? uri!.host : url;
  final displayTitle = title?.trim().isNotEmpty == true ? title!.trim() : host;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight * 0.88
                : MediaQuery.sizeOf(context).height * 0.82;

            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Material(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.borderMedium,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.josefinSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _OpenLinkAction(
                          icon: Icons.open_in_browser_rounded,
                          title: 'Open in app',
                          subtitle: 'Stay inside Echoproof',
                          onTap: () {
                            Navigator.pop(ctx);
                            launchAppUrl(
                              context,
                              url,
                              mode: LaunchMode.inAppBrowserView,
                            );
                          },
                        ),
                        _OpenLinkAction(
                          icon: Icons.north_east_rounded,
                          title: 'Open in browser',
                          subtitle: 'Use your default browser',
                          onTap: () {
                            Navigator.pop(ctx);
                            launchAppUrl(
                              context,
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _OpenLinkAction extends StatelessWidget {
  const _OpenLinkAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Icon(icon, size: 19, color: AppColors.charcoal),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.josefinSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.charcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
