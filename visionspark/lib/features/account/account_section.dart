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
  
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    
    _loadProfileData();
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _floatController.dispose();
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

    if (_isDeleting) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surface,
                colorScheme.errorContainer.withOpacity(0.1),
              ],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 24),
                Text('Deleting account...'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.3, 1.0],
            colors: [
              colorScheme.surface,
              colorScheme.primary.withOpacity(0.02),
              colorScheme.secondary.withOpacity(0.03),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Floating decorations
              _buildFloatingDecorations(colorScheme, size),
              
              // Main content
              SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.06,
                  vertical: size.height * 0.02,
                ),
                child: Column(
                  children: [
                    SizedBox(height: size.height * 0.03),
                    _buildProfileHeader(colorScheme, size),
                    SizedBox(height: size.height * 0.04),
                    _buildAccountSettingsCard(colorScheme),
                    SizedBox(height: size.height * 0.03),
                    _buildDangerZoneCard(colorScheme),
                    SizedBox(height: size.height * 0.04),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingDecorations(ColorScheme colorScheme, Size size) {
    return Stack(
      children: [
        // Top floating element
        AnimatedBuilder(
          animation: _floatAnimation,
          builder: (context, child) {
            return Positioned(
              top: size.height * 0.1 + _floatAnimation.value,
              right: size.width * 0.05,
              child: Container(
                width: size.width * 0.3,
                height: size.width * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withOpacity(0.04),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
            );
          },
        ),
        
        // Bottom floating element
        AnimatedBuilder(
          animation: _floatAnimation,
          builder: (context, child) {
            return Positioned(
              bottom: size.height * 0.15 - _floatAnimation.value,
              left: size.width * 0.02,
              child: Container(
                width: size.width * 0.25,
                height: size.width * 0.25,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: colorScheme.secondary.withOpacity(0.03),
                  border: Border.all(
                    color: colorScheme.secondary.withOpacity(0.08),
                    width: 1,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildProfileHeader(ColorScheme colorScheme, Size size) {
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
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withOpacity(0.3),
            colorScheme.secondaryContainer.withOpacity(0.2),
          ],
        ),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile picture with unique styling
          Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.2),
                      colorScheme.secondary.withOpacity(0.1),
                    ],
                  ),
                ),
              ),
              // Profile image
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: _isUploading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: colorScheme.primary,
                          strokeWidth: 3,
                        ),
                      )
                    : _profileImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(60),
                            child: Image.network(
                              _profileImageUrl!,
                              fit: BoxFit.cover,
                              width: 120,
                              height: 120,
                            ),
                          )
                        : CircleAvatar(
                            radius: 60,
                            backgroundColor: colorScheme.primary,
                            child: Text(
                              initials,
                              style: TextStyle(
                                fontSize: 48,
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
              ),
              // Camera button
              Positioned(
                bottom: 0,
                right: 10,
                child: GestureDetector(
                  onTap: _isUploading ? null : _pickAndUploadProfilePicture,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                      border: Border.all(
                        color: colorScheme.surface,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: 20,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // User info with modern typography
          Text(
            _username ?? user.email ?? 'Visionspark User',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          
          if (_username != null && user.email != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                user.email!,
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          ],
          
          if (_joinDate != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Joined ${_formatJoinDate(_joinDate!)}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountSettingsCard(ColorScheme colorScheme) {
    return _buildModernCard(
      title: 'Account Settings',
      icon: Icons.settings,
      color: colorScheme.primaryContainer,
      children: [
        _buildModernSettingsTile(
          icon: Icons.edit_outlined,
          title: 'Edit Username',
          subtitle: _username ?? 'Set your display name',
          onTap: () => _showEditUsernameDialog(context),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildDangerZoneCard(ColorScheme colorScheme) {
    return _buildModernCard(
      title: 'Account Actions',
      icon: Icons.warning_amber_rounded,
      color: colorScheme.errorContainer,
      children: [
        _buildModernSettingsTile(
          icon: Icons.logout,
          title: 'Sign Out',
          subtitle: 'Sign out of your account',
          onTap: _signOut,
          colorScheme: colorScheme,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Divider(
            color: colorScheme.outline.withOpacity(0.2),
            height: 1,
          ),
        ),
        _buildModernSettingsTile(
          icon: Icons.delete_forever_outlined,
          title: 'Delete Account',
          subtitle: 'Permanently delete your account',
          textColor: colorScheme.error,
          onTap: _showDeleteAccountConfirmation,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildModernCard({
    required String title,
    required IconData icon,
    required ColorScheme color,
    required List<Widget> children,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: color.withOpacity(0.1),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: colorScheme.onSurface,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          ...children,
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildModernSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? textColor,
    required ColorScheme colorScheme,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (textColor ?? colorScheme.primary).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: textColor ?? colorScheme.primary,
                  size: 20,
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
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurface.withOpacity(0.4),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Edit Username'),
              content: TextField(
                controller: _usernameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter new username',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSavingUsername 
                      ? const SizedBox(
                          height: 20, 
                          width: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2)
                        ) 
                      : const Text('Save'),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action is permanent and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error, 
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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