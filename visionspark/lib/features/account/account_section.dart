import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../shared/utils/snackbar_utils.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../shared/widgets/page_container.dart';

class AccountSection extends StatefulWidget {
  const AccountSection({super.key});

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String? _profileImageUrl;
  DateTime? _joinDate;
  String? _username;
  final TextEditingController _usernameController = TextEditingController();
  bool _isSavingUsername = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
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
    // Check common image extensions
    for (final ext in ['png', 'jpg']) {
      final storagePath = '${user.id}/profile.$ext';
      try {
        final urlResponse = await Supabase.instance.client.storage
            .from('profilepictures')
            .createSignedUrl(storagePath, 60 * 60); // 1 hour validity
        if (mounted) {
          setState(() {
            _profileImageUrl = urlResponse;
          });
        }
        return; // Exit after finding the first valid image
      } catch (_) {
        // Silently continue to the next extension if image is not found
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
      
      // After upload, reload the image to get the new signed URL
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
      Navigator.of(dialogContext).pop(); // Close dialog if no change
      return;
    }

    // This setState call needs to be managed carefully with a StatefulBuilder in the dialog
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
        Navigator.of(dialogContext).pop(); // Close dialog on success
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
      // AuthGate will handle navigation
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
        // AuthGate will handle navigation
      } else {
        if(mounted) showErrorSnackbar(context, 'Failed to delete account: ${response.body}');
      }
    } catch (e) {
      if(mounted) showErrorSnackbar(context, 'Failed to delete account: $e');
    } finally {
      if(mounted) setState(() => _isDeleting = false);
    }
  }

  // --- UI Builder Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: PageContainer(
            padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
            child: _isDeleting ? const Center(child: CircularProgressIndicator()) : Column(
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 32),
                _buildAccountSettingsCard(),
                const SizedBox(height: 24),
                _buildDangerZoneCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final colorScheme = Theme.of(context).colorScheme;
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

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: colorScheme.primary.withOpacity(0.2),
              child: _isUploading
                  ? CircularProgressIndicator(color: colorScheme.primary)
                  : _profileImageUrl != null
                      ? CircleAvatar(radius: 50, backgroundImage: NetworkImage(_profileImageUrl!))
                      : CircleAvatar(
                          radius: 50,
                          backgroundColor: colorScheme.primary,
                          child: Text(initials, style: TextStyle(fontSize: 40, color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
                        ),
            ),
            InkWell(
              onTap: _isUploading ? null : _pickAndUploadProfilePicture,
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.surface,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.secondary,
                  child: Icon(Icons.camera_alt, size: 18, color: colorScheme.onSecondary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _username ?? user.email ?? 'Visionspark User',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (_username != null && user.email != null)
          Text(user.email!, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface.withOpacity(0.7))),
        if (_joinDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Joined ${_formatJoinDate(_joinDate!)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.5)),
            ),
          ),
      ],
    );
  }

  Widget _buildAccountSettingsCard() {
    return _buildSettingsCard(
      title: 'Account Settings',
      children: [
        _buildSettingsTile(
          icon: Icons.edit_outlined,
          title: 'Edit Username',
          subtitle: _username ?? 'Set your display name',
          onTap: () => _showEditUsernameDialog(context),
        ),
      ],
    );
  }

  Widget _buildDangerZoneCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSettingsCard(
      title: 'Danger Zone',
      cardColor: colorScheme.errorContainer.withOpacity(0.4),
      children: [
        _buildSettingsTile(
          icon: Icons.logout,
          title: 'Logout',
          onTap: _signOut,
        ),
        const Divider(),
        _buildSettingsTile(
          icon: Icons.delete_forever_outlined,
          title: 'Delete Account',
          textColor: colorScheme.error,
          onTap: _showDeleteAccountConfirmation,
        ),
      ],
    );
  }

  Widget _buildSettingsCard({required String title, required List<Widget> children, Color? cardColor}) {
    return Card(
      color: cardColor ?? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsTile({required IconData icon, required String title, String? subtitle, required VoidCallback onTap, Color? textColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      leading: Icon(icon, color: textColor ?? colorScheme.onSurfaceVariant),
      title: Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500, color: textColor ?? colorScheme.onSurface)),
      subtitle: subtitle != null ? Text(subtitle, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.7))) : null,
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
      onTap: onTap,
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
                    // Manually trigger a rebuild of the dialog's state
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