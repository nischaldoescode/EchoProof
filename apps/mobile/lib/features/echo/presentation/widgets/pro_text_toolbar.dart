// Minimal rich text toolbar for Pro users.
// Inserts markdown-style markers into text: **bold**, _italic_, ~~strike~~.
// The feed card renders these using a simple inline parser.

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
    final replacement = '$open$selected$close';
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