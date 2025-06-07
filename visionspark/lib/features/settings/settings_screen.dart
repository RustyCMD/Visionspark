import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../main.dart'; // Assuming ThemeController is in main.dart
import 'package:supabase_flutter/supabase_flutter.dart'; // Added for Supabase
import '../../shared/notifiers/subscription_status_notifier.dart'; // Added for Notifier

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _autoUpload = false;
  String? _activeSubscription;
  bool _isLoadingSubscription = true;
  SubscriptionStatusNotifier? _subscriptionStatusNotifier;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadAutoUpload();
    _fetchSubscriptionStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = Provider.of<SubscriptionStatusNotifier>(context, listen: false);
    if (_subscriptionStatusNotifier != notifier) {
      _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
      _subscriptionStatusNotifier = notifier;
      _subscriptionStatusNotifier?.addListener(_onSubscriptionChanged);
    }
  }

  void _onSubscriptionChanged() {
    _fetchSubscriptionStatus();
  }

  Future<void> _fetchSubscriptionStatus() async {
    if (!mounted) return;
    setState(() {
      _isLoadingSubscription = true;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke('get-generation-status');
      if (mounted) {
        if (response.data != null) {
          final data = response.data;
          if (data['error'] != null) {
            setState(() {
              _activeSubscription = 'Error: ${data['error']}';
            });
          } else {
            final subType = data['active_subscription_type'];
            final limit = data['limit'];
            String subText = 'No Active Subscription';

            if (subType == 'monthly_30_generations' || subType == 'monthly_30') {
              subText = 'Standard Monthly';
              if (limit != null) subText += ' (Limit: $limit)';
            } else if (subType == 'monthly_unlimited_generations' || subType == 'monthly_unlimited') {
              subText = 'Unlimited Monthly';
              if (limit != null) subText += ' (Limit: ${limit == -1 ? "∞" : limit})';
            } else if (subType != null) {
              subText = subType.toString().replaceAll('_', ' ').split(' ').map((e) => e[0].toUpperCase() + e.substring(1)).join(' ');
              if (limit != null) subText += ' (Limit: ${limit == -1 ? "∞" : limit})';
            }

            setState(() {
              _activeSubscription = subText;
            });
          }
        } else {
          setState(() {
            _activeSubscription = 'Failed to load status: No data';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeSubscription = 'Error: ${e.toString()}';
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoadingSubscription = false;
      });
    }
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
                      // --- Active Subscription Info ---
                      ListTile(
                        title: Text('Active Subscription', style: TextStyle(color: primaryContentTextColor, fontWeight: FontWeight.w600)),
                        subtitle: _isLoadingSubscription
                            ? Row(
                                children: [
                                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)),
                                  const SizedBox(width: 8),
                                  Text('Loading...', style: TextStyle(color: secondaryContentTextColor)),
                                ],
                              )
                            : Text(_activeSubscription ?? 'N/A', style: TextStyle(color: secondaryContentTextColor)),
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

  @override
  void dispose() {
    _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
    super.dispose();
  }
}