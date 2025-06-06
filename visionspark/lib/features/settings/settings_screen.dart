import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../main.dart'; // Assuming ThemeController is in main.dart

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _autoUpload = false;

  // Define your fixed brand colors as static const
  // static const Color _lilacPurple = Color(0xFFD0B8E1); // REMOVED
  // static const Color _softTeal = Color(0xFF87CEEB); // REMOVED
  // static const Color _originalDarkText = Color(0xFF22223B); // A deep, nearly black color for text - This can be removed if primaryContentTextColor covers all its uses

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadAutoUpload();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
    });
  }

  Future<void> _loadAutoUpload() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoUpload = prefs.getBool('auto_upload_to_gallery') ?? false;
    });
  }

  Future<void> _setAutoUpload(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_upload_to_gallery', value);
    setState(() {
      _autoUpload = value;
    });
    // Optionally show a snackbar confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auto-upload set to ${value ? 'On' : 'Off'}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    final Brightness brightness = Theme.of(context).brightness;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // Dynamic colors based on theme brightness
    final Color scaffoldBackgroundColor = colorScheme.background;
    // final Color appBarBackgroundColor = brightness == Brightness.light ? Colors.white : colorScheme.surface; // Not used
    // final Color appBarIconColor = brightness == Brightness.light ? _originalDarkText : Colors.white.withOpacity(0.9); // Not used
    // final Color appBarTitleColor = appBarIconColor; // Not used

    final Color primaryContentTextColor = brightness == Brightness.light ? colorScheme.onSurface : Colors.white.withOpacity(0.9); // Adjusted _originalDarkText to be theme aware
    final Color secondaryContentTextColor = brightness == Brightness.light ? Colors.grey.shade600 : Colors.grey.shade400;

    final Color cardBackgroundColor = colorScheme.surface;
    final Color cardShadowColor = brightness == Brightness.light ? colorScheme.primary.withOpacity(0.08) : Colors.black.withOpacity(0.4);


    return Scaffold(
      backgroundColor: scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0), // Padding around the entire content
          child: Column(
            children: [
              Card(
                elevation: 6, // Increased elevation for a more prominent card
                color: cardBackgroundColor,
                shadowColor: cardShadowColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(vertical: 8.0), // Margin around the card
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0), // Padding inside the card
                  child: Column(
                    children: [
                      // --- Toggle Buttons Group ---
                      SwitchListTile(
                        title: Text('Dark Mode', style: TextStyle(color: primaryContentTextColor)),
                        subtitle: Text('Enable or disable dark theme', style: TextStyle(color: secondaryContentTextColor)),
                        value: themeController.isDarkMode,
                        onChanged: (value) => themeController.setDarkMode(value),
                        activeColor: colorScheme.primary,
                        activeTrackColor: colorScheme.primary.withOpacity(0.5),
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.grey.withOpacity(0.5),
                      ),
                      SwitchListTile(
                        title: Text('Auto-upload generated images to gallery', style: TextStyle(color: primaryContentTextColor)),
                        subtitle: Text('Automatically share new images to the public gallery', style: TextStyle(color: secondaryContentTextColor)),
                        value: _autoUpload,
                        onChanged: _setAutoUpload,
                        activeColor: colorScheme.primary, // Use theme color
                        activeTrackColor: colorScheme.primary.withOpacity(0.5),
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.grey.withOpacity(0.5),
                      ),
                      // --- Version Info ---
                      Divider(
                        height: 32, // Height of the divider
                        thickness: 1,
                        color: colorScheme.primary.withOpacity(0.3), // Themed divider color
                        indent: 16, // Indent from left
                        endIndent: 16, // Indent from right
                      ),
                      ListTile(
                        title: Text('App Version', style: TextStyle(color: primaryContentTextColor, fontWeight: FontWeight.w600)),
                        subtitle: Text(_version.isEmpty ? 'Loading...' : _version, style: TextStyle(color: secondaryContentTextColor)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}