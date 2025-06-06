import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AccountSection extends StatefulWidget {
  const AccountSection({super.key});

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  String? _error;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String? _profileImageUrl;
  DateTime? _joinDate;
  String? _username;
  final TextEditingController _usernameController = TextEditingController();
  bool _isSavingUsername = false;
  bool _isDeleting = false;

  // Define your fixed brand colors as static const
  static const Color _originalDarkText = Color(0xFF22223B); // A deep, nearly black color for text

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Unexpected error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred during sign out: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _pickAndUploadProfilePicture() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (pickedFile == null) return;
      setState(() => _isUploading = true);
      final file = File(pickedFile.path);
      final ext = pickedFile.path.split('.').last;
      final storagePath = '${user.id}/profile.$ext';
      final bytes = await file.readAsBytes();
      await Supabase.instance.client.storage
          .from('profilepictures')
          .uploadBinary(storagePath, bytes, fileOptions: const FileOptions(upsert: true));
      final urlResponse = await Supabase.instance.client.storage
          .from('profilepictures')
          .createSignedUrl(storagePath, 60 * 60); // 1 hour
      setState(() {
        _profileImageUrl = urlResponse;
        _isUploading = false;
      });
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload profile picture: $e')),
      );
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
            .createSignedUrl(storagePath, 60 * 60); // 1 hour
        setState(() {
          _profileImageUrl = urlResponse;
        });
        return;
      } catch (_) {
        // Continue to next extension if not found
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
    _fetchProfile();
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
      setState(() {
        if (response['created_at'] != null) {
          _joinDate = DateTime.parse(response['created_at']);
        }
        _username = response['username'];
        _usernameController.text = _username ?? '';
      });
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  Future<void> _saveUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) {
      if (mounted) {
        setState(() => _error = 'Username cannot be empty.');
      }
      return;
    }
    if (newUsername == _username) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username is already up to date.')),
        );
      }
      return;
    }
    setState(() {
      _isSavingUsername = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'username': newUsername})
          .eq('id', user.id)
          .select()
          .single();
      if (mounted) {
        setState(() {
          _username = newUsername;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username updated successfully.')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update username: ${e.message}')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to update username: $e';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update username: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingUsername = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (user == null || jwt == null) return;
    setState(() { _isDeleting = true; });
    try {
      final projectUrl = dotenv.env['SUPABASE_URL']!;
      final response = await http.post(
        Uri.parse('$projectUrl/functions/v1/delete-account'),
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
      );
      final body = response.body;
      if (response.statusCode == 200) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          // Navigate to a root screen (e.g., login) and remove all previous routes
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } else {
        setState(() {
          _error = 'Failed to delete account: ${body.isNotEmpty ? body : response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to delete account: $e';
      });
    } finally {
      if (mounted) setState(() { _isDeleting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // Dynamic colors based on theme brightness
    final Color cardBackgroundColor = colorScheme.surface;
    final Color cardShadowColor = brightness == Brightness.light ? colorScheme.primary.withOpacity(0.08) : Colors.black.withOpacity(0.4);

    final Color primaryContentTextColor = brightness == Brightness.light ? _originalDarkText : Colors.white.withOpacity(0.9);
    final Color secondaryContentTextColor = brightness == Brightness.light ? Colors.grey.shade600 : Colors.grey.shade400;

    final Color onAccentButtonColor = brightness == Brightness.light ? _originalDarkText : Colors.white;

    final Color textFieldBorderColor = brightness == Brightness.light ? colorScheme.primary : Colors.grey.shade700;
    final Color textFieldFocusedBorderColor = colorScheme.secondary; // Always vibrant
    final Color textFieldInputColor = primaryContentTextColor;
    final Color textFieldHintColor = secondaryContentTextColor;

    final Color errorBackgroundColor = brightness == Brightness.light ? Colors.red.shade100 : Colors.red.shade900.withOpacity(0.4);
    final Color errorTextColor = brightness == Brightness.light ? Colors.red.shade800 : Colors.red.shade100;
    final Color errorIconColor = brightness == Brightness.light ? Colors.red.shade600 : Colors.red.shade200;


    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return const Center(
        child: Text('Error: No user session found. Please restart the app.'),
      );
    }

    // Get initials from email or username
    String getInitials(String? name, String? email) {
      if (name != null && name.isNotEmpty) {
        final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
        if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
        if (parts.isNotEmpty) return parts[0].substring(0, 1).toUpperCase();
      }
      if (email != null && email.isNotEmpty) {
        final emailParts = email.split('@').first.split(RegExp(r'[^a-zA-Z]'));
        final filteredEmailParts = emailParts.where((e) => e.isNotEmpty).toList();
        if (filteredEmailParts.length >= 2) return (filteredEmailParts[0][0] + filteredEmailParts[1][0]).toUpperCase();
        if (filteredEmailParts.isNotEmpty) return filteredEmailParts[0].substring(0, 1).toUpperCase();
        return email.substring(0, 2).toUpperCase();
      }
      return '';
    }

    final initials = getInitials(_username, user.email);

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24), // Outer padding for the entire screen content
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              elevation: 8, // Slightly increased elevation for more depth
              color: cardBackgroundColor,
              shadowColor: cardShadowColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Profile Header (Avatar, Username/Email, Joined Date, Logout Button)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Profile Picture / Initials with Camera Icon
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            _isUploading
                                ? CircleAvatar(
                                    radius: 36,
                                    backgroundColor: colorScheme.primary, // Placeholder background
                                    child: CircularProgressIndicator(color: colorScheme.onPrimary), // Loader color
                                  )
                                : _profileImageUrl != null
                                    ? CircleAvatar(
                                        radius: 36,
                                        backgroundImage: NetworkImage(_profileImageUrl!),
                                      )
                                    : CircleAvatar(
                                        radius: 36,
                                        backgroundColor: colorScheme.primary,
                                        child: Text(
                                          initials,
                                          style: TextStyle(fontSize: 28, color: colorScheme.onPrimary, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: InkWell(
                                onTap: _isUploading ? null : _pickAndUploadProfilePicture,
                                customBorder: const CircleBorder(),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: colorScheme.secondary,
                                  child: Icon(Icons.camera_alt, size: 16, color: colorScheme.onSecondary),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _username?.isNotEmpty == true ? _username! : user.email ?? 'No email',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryContentTextColor),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              if (_username?.isNotEmpty == true && user.email?.isNotEmpty == true)
                                Text(
                                  user.email!,
                                  style: TextStyle(fontSize: 14, color: secondaryContentTextColor),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              if (_joinDate != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    'Joined: ${_formatJoinDate(_joinDate!)}',
                                    style: TextStyle(fontSize: 14, color: secondaryContentTextColor),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100, // Fixed width for consistent button size
                          child: ElevatedButton.icon(
                            onPressed: _signOut,
                            icon: Icon(Icons.logout, size: 18, color: onAccentButtonColor),
                            label: Text('Logout', style: TextStyle(fontSize: 14, color: onAccentButtonColor)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.secondary,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Divider(height: 40, thickness: 1, color: colorScheme.primary.withOpacity(0.5)), // Visual separation

                    // 2. Update Username Section
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Update Username',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryContentTextColor)),
                          const SizedBox(height: 16),
                          Text('New Username', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryContentTextColor)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _usernameController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter your new username',
                                    hintStyle: TextStyle(color: textFieldHintColor, fontSize: 15),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: textFieldBorderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: textFieldBorderColor.withOpacity(0.7)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: textFieldFocusedBorderColor, width: 2),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  ),
                                  style: TextStyle(color: textFieldInputColor),
                                  enabled: !_isSavingUsername,
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: _isSavingUsername ? null : _saveUsername,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.secondary,
                                  foregroundColor: onAccentButtonColor,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isSavingUsername
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: onAccentButtonColor),
                                      )
                                    : Text('Save', style: TextStyle(fontSize: 16, color: onAccentButtonColor)),
                              ),
                            ],
                          ),
                          if (_username != null && _username!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Current username: $_username',
                                style: TextStyle(fontSize: 14, color: secondaryContentTextColor),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error Message Display
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: errorBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: errorIconColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: errorTextColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Delete Account Section (now inside the card)
                    Divider(height: 40, thickness: 1, color: colorScheme.error.withOpacity(0.5)),
                    Text(
                      'Danger Zone',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    _isDeleting
                        ? CircularProgressIndicator(color: colorScheme.error)
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.error,
                              foregroundColor: colorScheme.onError, // Text/icon color for error button
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            icon: Icon(Icons.delete_forever, color: colorScheme.onError),
                            label: Text('Delete Account', style: TextStyle(color: colorScheme.onError, fontSize: 16)),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: cardBackgroundColor, // Use card background for dialog
                                  title: Text('Delete Account', style: TextStyle(color: primaryContentTextColor)),
                                  content: Text(
                                    'Are you sure you want to delete your account? This action cannot be undone.',
                                    style: TextStyle(color: secondaryContentTextColor),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      child: Text('Cancel', style: TextStyle(color: primaryContentTextColor)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error),
                                      onPressed: () => Navigator.of(context).pop(true),
                                      child: Text('Delete', style: TextStyle(color: colorScheme.onError)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await _deleteAccount();
                              }
                            },
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatJoinDate(DateTime date) {
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}