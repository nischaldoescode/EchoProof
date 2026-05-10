// Link preview card — shows OG title, description, and favicon for URLs.
// Fetches metadata via a Supabase edge function to keep API calls server-side.
// Users can dismiss the preview with the X button.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/utils/logger.dart';

class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.onDismiss,
    required this.onAttach,
  });

  final String url;
  final VoidCallback onDismiss;
  final VoidCallback onAttach;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  Map<String, dynamic>? _meta;
  bool _isLoading = true;
  bool _attached = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) return;

      final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
      final res = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/fetch-link-preview'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': widget.url}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _meta = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load preview';
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.warn('link preview: fetch failed $e');
      setState(() {
        _error = 'Preview unavailable';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _PreviewSkeleton(onDismiss: widget.onDismiss);
    }

    if (_error != null || _meta == null) {
      return const SizedBox.shrink();
    }

    final title = _meta!['title'] as String? ?? '';
    final description = _meta!['description'] as String? ?? '';
    final imageUrl = _meta!['image'] as String?;
    final siteName = _meta!['site_name'] as String? ?? '';
    final faviconUrl = _meta!['favicon'] as String?;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _attached ? AppColors.fernGreen : AppColors.borderSubtle,
          width: _attached ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OG image if present.
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: Image.network(
                imageUrl,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Site name with favicon.
                Row(
                  children: [
                    if (faviconUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Image.network(
                          faviconUrl,
                          width: 14,
                          height: 14,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    Text(
                      siteName.toUpperCase(),
                      style: GoogleFonts.josefinSans(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.charcoal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.josefinSans(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                // Action row: attach / dismiss / open.
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() => _attached = !_attached);
                        if (_attached) widget.onAttach();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _attached
                              ? AppColors.fernGreenLight
                              : AppColors.softSand,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _attached ? 'Preview attached ✓' : 'Attach preview',
                          style: GoogleFonts.josefinSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _attached
                                ? AppColors.fernGreenDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Open link options.
                    GestureDetector(
                      onTap: () => _showOpenOptions(context),
                      child: const Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Dismiss preview entirely.
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showOpenOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_browser_rounded),
              title: Text(
                'Open in browser',
                style: GoogleFonts.josefinSans(),
              ),
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri.tryParse(widget.url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.web_rounded),
              title: Text(
                'Open in app',
                style: GoogleFonts.josefinSans(),
              ),
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri.tryParse(widget.url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.inAppWebView);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.softSand,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.fernGreen),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Loading preview...',
              style: GoogleFonts.josefinSans(
                fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded,
              size: 16, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}