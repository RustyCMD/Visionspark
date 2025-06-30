import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../shared/utils/snackbar_utils.dart';
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
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: _isDeleting 
        ? Center(child: CircularProgressIndicator()) 
        : AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: CustomScrollView(
                    slivers: [
                      _buildHeroSection(size),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: size.width * 0.06,
                          vertical: size.height * 0.02,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            SizedBox(height: size.height * 0.02),
                            _buildAccountManagementCard(),
                            SizedBox(height: size.height * 0.024),
                            _buildDangerZoneCard(),
                            SizedBox(height: size.height * 0.04),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _buildHeroSection(Size size) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final user = Supabase.instance.client.auth.currentUser;
    
    if (user == null) return SliverToBoxAdapter(child: SizedBox.shrink());

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
      child: Container(
        height: size.height * 0.45,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer.withOpacity(0.3),
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
                      colorScheme.primary.withOpacity(0.1),
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
                      colorScheme.secondary.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            
            // Profile content
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.06,
                vertical: size.height * 0.06,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Profile picture with edit button
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: size.width * 0.32,
                          height: size.width * 0.32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.2),
                              width: 3,
                            ),
                          ),
                          child: _isUploading
                              ? CircularProgressIndicator(color: colorScheme.primary)
                              : _profileImageUrl != null
                                  ? ClipOval(
                                      child: Image.network(
                                        _profileImageUrl!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                                    )
                                  : Container(
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
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                        ),
                        Container(
                          width: size.width * 0.12,
                          height: size.width * 0.12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.surface,
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.3),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isUploading ? null : _pickAndUploadProfilePicture,
                              borderRadius: BorderRadius.circular(size.width * 0.06),
                              child: Icon(
                                Icons.camera_alt_rounded,
                                size: size.width * 0.06,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: size.height * 0.03),
                  
                  // User info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.15),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          _username ?? user.email ?? 'VisionSpark User',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_username != null && user.email != null) ...[
                          SizedBox(height: size.height * 0.006),
                          Text(
                            user.email!,
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (_joinDate != null) ...[
                          SizedBox(height: size.height * 0.012),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Member since ${_formatJoinDate(_joinDate!)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountManagementCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.manage_accounts_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Account Management',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          _buildModernSettingsTile(
            icon: Icons.edit_rounded,
            title: 'Edit Username',
            subtitle: _username ?? 'Set your display name',
            onTap: () => _showEditUsernameDialog(context),
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.error.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.error.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.warning_rounded,
                    color: colorScheme.onErrorContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Danger Zone',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          _buildModernSettingsTile(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            subtitle: 'Sign out of your account',
            onTap: _signOut,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Divider(
              color: colorScheme.outline.withOpacity(0.2),
              height: 1,
            ),
          ),
          _buildModernSettingsTile(
            icon: Icons.delete_forever_rounded,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account and all data',
            onTap: _showDeleteAccountConfirmation,
            textColor: colorScheme.error,
            colorScheme: colorScheme,
            textTheme: textTheme,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildModernSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    Color? textColor,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDestructive 
                    ? colorScheme.errorContainer.withOpacity(0.2)
                    : colorScheme.surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: textColor ?? colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: textColor ?? colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                size: 20,
              ),
            ],
          ),
        ),
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