// link preview card shows og title, description, and favicon for urls
// fetches metadata via a supabase edge function to keep api calls server-side
// users can dismiss the preview with the x button

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/utils/link_launcher.dart';
import '../../../../core/utils/logger.dart';

String? extractFirstUrl(String text) {
  final urlPattern = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );
  final match = urlPattern.firstMatch(text);
  return match?.group(0);
}

String _hostFor(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  return uri.host.replaceFirst(RegExp(r'^www\.'), '');
}

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
      final anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
      final res = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/fetch-link-preview'),
        headers: {
          if (anonKey.isNotEmpty) 'apikey': anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': widget.url}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['error'] != null) {
          setState(() {
            _error = 'Preview unavailable';
            _isLoading = false;
          });
          return;
        }
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
          color: AppColors.fernGreen.withValues(alpha: 0.24),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // og image if present
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
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
                // site name with favicon
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
                // action row: attach / dismiss / open
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.fernGreenLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Preview attached',
                        style: GoogleFonts.josefinSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.fernGreenDark,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // open link options
                    GestureDetector(
                      onTap: () => _showOpenOptions(context),
                      child: const Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // dismiss preview entirely
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
    showOpenLinkSheet(
      context,
      url: widget.url,
      title: _meta?['title'] as String?,
    );
  }
}

enum EchoLinkPreviewVariant { compact, detail }

class EchoLinkPreview extends StatefulWidget {
  const EchoLinkPreview({
    super.key,
    required this.url,
    this.variant = EchoLinkPreviewVariant.compact,
    this.onUnavailable,
  });

  final String url;
  final EchoLinkPreviewVariant variant;
  final VoidCallback? onUnavailable;

  @override
  State<EchoLinkPreview> createState() => _EchoLinkPreviewState();
}

class _EchoLinkPreviewState extends State<EchoLinkPreview> {
  Map<String, dynamic>? _meta;
  bool _isLoading = true;

  bool get _isDetail => widget.variant == EchoLinkPreviewVariant.detail;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant EchoLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      setState(() {
        _meta = null;
        _isLoading = true;
      });
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) {
        setState(() => _isLoading = false);
        widget.onUnavailable?.call();
        return;
      }

      final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
      final anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
      final res = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/fetch-link-preview'),
        headers: {
          if (anonKey.isNotEmpty) 'apikey': anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': widget.url}),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _meta = data['error'] == null ? data : null;
          _isLoading = false;
        });
        if (data['error'] != null) widget.onUnavailable?.call();
      } else {
        setState(() => _isLoading = false);
        widget.onUnavailable?.call();
      }
    } catch (e) {
      AppLogger.warn('echo link preview: fetch failed $e');
      if (mounted) setState(() => _isLoading = false);
      widget.onUnavailable?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _InlinePreviewSkeleton(isDetail: _isDetail);
    }

    final title = (_meta?['title'] as String?)?.trim() ?? '';
    final description = (_meta?['description'] as String?)?.trim() ?? '';
    final imageUrl = (_meta?['image'] as String?)?.trim();
    final siteName =
        ((_meta?['site_name'] as String?)?.trim().isNotEmpty == true
                ? (_meta!['site_name'] as String).trim()
                : _hostFor(widget.url))
            .trim();
    final displayTitle = title.isNotEmpty ? title : widget.url;

    if (_meta == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showOpenLinkSheet(
        context,
        url: widget.url,
        title: displayTitle,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.only(top: _isDetail ? AppSpacing.lg : AppSpacing.md),
        decoration: BoxDecoration(
          color: _isDetail ? AppColors.surfaceSecondary : Colors.white,
          borderRadius: BorderRadius.circular(_isDetail ? 16 : 12),
          border: Border.all(
            color: _isDetail
                ? AppColors.fernGreen.withValues(alpha: 0.24)
                : AppColors.borderSubtle,
            width: _isDetail ? 1.2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _isDetail
            ? _DetailPreviewLayout(
                url: widget.url,
                title: displayTitle,
                description: description,
                siteName: siteName,
                imageUrl: imageUrl,
              )
            : _CompactPreviewLayout(
                title: displayTitle,
                description: description,
                siteName: siteName,
                imageUrl: imageUrl,
              ),
      ),
    );
  }
}

class _CompactPreviewLayout extends StatelessWidget {
  const _CompactPreviewLayout({
    required this.title,
    required this.description,
    required this.siteName,
    required this.imageUrl,
  });

  final String title;
  final String description;
  final String siteName;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 86,
          height: 86,
          color: AppColors.softSand,
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.link_rounded,
                    color: AppColors.textTertiary,
                  ),
                )
              : const Icon(Icons.link_rounded, color: AppColors.textTertiary),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  siteName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.josefinSans(
                    fontSize: 10,
                    color: AppColors.fernGreenDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                    height: 1.25,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.josefinSans(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: AppSpacing.md),
          child: Icon(
            Icons.open_in_new_rounded,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _DetailPreviewLayout extends StatelessWidget {
  const _DetailPreviewLayout({
    required this.url,
    required this.title,
    required this.description,
    required this.siteName,
    required this.imageUrl,
  });

  final String url;
  final String title;
  final String description;
  final String siteName;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty)
          SizedBox(
            height: 178,
            width: double.infinity,
            child: Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    size: 15,
                    color: AppColors.fernGreenDark,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      siteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color: AppColors.fernGreenDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.josefinSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                  height: 1.22,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.josefinSans(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 17,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlinePreviewSkeleton extends StatelessWidget {
  const _InlinePreviewSkeleton({required this.isDetail});

  final bool isDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isDetail ? 124 : 86,
      margin: EdgeInsets.only(top: isDetail ? AppSpacing.lg : AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(isDetail ? 16 : 12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.fernGreen,
          ),
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
            width: 16,
            height: 16,
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
