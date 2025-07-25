import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../shared/utils/snackbar_utils.dart';
import '../../shared/design_system/design_system.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountSection extends StatefulWidget {
  const AccountSection({super.key});

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String? _profileImageUrl;
  DateTime? _joinDate;
  String? _username;
  final TextEditingController _usernameController = TextEditingController();
  bool _isSavingUsername = false;
  bool _isDeleting = false;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _loadProfileData();
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    await _fetchProfile();
    await _loadProfileImage();
  }

  Future<void> _fetchProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('created_at, username')
          .eq('id', user.id)
          .single();
      if (mounted) {
        setState(() {
          if (response['created_at'] != null) {
            _joinDate = DateTime.parse(response['created_at']);
          }
          _username = response['username'];
          _usernameController.text = _username ?? '';
        });
      }
    } catch (e) {
      if(mounted) showErrorSnackbar(context, 'Could not fetch profile.');
      debugPrint('Error fetching profile: $e');
    }
  }

  Future<void> _loadProfileImage() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    for (final ext in ['png', 'jpg']) {
      final storagePath = '${user.id}/profile.$ext';
      try {
        final urlResponse = await Supabase.instance.client.storage
            .from('profilepictures')
            .createSignedUrl(storagePath, 60 * 60);
        if (mounted) {
          setState(() {
            _profileImageUrl = urlResponse;
          });
        }
        return;
      } catch (_) {
        // Continue to next extension
      }
    }
  }

  Future<void> _pickAndUploadProfilePicture() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (pickedFile == null) return;
      if(mounted) setState(() => _isUploading = true);
      final file = File(pickedFile.path);
      final ext = pickedFile.path.split('.').last;
      final storagePath = '${user.id}/profile.$ext';
      final bytes = await file.readAsBytes();
      await Supabase.instance.client.storage
          .from('profilepictures')
          .uploadBinary(storagePath, bytes, fileOptions: const FileOptions(upsert: true));
      
      await _loadProfileImage();

    } catch (e) {
      if(mounted) showErrorSnackbar(context, 'Failed to upload profile picture: $e');
    } finally {
      if(mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveUsername(BuildContext dialogContext) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final newUsername = _usernameController.text.trim();

    if (newUsername.isEmpty) {
      showErrorSnackbar(context, 'Username cannot be empty.');
      return;
    }
    if (newUsername == _username) {
      Navigator.of(dialogContext).pop();
      return;
    }

    (dialogContext as Element).markNeedsBuild();
    setState(() => _isSavingUsername = true);

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'username': newUsername}).eq('id', user.id);
      if (mounted) {
        setState(() {
          _username = newUsername;
        });
        showSuccessSnackbar(context, 'Username updated successfully.');
        Navigator.of(dialogContext).pop();
      }
    } on PostgrestException catch (e) {
      if(mounted) showErrorSnackbar(context, 'Error: ${e.message}');
    } catch (e) {
      if(mounted) showErrorSnackbar(context, 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isSavingUsername = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
      await GoogleSignIn().signOut();
    } on AuthException catch (e) {
      if(mounted) showErrorSnackbar(context, e.message);
    } catch (e) {
      if(mounted) showErrorSnackbar(context, 'An unexpected error occurred during sign out.');
    }
  }

  Future<void> _deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (user == null || jwt == null) return;
    
    if(mounted) setState(() => _isDeleting = true);

    try {
      final projectUrl = dotenv.env['SUPABASE_URL']!;
      final response = await http.post(
        Uri.parse('$projectUrl/functions/v1/delete-account'),
        headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        if(mounted) await Supabase.instance.client.auth.signOut();
      } else {
        if(mounted) showErrorSnackbar(context, 'Failed to delete account: ${response.body}');
      }
    } catch (e) {
      if(mounted) showErrorSnackbar(context, 'Failed to delete account: $e');
    } finally {
      if(mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleting) {
      return Scaffold(
        body: Center(
          child: VSLoadingIndicator(
            message: 'Deleting account...',
            size: VSDesignTokens.iconXL,
          ),
        ),
      );
    }

    return Scaffold(
      body: VSResponsiveLayout(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: CustomScrollView(
                  slivers: [
                    _buildHeroSection(),
                    SliverPadding(
                      padding: VSResponsive.getResponsivePadding(context),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          const VSResponsiveSpacing(),
                          _buildAccountManagementCard(),
                          const VSResponsiveSpacing(),
                          _buildDangerZoneCard(),
                          const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final user = Supabase.instance.client.auth.currentUser;
    final size = MediaQuery.of(context).size;

    if (user == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    String getInitials(String? name, String? email) {
      if (name != null && name.isNotEmpty) {
        final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
        if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
        if (parts.isNotEmpty) return parts[0].substring(0, 1).toUpperCase();
      }
      if (email != null && email.isNotEmpty) {
        return email.substring(0, 1).toUpperCase();
      }
      return '';
    }

    final initials = getInitials(_username, user.email);

    return SliverToBoxAdapter(
      child: VSResponsiveBuilder(
        builder: (context, breakpoint) {
          final heroHeight = breakpoint == VSBreakpoint.mobile
            ? size.height * 0.45
            : size.height * 0.35;

          return Container(
            height: heroHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primaryContainer.withValues(alpha: 0.3),
                  colorScheme.surface,
                ],
                stops: const [0.0, 0.8],
              ),
            ),
            child: Stack(
              children: [
                // Background decoration
                Positioned(
                  top: -size.height * 0.1,
                  right: -size.width * 0.2,
                  child: Container(
                    width: size.width * 0.6,
                    height: size.width * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -size.height * 0.05,
                  left: -size.width * 0.15,
                  child: Container(
                    width: size.width * 0.4,
                    height: size.width * 0.4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colorScheme.secondary.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Profile content
                Positioned.fill(
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: VSResponsive.isMobile(context)
                            ? size.width - (VSDesignTokens.space6 * 2)
                            : 500,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: VSDesignTokens.space6,
                            vertical: VSDesignTokens.space4,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Profile picture with edit button
                              Flexible(
                                child: _buildProfilePicture(size, colorScheme, textTheme, initials),
                              ),

                              SizedBox(height: VSDesignTokens.space4),

                              // User info card
                              Flexible(
                                child: _buildUserInfoCard(user, colorScheme, textTheme),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfilePicture(Size size, ColorScheme colorScheme, TextTheme textTheme, String initials) {
    final profileSize = VSResponsive.isMobile(context)
      ? size.width * 0.32
      : VSDesignTokens.iconXXL * 2;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.2),
              blurRadius: VSDesignTokens.space6,
              offset: const Offset(0, VSDesignTokens.space2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
          // Profile picture container
          VSAccessibleButton(
            onPressed: _isUploading ? null : _pickAndUploadProfilePicture,
            semanticLabel: 'Profile picture. Tap to change.',
            child: Container(
              width: profileSize,
              height: profileSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 3,
                ),
              ),
              child: _isUploading
                ? VSLoadingIndicator(
                    size: VSDesignTokens.iconL,
                  )
                : _profileImageUrl != null
                  ? ClipOval(
                      child: Image.network(
                        _profileImageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildInitialsAvatar(colorScheme, textTheme, initials);
                        },
                      ),
                    )
                  : _buildInitialsAvatar(colorScheme, textTheme, initials),
            ),
          ),

          // Edit button
          if (!_isUploading)
            Container(
              width: VSDesignTokens.touchTargetMin * 0.7,
              height: VSDesignTokens.touchTargetMin * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surface,
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.15),
                    blurRadius: VSDesignTokens.space2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: VSAccessibleButton(
                onPressed: _pickAndUploadProfilePicture,
                semanticLabel: 'Change profile picture',
                tooltip: 'Change profile picture',
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: VSDesignTokens.iconS,
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar(ColorScheme colorScheme, TextTheme textTheme, String initials) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.secondary,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: textTheme.displaySmall?.copyWith(
            color: colorScheme.onPrimary,
            fontWeight: VSTypography.weightBold,
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(User user, ColorScheme colorScheme, TextTheme textTheme) {
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      color: colorScheme.surface.withValues(alpha: 0.8),
      borderRadius: VSDesignTokens.radiusXXL,
      border: Border.all(
        color: colorScheme.outline.withValues(alpha: 0.15),
        width: 1,
      ),
      elevation: VSDesignTokens.elevation2,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          VSResponsiveText(
            text: _username ?? user.email ?? 'VisionSpark User',
            baseStyle: textTheme.headlineSmall?.copyWith(
              fontWeight: VSTypography.weightBold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          if (_username != null && user.email != null) ...[
            const SizedBox(height: VSDesignTokens.space1),
            Text(
              user.email!,
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
          if (_joinDate != null) ...[
            const SizedBox(height: VSDesignTokens.space3),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: VSDesignTokens.space3,
                  vertical: VSDesignTokens.space1,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                ),
                child: Text(
                  'Member since ${_formatJoinDate(_joinDate!)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountManagementCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSCard(
      color: colorScheme.surface,
      borderRadius: VSDesignTokens.radiusXXL,
      border: Border.all(
        color: colorScheme.outline.withValues(alpha: 0.15),
        width: 1,
      ),
      elevation: VSDesignTokens.elevation2,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(VSDesignTokens.space6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(VSDesignTokens.space3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                  ),
                  child: Icon(
                    Icons.manage_accounts_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: VSDesignTokens.iconM,
                  ),
                ),
                const SizedBox(width: VSDesignTokens.space4),
                Text(
                  'Account Management',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: VSTypography.weightBold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Settings tiles
          _buildSettingsTile(
            icon: Icons.edit_rounded,
            title: 'Edit Username',
            subtitle: _username ?? 'Set your display name',
            onTap: () => _showEditUsernameDialog(context),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSCard(
      color: colorScheme.surface,
      borderRadius: VSDesignTokens.radiusXXL,
      border: Border.all(
        color: colorScheme.error.withValues(alpha: 0.2),
        width: 1,
      ),
      elevation: VSDesignTokens.elevation2,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(VSDesignTokens.space6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(VSDesignTokens.space3),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                  ),
                  child: Icon(
                    Icons.warning_rounded,
                    color: colorScheme.onErrorContainer,
                    size: VSDesignTokens.iconM,
                  ),
                ),
                const SizedBox(width: VSDesignTokens.space4),
                Text(
                  'Danger Zone',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: VSTypography.weightBold,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ),

          // Settings tiles
          _buildSettingsTile(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            subtitle: 'Sign out of your account',
            onTap: _signOut,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSDesignTokens.space6),
            child: Divider(
              color: colorScheme.outline.withValues(alpha: 0.2),
              height: 1,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.delete_forever_rounded,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account and all data',
            onTap: _showDeleteAccountConfirmation,
            textColor: colorScheme.error,
            isDestructive: true,
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSAccessibleCard(
      onTap: onTap,
      semanticLabel: '$title. $subtitle',
      semanticHint: 'Tap to ${title.toLowerCase()}',
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(VSDesignTokens.space3),
            decoration: BoxDecoration(
              color: isDestructive
                ? colorScheme.errorContainer.withValues(alpha: 0.2)
                : colorScheme.surfaceContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
            ),
            child: Icon(
              icon,
              color: textColor ?? (isDestructive
                ? colorScheme.onErrorContainer
                : colorScheme.onSurfaceVariant),
              size: VSDesignTokens.iconS,
            ),
          ),
          const SizedBox(width: VSDesignTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: textColor ?? colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
                const SizedBox(height: VSDesignTokens.space1),
                Text(
                  subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            size: VSDesignTokens.iconS,
          ),
        ],
      ),
    );
  }
  
  void _showEditUsernameDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Username'),
              content: TextField(
                controller: _usernameController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Enter new username'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isSavingUsername ? null : () async {
                    setDialogState(() { _isSavingUsername = true; });
                    await _saveUsername(dialogContext);
                    if(mounted) setDialogState(() { _isSavingUsername = false; });
                  },
                  child: _isSavingUsername ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _showDeleteAccountConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to delete your account? This action is permanent and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  String _formatJoinDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}