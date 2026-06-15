// bookmark button
// @params echoid identifies the echo to save
// @params compact keeps feed actions light

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/snack.dart';
import '../services/bookmark_service.dart';

class EchoBookmarkButton extends StatefulWidget {
  const EchoBookmarkButton({
    super.key,
    required this.echoId,
    this.compact = false,
    this.showLabel = false,
  });

  final String echoId;
  final bool compact;
  final bool showLabel;

  @override
  State<EchoBookmarkButton> createState() => _EchoBookmarkButtonState();
}

class _EchoBookmarkButtonState extends State<EchoBookmarkButton> {
  bool _requestedLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedLoad) return;
    _requestedLoad = true;
    final service = _maybeBookmarkService(context);
    if (service != null) unawaited(service.ensureLoaded());
  }

  Future<void> _toggle() async {
    final service = _maybeBookmarkService(context);
    if (service == null) {
      showInfoSnack(context, 'Bookmarks are still loading.');
      return;
    }
    final wasSaved = service.isBookmarked(widget.echoId);
    unawaited(AppHaptics.selection());
    final ok = await service.toggle(widget.echoId);
    if (!mounted) return;
    if (!ok) {
      showErrorSnack(context, 'Could not update bookmark.');
      return;
    }
    showInfoSnack(context, wasSaved ? 'Removed from bookmarks.' : 'Saved.');
  }

  @override
  Widget build(BuildContext context) {
    final service = _maybeBookmarkService(context, listen: true);
    final saved = service?.isBookmarked(widget.echoId) ?? false;
    final color = saved ? AppColors.fernGreenDark : AppColors.textTertiary;
    final icon = saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded;
    final size = widget.compact ? 20.0 : 24.0;

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: child,
      ),
      child: Icon(icon, key: ValueKey(saved), size: size, color: color),
    );

    if (!widget.showLabel) {
      return IconButton(
        tooltip: saved ? 'Remove bookmark' : 'Bookmark',
        visualDensity: VisualDensity.compact,
        constraints: widget.compact
            ? const BoxConstraints.tightFor(width: 34, height: 34)
            : null,
        padding: widget.compact ? EdgeInsets.zero : null,
        onPressed: _toggle,
        icon: child,
      );
    }

    return TextButton.icon(
      onPressed: _toggle,
      icon: child,
      label: Text(saved ? 'Bookmarked' : 'Bookmark'),
      style: TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

BookmarkService? _maybeBookmarkService(
  BuildContext context, {
  bool listen = false,
}) {
  try {
    return Provider.of<BookmarkService>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}
