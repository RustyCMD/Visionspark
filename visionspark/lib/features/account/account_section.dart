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
  late AnimationController _profileAnimationController;
  late Animation<double> _profileScaleAnimation;

  @override
  void initState() {
    super.initState();
    _profileAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _profileScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _profileAnimationController, curve: Curves.elasticOut),
    );
    _loadProfileData();
    _profileAnimationController.forward();
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _profileAnimationController.dispose();
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
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainer.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: _isDeleting 
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    SizedBox(height: size.height * 0.03),
                    _buildModernProfileHeader(colorScheme, size),
                    SizedBox(height: size.height * 0.05),
                    _buildSettingsGrid(colorScheme),
                    SizedBox(height: size.height * 0.03),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildModernProfileHeader(ColorScheme colorScheme, Size size) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();

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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: _profileScaleAnimation,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primary.withOpacity(0.1),
                        colorScheme.secondary.withOpacity(0.1),
                      ],
                    ),
                  ),
                ),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: _isUploading
                          ? CircularProgressIndicator(color: colorScheme.primary)
                          : _profileImageUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    _profileImageUrl!,
                                    width: 110,
                                    height: 110,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Container(
                                  width: 110,
                                  height: 110,
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
                                      style: TextStyle(
                                        fontSize: 36,
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                    GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadProfilePicture,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 18,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _username ?? user.email ?? 'VisionSpark User',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          if (_username != null && user.email != null) ...[
            const SizedBox(height: 8),
            Text(
              user.email!,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (_joinDate != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Member since ${_formatJoinDate(_joinDate!)}',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsGrid(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildModernSettingsCard(
            colorScheme,
            title: 'Profile Settings',
            items: [
              _SettingsItem(
                icon: Icons.edit_rounded,
                title: 'Edit Username',
                subtitle: _username ?? 'Set your display name',
                onTap: () => _showModernEditDialog(context),
                trailing: Icons.arrow_forward_ios_rounded,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildModernSettingsCard(
            colorScheme,
            title: 'Account Actions',
            isWarning: true,
            items: [
              _SettingsItem(
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                subtitle: 'Sign out of your account',
                onTap: _signOut,
                trailing: Icons.arrow_forward_ios_rounded,
              ),
              _SettingsItem(
                icon: Icons.delete_forever_rounded,
                title: 'Delete Account',
                subtitle: 'Permanently delete your account',
                onTap: _showDeleteAccountConfirmation,
                trailing: Icons.arrow_forward_ios_rounded,
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernSettingsCard(
    ColorScheme colorScheme, {
    required String title,
    required List<_SettingsItem> items,
    bool isWarning = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isWarning 
          ? colorScheme.errorContainer.withOpacity(0.1)
          : colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isWarning 
            ? colorScheme.error.withOpacity(0.2)
            : colorScheme.outline.withOpacity(0.2),
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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isWarning 
                  ? colorScheme.error
                  : colorScheme.onSurface,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == items.length - 1;
            
            return Column(
              children: [
                _buildModernSettingsTile(colorScheme, item),
                if (!isLast)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    height: 1,
                    color: colorScheme.outline.withOpacity(0.1),
                  ),
              ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildModernSettingsTile(ColorScheme colorScheme, _SettingsItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: item.isDestructive 
          ? colorScheme.error.withOpacity(0.1)
          : colorScheme.primary.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.isDestructive
                    ? colorScheme.error.withOpacity(0.1)
                    : colorScheme.surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  color: item.isDestructive
                    ? colorScheme.error
                    : colorScheme.onSurface,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: item.isDestructive
                          ? colorScheme.error
                          : colorScheme.onSurface,
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                item.trailing,
                size: 18,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showModernEditDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Username',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
              'Edit Username',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: TextField(
              controller: _usernameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter new username',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _isSavingUsername ? null : () => _saveUsername(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: _isSavingUsername
                  ? const SizedBox(
                      height: 20,
                      width: 20,
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
  
  void _showDeleteAccountConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(
              Icons.warning_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Account',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete your account? This action is permanent and cannot be undone.',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
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

class _SettingsItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final IconData trailing;
  final bool isDestructive;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    required this.trailing,
    this.isDestructive = false,
  });
}