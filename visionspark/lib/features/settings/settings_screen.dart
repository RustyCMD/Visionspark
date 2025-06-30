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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.02),
                _buildModernSettingsHeader(colorScheme, textTheme),
                SizedBox(height: size.height * 0.04),
                _buildPreferencesCard(themeController, colorScheme, textTheme),
                const SizedBox(height: 24),
                _buildAccountCard(colorScheme, textTheme),
                const SizedBox(height: 24),
                _buildDataCard(colorScheme, textTheme),
                const SizedBox(height: 24),
                _buildLegalCard(colorScheme, textTheme),
                SizedBox(height: size.height * 0.03),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernSettingsHeader(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.settings_rounded,
              color: colorScheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customize your VisionSpark experience',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard(ThemeController themeController, ColorScheme colorScheme, TextTheme textTheme) {
    return _buildModernSettingsCard(
      colorScheme: colorScheme,
      textTheme: textTheme,
      title: 'Preferences',
      icon: Icons.tune_rounded,
      children: [
        _buildModernSwitchTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Dark Mode',
          subtitle: 'Enable dark theme for better viewing in low light',
          icon: Icons.dark_mode_rounded,
          value: themeController.isDarkMode,
          onChanged: (value) => themeController.setDarkMode(value),
        ),
        _buildDivider(colorScheme),
        _buildModernSwitchTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Auto-upload to Gallery',
          subtitle: 'Automatically share new images to the public gallery',
          icon: Icons.cloud_upload_rounded,
          value: _autoUpload,
          onChanged: _setAutoUpload,
        ),
      ],
    );
  }

  Widget _buildAccountCard(ColorScheme colorScheme, TextTheme textTheme) {
    return _buildModernSettingsCard(
      colorScheme: colorScheme,
      textTheme: textTheme,
      title: 'Account',
      icon: Icons.account_circle_rounded,
      children: [
        _buildModernInfoTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'App Version',
          subtitle: _version.isEmpty ? 'Loading...' : _version,
          icon: Icons.info_rounded,
        ),
        _buildDivider(colorScheme),
        _buildModernInfoTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Active Subscription',
          subtitle: _isLoadingSubscription ? 'Loading...' : _activeSubscription ?? 'N/A',
          icon: Icons.star_rounded,
          isLoading: _isLoadingSubscription,
        ),
        _buildDivider(colorScheme),
        _buildModernActionTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Manage Subscription',
          subtitle: 'View and manage your subscription on Google Play',
          icon: Icons.subscriptions_rounded,
          onTap: () => _launchURL('https://play.google.com/store/account/subscriptions'),
        ),
      ],
    );
  }

  Widget _buildDataCard(ColorScheme colorScheme, TextTheme textTheme) {
    return _buildModernSettingsCard(
      colorScheme: colorScheme,
      textTheme: textTheme,
      title: 'Data & Storage',
      icon: Icons.storage_rounded,
      children: [
        _buildModernActionTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Clear Image Cache',
          subtitle: 'Remove cached images to free up space',
          icon: Icons.clear_all_rounded,
          onTap: _clearImageCache,
        ),
      ],
    );
  }

  Widget _buildLegalCard(ColorScheme colorScheme, TextTheme textTheme) {
    return _buildModernSettingsCard(
      colorScheme: colorScheme,
      textTheme: textTheme,
      title: 'Legal',
      icon: Icons.gavel_rounded,
      children: [
        _buildModernActionTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Privacy Policy',
          subtitle: 'Learn how we protect your privacy',
          icon: Icons.privacy_tip_rounded,
          onTap: () => _launchURL('https://visionspark.app/privacy-policy.html'),
        ),
        _buildDivider(colorScheme),
        _buildModernActionTile(
          colorScheme: colorScheme,
          textTheme: textTheme,
          title: 'Terms of Service',
          subtitle: 'Read our terms and conditions',
          icon: Icons.description_rounded,
          onTap: () => _launchURL('https://visionspark.app/terms-of-service.html'),
        ),
      ],
    );
  }

  Widget _buildModernSettingsCard({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildModernSwitchTile({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: colorScheme.onSurface,
              size: 24,
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
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: colorScheme.primary,
              activeTrackColor: colorScheme.primary.withOpacity(0.3),
              inactiveThumbColor: colorScheme.outline,
              inactiveTrackColor: colorScheme.surfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernInfoTile({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required String title,
    required String subtitle,
    required IconData icon,
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: colorScheme.onSurface,
              size: 24,
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
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (isLoading)
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Loading...',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    subtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernActionTile({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onSurface,
                  size: 24,
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
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: colorScheme.outline.withOpacity(0.1),
    );
  }

  @override
  void dispose() {
    _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
    super.dispose();
  }
}