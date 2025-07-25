import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../main.dart'; // Assuming ThemeController is in main.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/utils/snackbar_utils.dart';
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
          VSSnackbar.showError(context, 'Could not launch $urlString');
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        VSSnackbar.showError(context, 'Error launching URL: An unexpected error occurred.');
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
        if (mounted) {
          VSSnackbar.showSuccess(context, 'Image cache cleared successfully!');
        }
      } catch (e) {
        debugPrint("Error clearing cache: $e");
        if (mounted) {
          VSSnackbar.showError(context, 'Error clearing cache: An unexpected error occurred.');
        }
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
      body: VSResponsiveLayout(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: VSResponsive.getResponsivePadding(context),
            child: Column(
              children: [
                _buildAppearanceSection(context, themeController, colorScheme, textTheme),
                const VSResponsiveSpacing(),
                _buildDataSection(context, colorScheme, textTheme),
                const VSResponsiveSpacing(),
                _buildSubscriptionSection(context, colorScheme, textTheme),
                const VSResponsiveSpacing(),
                _buildAboutSection(context, colorScheme, textTheme),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context, ThemeController themeController, ColorScheme colorScheme, TextTheme textTheme) {
    return VSCard(
      elevation: VSDesignTokens.elevation2,
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      margin: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      padding: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space3),
                VSResponsiveText(
                  text: 'Appearance',
                  baseStyle: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(
              'Dark Mode',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
            subtitle: Text(
              'Enable or disable dark theme',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: themeController.isDarkMode,
            onChanged: (value) => themeController.setDarkMode(value),
            activeColor: colorScheme.primary,
            activeTrackColor: colorScheme.primary.withValues(alpha: 0.5),
            inactiveThumbColor: colorScheme.outline,
            inactiveTrackColor: colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return VSCard(
      elevation: VSDesignTokens.elevation2,
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      margin: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      padding: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Row(
              children: [
                Icon(
                  Icons.storage_outlined,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space3),
                VSResponsiveText(
                  text: 'Data & Storage',
                  baseStyle: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(
              'Auto-upload generated images to gallery',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
            subtitle: Text(
              'Automatically share new images to the public gallery',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: _autoUpload,
            onChanged: _setAutoUpload,
            activeColor: colorScheme.primary,
            activeTrackColor: colorScheme.primary.withValues(alpha: 0.5),
            inactiveThumbColor: colorScheme.outline,
            inactiveTrackColor: colorScheme.surfaceContainerHighest,
          ),
          ListTile(
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconM,
            ),
            title: Text(
              'Clear Image Cache',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
            subtitle: Text(
              'Remove cached images from gallery and network',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: _clearImageCache,
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionSection(BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return VSCard(
      elevation: VSDesignTokens.elevation2,
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      margin: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      padding: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Row(
              children: [
                Icon(
                  Icons.card_membership_outlined,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space3),
                VSResponsiveText(
                  text: 'Subscription',
                  baseStyle: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(
              'Active Subscription',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightSemiBold,
              ),
            ),
            subtitle: _isLoadingSubscription
                ? Row(
                    children: [
                      SizedBox(
                        width: VSDesignTokens.iconS,
                        height: VSDesignTokens.iconS,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: VSDesignTokens.space2),
                      Text(
                        'Loading...',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _activeSubscription ?? 'N/A',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  Widget _buildAboutSection(BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return VSCard(
      elevation: VSDesignTokens.elevation2,
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      margin: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      padding: const EdgeInsets.symmetric(vertical: VSDesignTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space3),
                VSResponsiveText(
                  text: 'About & Legal',
                  baseStyle: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(
              'App Version',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightSemiBold,
              ),
            ),
            subtitle: Text(
              _version.isEmpty ? 'Loading...' : _version,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(indent: VSDesignTokens.space4, endIndent: VSDesignTokens.space4),
          ListTile(
            leading: Icon(
              Icons.privacy_tip_outlined,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconM,
            ),
            title: Text(
              'Privacy Policy',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
            onTap: () => _launchURL('https://visionspark.app/privacy-policy.html'),
            trailing: Icon(
              Icons.open_in_new,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconS,
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.description_outlined,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconM,
            ),
            title: Text(
              'Terms of Service',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
            onTap: () => _launchURL('https://visionspark.app/terms-of-service.html'),
            trailing: Icon(
              Icons.open_in_new,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconS,
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.subscriptions_outlined,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconM,
            ),
            title: Text(
              'Manage Subscription',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
            onTap: () => _launchURL('https://play.google.com/store/account/subscriptions'),
            trailing: Icon(
              Icons.open_in_new,
              color: colorScheme.onSurfaceVariant,
              size: VSDesignTokens.iconS,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
    super.dispose();
  }
}