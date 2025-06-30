import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../main.dart'; // Assuming ThemeController is in main.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart'; // For launching URLs

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

  // Helper function to launch URLs
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch $urlString')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching URL: An unexpected error occurred.')),
        );
      }
    }
  }

  Future<void> _clearImageCache() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Clear Cache'),
          content: const Text('Are you sure you want to clear all cached images? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              child: Text('Clear Cache', style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        await DefaultCacheManager().emptyCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image cache cleared successfully!')),
        );
      } catch (e) {
        debugPrint("Error clearing cache: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error clearing cache: An unexpected error occurred.')),
        );
      }
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
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // backgroundColor is inherited from theme.background automatically
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Card(
                elevation: 2, // Standard elevation
                color: colorScheme.surfaceContainerLow, // Use a M3 surface color
                shadowColor: colorScheme.shadow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text('Dark Mode', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                        subtitle: Text('Enable or disable dark theme', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                        value: themeController.isDarkMode,
                        onChanged: (value) => themeController.setDarkMode(value),
                        activeColor: colorScheme.primary,
                        activeTrackColor: colorScheme.primary.withOpacity(0.5),
                        inactiveThumbColor: colorScheme.outline,
                        inactiveTrackColor: colorScheme.surfaceVariant,
                      ),
                      SwitchListTile(
                        title: Text('Auto-upload generated images to gallery', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                        subtitle: Text('Automatically share new images to the public gallery', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                        value: _autoUpload,
                        onChanged: _setAutoUpload,
                        activeColor: colorScheme.primary,
                        activeTrackColor: colorScheme.primary.withOpacity(0.5),
                        inactiveThumbColor: colorScheme.outline,
                        inactiveTrackColor: colorScheme.surfaceVariant,
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_sweep_outlined, color: colorScheme.onSurfaceVariant),
                        title: Text('Clear Image Cache', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                        subtitle: Text('Remove cached images from gallery and network', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                        onTap: _clearImageCache,
                      ),
                      Divider(
                        height: 32,
                        thickness: 1,
                        color: colorScheme.outlineVariant, // Standard M3 divider color
                        indent: 16,
                        endIndent: 16,
                      ),
                      ListTile(
                        title: Text('App Version', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600)),
                        subtitle: Text(_version.isEmpty ? 'Loading...' : _version, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                      ),
                      ListTile(
                        title: Text('Active Subscription', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600)),
                        subtitle: _isLoadingSubscription
                            ? Row(
                                children: [
                                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)),
                                  const SizedBox(width: 8),
                                  Text('Loading...', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                                ],
                              )
                            : Text(_activeSubscription ?? 'N/A', style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                      ),
                      Divider(indent: 16, endIndent: 16, color: colorScheme.outlineVariant),
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined, color: colorScheme.onSurfaceVariant),
                        title: Text('Privacy Policy', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                        onTap: () => _launchURL('https://visionspark.app/privacy-policy.html'),
                      ),
                      ListTile(
                        leading: Icon(Icons.description_outlined, color: colorScheme.onSurfaceVariant),
                        title: Text('Terms of Service', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                        onTap: () => _launchURL('https://visionspark.app/terms-of-service.html'),
                      ),
                      ListTile(
                        leading: Icon(Icons.subscriptions_outlined, color: colorScheme.onSurfaceVariant),
                        title: Text('Manage Subscription', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
                        onTap: () {
                          // General link for Google Play. For specific SKU management, a more detailed URL might be needed if available.
                          // https://developer.android.com/google/play/billing/subscriptions#deep-link
                          // Example: "https://play.google.com/store/account/subscriptions?sku=your-sku&package=com.example.app"
                          _launchURL('https://play.google.com/store/account/subscriptions');
                        },
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