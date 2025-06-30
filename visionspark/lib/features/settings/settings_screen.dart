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
              _buildAppearanceCard(themeController, colorScheme, textTheme),
              const SizedBox(height: 16),
              _buildPreferenceCard(colorScheme, textTheme),
              const SizedBox(height: 16),
              _buildInfoCard(colorScheme, textTheme),
              const SizedBox(height: 16),
              _buildLinksCard(colorScheme, textTheme),
            ],
          ),
        ),
      ),
    );
  }

  // --- Card Builders ---
  Card _styledCard(Widget child, ColorScheme scheme) => Card(
        elevation: 3,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _buildAppearanceCard(ThemeController controller, ColorScheme scheme, TextTheme text) {
    return _styledCard(
      SwitchListTile(
        title: Text('Dark Mode', style: text.titleMedium?.copyWith(color: scheme.onSurface)),
        subtitle: Text('Enable or disable dark theme', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        value: controller.isDarkMode,
        onChanged: (val) => controller.setDarkMode(val),
        activeColor: scheme.primary,
        activeTrackColor: scheme.primary.withOpacity(0.5),
      ),
      scheme,
    );
  }

  Widget _buildPreferenceCard(ColorScheme scheme, TextTheme text) {
    return _styledCard(
      Column(
        children: [
          SwitchListTile(
            title: Text('Auto-upload to gallery', style: text.titleMedium?.copyWith(color: scheme.onSurface)),
            subtitle: Text('Automatically share new images publicly', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            value: _autoUpload,
            onChanged: _setAutoUpload,
            activeColor: scheme.primary,
            activeTrackColor: scheme.primary.withOpacity(0.5),
          ),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: scheme.onSurfaceVariant),
            title: Text('Clear Image Cache', style: text.titleMedium?.copyWith(color: scheme.onSurface)),
            subtitle: Text('Remove all cached images', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            onTap: _clearImageCache,
          ),
        ],
      ),
      scheme,
    );
  }

  Widget _buildInfoCard(ColorScheme scheme, TextTheme text) {
    return _styledCard(
      Column(
        children: [
          ListTile(
            title: Text('App Version', style: text.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600)),
            subtitle: Text(_version.isEmpty ? 'Loading...' : _version, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text('Active Subscription', style: text.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600)),
            subtitle: _isLoadingSubscription
                ? Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)), const SizedBox(width: 8), Text('Loading...', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))])
                : Text(_activeSubscription ?? 'N/A', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
      scheme,
    );
  }

  Widget _buildLinksCard(ColorScheme scheme, TextTheme text) {
    return _styledCard(
      Column(
        children: [
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: scheme.onSurfaceVariant),
            title: Text('Privacy Policy', style: text.titleMedium?.copyWith(color: scheme.onSurface)),
            onTap: () => _launchURL('https://visionspark.app/privacy-policy.html'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
            title: Text('Terms of Service', style: text.titleMedium?.copyWith(color: scheme.onSurface)),
            onTap: () => _launchURL('https://visionspark.app/terms-of-service.html'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.subscriptions_outlined, color: scheme.onSurfaceVariant),
            title: Text('Manage Subscription', style: text.titleMedium?.copyWith(color: scheme.onSurface)),
            onTap: () => _launchURL('https://play.google.com/store/account/subscriptions'),
          ),
        ],
      ),
      scheme,
    );
  }

  @override
  void dispose() {
    _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
    super.dispose();
  }
}