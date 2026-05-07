import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../auth/firebase_auth_service.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/utils/snackbar_utils.dart';

class AccountSection extends StatefulWidget {
  const AccountSection({super.key});

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  final _picker = ImagePicker();
  final _username = TextEditingController();
  final _auth = FirebaseAuthService();

  String? _profileImageUrl;
  String? _googleProfilePictureUrl;
  String? _userEmail;
  String? _name;
  DateTime? _joined;

  bool _uploading = false;
  bool _savingUsername = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _fetchProfile();
    await _fetchEmail();
    await _loadGoogleAvatar();
    await _loadAvatar();
  }

  Future<void> _fetchProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final r = await Supabase.instance.client
          .from('profiles')
          .select('created_at, username')
          .eq('id', user.id)
          .single();
      if (!mounted) return;
      setState(() {
        if (r['created_at'] != null) _joined = DateTime.parse(r['created_at']);
        _name = r['username'] as String?;
        _username.text = _name ?? '';
      });
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not fetch profile.');
    }
  }

  Future<void> _fetchEmail() async {
    if (!mounted) return;
    setState(() => _userEmail = FirebaseAuth.instance.currentUser?.email);
  }

  Future<void> _loadGoogleAvatar() async {
    if (!mounted) return;
    setState(() => _googleProfilePictureUrl = FirebaseAuth.instance.currentUser?.photoURL);
  }

  Future<void> _loadAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    for (final ext in ['png', 'jpg']) {
      try {
        final url = await Supabase.instance.client.storage
            .from('profilepictures')
            .createSignedUrl('${user.id}/profile.$ext', 60 * 60);
        if (mounted) setState(() => _profileImageUrl = url);
        return;
      } catch (_) {/* try next */}
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final picked =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _uploading = true);
      final ext = picked.path.split('.').last;
      final bytes = await File(picked.path).readAsBytes();
      await Supabase.instance.client.storage.from('profilepictures').uploadBinary(
            '${user.id}/profile.$ext',
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      await _loadAvatar();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to upload: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveUsername(BuildContext dialogContext) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final next = _username.text.trim();
    if (next.isEmpty) {
      showErrorSnackbar(context, 'Username cannot be empty.');
      return;
    }
    if (next == _name) {
      Navigator.of(dialogContext).pop();
      return;
    }
    setState(() => _savingUsername = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'username': next}).eq('id', user.id);
      if (!mounted) return;
      setState(() => _name = next);
      showSuccessSnackbar(context, 'Username updated.');
      Navigator.of(dialogContext).pop();
    } on PostgrestException catch (e) {
      if (mounted) showErrorSnackbar(context, e.message);
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not update username.');
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      if (mounted) showSuccessSnackbar(context, 'Signed out.');
    } on AuthException catch (e) {
      if (mounted) showErrorSnackbar(context, 'Sign out error: ${e.message}');
    } catch (_) {
      if (mounted) showSuccessSnackbar(context, 'Signed out (with warnings).');
    }
  }

  Future<void> _deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (user == null || jwt == null) return;
    setState(() => _deleting = true);
    try {
      final url = dotenv.env['SUPABASE_URL']!;
      final res = await http.post(
        Uri.parse('$url/functions/v1/delete-account'),
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200 && mounted) {
        await Supabase.instance.client.auth.signOut();
      } else if (mounted) {
        showErrorSnackbar(context, 'Could not delete account: ${res.body}');
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not delete: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_deleting) {
      return Scaffold(
        body: Center(child: VSLoadingIndicator(message: 'Deleting account…')),
      );
    }
    return Scaffold(
      body: VSResponsiveLayout(
        child: ListView(
          padding: VSResponsive.getResponsivePadding(context),
          children: [
            _hero(),
            const SizedBox(height: VSDesignTokens.space5),
            _accountCard(),
            const SizedBox(height: VSDesignTokens.space5),
            _dangerCard(),
            const SizedBox(height: VSDesignTokens.space12),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final initials = _initials(_name, _userEmail);

    return Container(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXXL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.25),
            cs.secondary.withValues(alpha: 0.15),
          ],
        ),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          _Avatar(
            size: 108,
            googleUrl: _googleProfilePictureUrl,
            customUrl: _profileImageUrl,
            initials: initials,
            uploading: _uploading,
            onTap: _pickAndUploadAvatar,
          ),
          const SizedBox(height: VSDesignTokens.space4),
          Text(
            _name ?? _userEmail ?? 'VisionSpark User',
            style: tt.headlineSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightBold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (_userEmail != null && _name != null) ...[
            const SizedBox(height: 2),
            Text(
              _userEmail!,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_joined != null) ...[
            const SizedBox(height: VSDesignTokens.space3),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: VSDesignTokens.space3,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
              ),
              child: Text(
                'Member since ${_formatJoin(_joined!)}',
                style: tt.bodySmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: VSTypography.weightSemiBold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountCard() {
    final cs = Theme.of(context).colorScheme;
    return VSCard(
      padding: EdgeInsets.zero,
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(VSDesignTokens.space5),
              child: const VSSectionHeader(
                icon: Icons.manage_accounts_rounded,
                title: 'Account',
                subtitle: 'Update your display name and avatar.',
              ),
            ),
            _SettingTile(
              icon: Icons.edit_rounded,
              title: 'Edit username',
              subtitle: _name ?? 'Choose a display name',
              onTap: _showUsernameDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dangerCard() {
    final cs = Theme.of(context).colorScheme;
    return VSCard(
      padding: EdgeInsets.zero,
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(VSDesignTokens.space5),
              child: VSSectionHeader(
                icon: Icons.warning_amber_rounded,
                title: 'Danger zone',
                subtitle: 'Sign out or permanently delete your account.',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusS),
                  ),
                  child: Text(
                    'Care',
                    style: TextStyle(
                      color: cs.error,
                      fontSize: 11,
                      fontWeight: VSTypography.weightBold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
            _SettingTile(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'You\'ll need to sign in again to use the app.',
              onTap: _signOut,
            ),
            Divider(
              height: 1,
              indent: VSDesignTokens.space5,
              endIndent: VSDesignTokens.space5,
            ),
            _SettingTile(
              icon: Icons.delete_forever_rounded,
              title: 'Delete account',
              subtitle: 'Erase your data permanently. This cannot be undone.',
              onTap: _confirmDelete,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }

  void _showUsernameDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setLocal) => AlertDialog(
            title: const Text('Edit username'),
            content: TextField(
              controller: _username,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Choose a display name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _savingUsername
                    ? null
                    : () async {
                        setLocal(() {});
                        await _saveUsername(dialogContext);
                        setLocal(() {});
                      },
                child: _savingUsername
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'This will permanently erase your data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteAccount();
  }

  static String _initials(String? name, String? email) {
    if (name != null && name.isNotEmpty) {
      final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
      return parts[0].substring(0, 1).toUpperCase();
    }
    if (email != null && email.isNotEmpty) return email[0].toUpperCase();
    return 'V';
  }

  static String _formatJoin(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _Avatar extends StatelessWidget {
  final double size;
  final String? googleUrl;
  final String? customUrl;
  final String initials;
  final bool uploading;
  final VoidCallback onTap;
  const _Avatar({
    required this.size,
    required this.googleUrl,
    required this.customUrl,
    required this.initials,
    required this.uploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget initialsWidget() => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [cs.primary, cs.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(
              initials,
              style: tt.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: VSTypography.weightBold,
              ),
            ),
          ),
        );

    Widget body;
    if (uploading) {
      body = Container(
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
        child: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    } else if (customUrl != null) {
      body = ClipOval(
        child: CachedNetworkImage(
          imageUrl: customUrl!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          placeholder: (_, __) => initialsWidget(),
          errorWidget: (_, __, ___) => googleUrl != null
              ? CachedNetworkImage(
                  imageUrl: googleUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => initialsWidget(),
                )
              : initialsWidget(),
        ),
      );
    } else if (googleUrl != null) {
      body = ClipOval(
        child: CachedNetworkImage(
          imageUrl: googleUrl!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          placeholder: (_, __) => initialsWidget(),
          errorWidget: (_, __, ___) => initialsWidget(),
        ),
      );
    } else {
      body = initialsWidget();
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant, width: 3),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(child: body),
          ),
        ),
        if (!uploading)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surface,
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant, width: 2),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Change avatar',
              icon: Icon(Icons.camera_alt_rounded, color: cs.primary, size: 18),
              onPressed: onTap,
            ),
          ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = destructive ? cs.error : cs.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(VSDesignTokens.space5),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(VSDesignTokens.space3),
              decoration: BoxDecoration(
                color: destructive
                    ? cs.error.withValues(alpha: 0.12)
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
              ),
              child: Icon(icon, color: destructive ? cs.error : cs.onSurfaceVariant, size: 20),
            ),
            const SizedBox(width: VSDesignTokens.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      color: color,
                      fontWeight: VSTypography.weightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
