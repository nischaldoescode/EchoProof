// settings screen
// account, notifications, subscription, privacy, about

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../auth/presentation/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.josefinSans(
            fontSize: 18, fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
      ),
      body: ListView(
        children: [
          _Section(title: 'Account', tiles: [
            _Tile(
              icon:    Icons.person_outline_rounded,
              label:   'Edit profile',
              onTap:   () => context.push('/profile'),
            ),
            _Tile(
              icon:    Icons.lock_outline_rounded,
              label:   'Change password',
              onTap:   () => _showChangePassword(context),
            ),
            _Tile(
              icon:    Icons.verified_user_outlined,
              label:   'Verify identity',
              onTap:   () => context.push('/verify-identity'),
            ),
          ]),

          _Section(title: 'Subscription', tiles: [
            _Tile(
              icon:     Icons.star_outline_rounded,
              label:    'Echoproof Pro',
              trailing: const _ProBadge(),
              onTap:    () => context.push('/subscribe'),
            ),
          ]),

          _Section(title: 'Notifications', tiles: [
            _SwitchTile(
              icon:  Icons.notifications_outlined,
              label: 'Echo verified',
              value: true,
              onChanged: (_) {},
            ),
            _SwitchTile(
              icon:  Icons.people_outline,
              label: 'New echo from someone I follow',
              value: true,
              onChanged: (_) {},
            ),
            _SwitchTile(
              icon:  Icons.arrow_upward_rounded,
              label: 'Someone supported my echo',
              value: false,
              onChanged: (_) {},
            ),
          ]),

          _Section(title: 'Privacy', tiles: [
            _Tile(
              icon:  Icons.lock_outlined,
              label: 'End-to-end encryption',
              subtitle: 'All your echoes are encrypted in transit and at rest',
              onTap: () {},
            ),
            _Tile(
              icon:    Icons.delete_outline_rounded,
              label:   'Delete account',
              color:   AppColors.sunsetCoral,
              onTap:   () => _showDeleteAccount(context),
            ),
          ]),

          _Section(title: 'About', tiles: [
            _Tile(
              icon:  Icons.info_outline_rounded,
              label: 'About Echoproof',
              onTap: () {},
            ),
            _Tile(
              icon:  Icons.description_outlined,
              label: 'Terms of service',
              onTap: () {},
            ),
            _Tile(
              icon:  Icons.privacy_tip_outlined,
              label: 'Privacy policy',
              onTap: () {},
            ),
            _Tile(
              icon:  Icons.code_rounded,
              label: 'Version 1.0.0',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: AppSpacing.lg),

          // sign out
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical:   AppSpacing.sm,
            ),
            child: OutlinedButton.icon(
              onPressed: () {
                context.read<AuthService>().signOut();
                context.go('/login');
              },
              icon:  const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'Sign out',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sunsetCoral,
                side: BorderSide(color: AppColors.sunsetCoral.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  void _showDeleteAccount(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Delete account?',
          style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This permanently deletes your account, echoes, and trust history. This cannot be undone.',
          style: GoogleFonts.josefinSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.josefinSans(),
            ),
          ),
          TextButton(
            onPressed: () {},
            child: Text(
              'Delete',
              style: GoogleFonts.josefinSans(color: AppColors.sunsetCoral),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles});
  final String       title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xs,
          ),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.josefinSans(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.color,
  });
  final IconData icon;
  final String   label;
  final String?  subtitle;
  final Widget?  trailing;
  final Color?   color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical:   AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.charcoal),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.josefinSans(
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                      color:      color ?? AppColors.charcoal,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        color:    AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            trailing ?? const Icon(
              Icons.chevron_right_rounded,
              size:  16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatefulWidget {
  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String   label;
  final bool     value;
  final void Function(bool) onChanged;

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical:   AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(widget.icon, size: 20, color: AppColors.charcoal),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              widget.label,
              style: GoogleFonts.josefinSans(
                fontSize:   14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            value:     _value,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
            activeColor: AppColors.fernGreen,
          ),
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D2D2D), Color(0xFF4CAF6E)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'PRO',
        style: GoogleFonts.josefinSans(
          fontSize:   10,
          fontWeight: FontWeight.w700,
          color:      Colors.white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _controller = TextEditingController();
  bool  _loading    = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left:   AppSpacing.xl,
        right:  AppSpacing.xl,
        top:    AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New password',
            style: GoogleFonts.josefinSans(
              fontSize:   18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller:  _controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Enter new password (min 8 chars)',
              hintStyle: GoogleFonts.josefinSans(color: AppColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : () async {
                if (_controller.text.length < 8) return;
                setState(() => _loading = true);
                // supabase update password
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(password: _controller.text),
                );
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.charcoal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Update password',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}