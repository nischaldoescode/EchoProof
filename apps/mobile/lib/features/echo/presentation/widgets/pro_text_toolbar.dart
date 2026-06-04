// minimal rich text toolbar for pro users
// inserts markdown-style markers into text:
// bold**, _italic_, ~~strike~~, [large], and [small]
// the feed card renders these using a simple inline parser

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';

class ProTextToolbar extends StatelessWidget {
  const ProTextToolbar({super.key, required this.controller});
  final TextEditingController controller;

  void _wrap(String open, String close) {
    final sel = controller.selection;
    if (!sel.isValid) return;
    final text = controller.text;
    final selected = sel.textInside(text);
    final fallback = switch (open) {
      '**' => 'bold text',
      '_' => 'italic text',
      '~~' => 'strikethrough text',
      '[large]' => 'large text',
      '[small]' => 'small text',
      _ => 'text',
    };

    if (selected.isEmpty) {
      final replacement = '$open$fallback$close';
      final newText = text.replaceRange(sel.start, sel.end, replacement);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + open.length,
          extentOffset: sel.start + open.length + fallback.length,
        ),
      );
      return;
    }

    final leading = RegExp(r'^\s+').firstMatch(selected)?.group(0) ?? '';
    final trailing = RegExp(r'\s+$').firstMatch(selected)?.group(0) ?? '';
    final coreStart = sel.start + leading.length;
    final coreEnd = sel.end - trailing.length;
    final core = coreEnd > coreStart ? text.substring(coreStart, coreEnd) : '';

    if (core.isEmpty) {
      final replacement = '$leading$open$fallback$close$trailing';
      final newText = text.replaceRange(sel.start, sel.end, replacement);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + leading.length + open.length,
          extentOffset:
              sel.start + leading.length + open.length + fallback.length,
        ),
      );
      return;
    }

    if (core.startsWith(open) &&
        core.endsWith(close) &&
        core.length >= open.length + close.length) {
      final unwrapped = core.substring(
        open.length,
        core.length - close.length,
      );
      final replacement = '$leading$unwrapped$trailing';
      final newText = text.replaceRange(sel.start, sel.end, replacement);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start + leading.length,
          extentOffset: sel.start + leading.length + unwrapped.length,
        ),
      );
      return;
    }

    final hasOuterOpen = coreStart >= open.length &&
        text.substring(coreStart - open.length, coreStart) == open;
    final hasOuterClose = coreEnd + close.length <= text.length &&
        text.substring(coreEnd, coreEnd + close.length) == close;
    if (hasOuterOpen && hasOuterClose) {
      final newText = text.replaceRange(coreEnd, coreEnd + close.length, '');
      final unwrappedText =
          newText.replaceRange(coreStart - open.length, coreStart, '');
      controller.value = TextEditingValue(
        text: unwrappedText,
        selection: TextSelection(
          baseOffset: coreStart - open.length,
          extentOffset: coreEnd - open.length,
        ),
      );
      return;
    }

    final replacement = '$leading$open$core$close$trailing';
    final newText = text.replaceRange(sel.start, sel.end, replacement);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: sel.start + replacement.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAF7),
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          _ToolbarButton(
            label: 'B',
            bold: true,
            onTap: () => _wrap('**', '**'),
          ),
          _ToolbarButton(
            label: 'I',
            italic: true,
            onTap: () => _wrap('_', '_'),
          ),
          _ToolbarButton(
            label: 'S',
            strikethrough: true,
            onTap: () => _wrap('~~', '~~'),
          ),
          _ToolbarButton(
            label: 'A+',
            bold: true,
            onTap: () => _wrap('[large]', '[/large]'),
          ),
          _ToolbarButton(
            label: 'A-',
            onTap: () => _wrap('[small]', '[/small]'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.onTap,
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool bold, italic, strikethrough;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 28,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: strikethrough ? TextDecoration.lineThrough : null,
              color: AppColors.charcoal,
            ),
          ),
        ),
      ),
    );
  }
}
