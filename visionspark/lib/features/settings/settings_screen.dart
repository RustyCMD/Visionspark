import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import '../../shared/services/retry_service.dart';
import '../../shared/utils/snackbar_utils.dart';
import '../../shared/widgets/standardized_loading_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with StandardizedRetryMixin {
  String _version = '';
  bool _autoUpload = false;
  String? _activeSubscription;
  bool _loadingSub = true;
  SubscriptionStatusNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadAutoUpload();
    _fetchSubscription();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = Provider.of<SubscriptionStatusNotifier>(context, listen: false);
    if (_notifier != n) {
      _notifier?.removeListener(_fetchSubscription);
      _notifier = n;
      _notifier?.addListener(_fetchSubscription);
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_fetchSubscription);
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _loadAutoUpload() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _autoUpload = p.getBool('auto_upload_to_gallery') ?? false);
  }

  Future<void> _setAutoUpload(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('auto_upload_to_gallery', v);
    if (mounted) {
      setState(() => _autoUpload = v);
      VSSnackbar.showInfo(context, 'Auto-upload ${v ? 'on' : 'off'}.');
    }
  }

  Future<void> _fetchSubscription() async {
    if (!mounted) return;
    setState(() => _loadingSub = true);
    final result = await executeWithRetry<Map<String, dynamic>>(
      operation: () async {
        final resp = await Supabase.instance.client.functions
            .invoke('get-generation-status');
        if (resp.data == null) throw Exception('No data');
        final data = resp.data as Map<String, dynamic>;
        if (data['error'] != null) throw Exception(data['error']);
        return data;
      },
      operationType: RetryOperationType.subscriptionStatus,
      operationName: 'Settings subscription status',
    );
    if (!mounted) return;
    setState(() => _loadingSub = false);
    if (result.success && result.data != null) {
      final type = result.data!['active_subscription_type'];
      final limit = result.data!['generation_limit'] ?? result.data!['limit'];
      String label = 'No active subscription';
      if (type == 'monthly_unlimited_generations' || type == 'monthly_unlimited') {
        label = 'Monthly unlimited';
        if (limit != null) label += ' • limit ${limit == -1 ? "∞" : limit}';
      } else if (type != null) {
        label = type
            .toString()
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ');
        if (limit != null) label += ' • limit ${limit == -1 ? "∞" : limit}';
      }
      setState(() => _activeSubscription = label);
    } else {
      setState(() => _activeSubscription =
          'Could not load subscription: ${result.error ?? "unknown error"}');
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) VSSnackbar.showError(context, 'Could not open $url');
    } catch (_) {
      if (mounted) VSSnackbar.showError(context, 'Could not open $url');
    }
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'This removes locally cached images. They\'ll re-download as needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DefaultCacheManager().emptyCache();
      if (mounted) VSSnackbar.showSuccess(context, 'Cache cleared.');
    } catch (_) {
      if (mounted) VSSnackbar.showError(context, 'Could not clear cache.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: ListView(
            padding: VSResponsive.getResponsivePadding(context),
            children: [
              _appearance(theme),
              const SizedBox(height: VSDesignTokens.space5),
              _data(),
              const SizedBox(height: VSDesignTokens.space5),
              _subscription(),
              const SizedBox(height: VSDesignTokens.space5),
              _about(),
              const SizedBox(height: VSDesignTokens.space12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return VSCard(
      padding: EdgeInsets.zero,
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(VSDesignTokens.space5),
              child: VSSectionHeader(
                icon: icon,
                title: title,
                subtitle: subtitle,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _appearance(ThemeController theme) {
    final cs = Theme.of(context).colorScheme;
    return _section(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      subtitle: 'Tune how VisionSpark looks.',
      children: [
        SwitchListTile(
          title: const Text('Dark mode'),
          subtitle: Text(
            theme.isDarkMode ? 'Enabled' : 'Disabled',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          value: theme.isDarkMode,
          onChanged: theme.setDarkMode,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space2),
      ],
    );
  }

  Widget _data() {
    return _section(
      icon: Icons.storage_outlined,
      title: 'Data & storage',
      subtitle: 'Auto-upload and local cache.',
      children: [
        SwitchListTile(
          title: const Text('Auto-upload to gallery'),
          subtitle: const Text(
            'Share generated/enhanced images automatically.',
          ),
          value: _autoUpload,
          onChanged: _setAutoUpload,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Clear image cache'),
          subtitle: const Text('Frees up local storage.'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _clearCache,
        ),
        const SizedBox(height: VSDesignTokens.space2),
      ],
    );
  }

  Widget _subscription() {
    final cs = Theme.of(context).colorScheme;
    return _section(
      icon: Icons.card_membership_outlined,
      title: 'Subscription',
      subtitle: 'Your current plan.',
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
          title: const Text('Active subscription'),
          subtitle: _loadingSub
              ? Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                    ),
                    const SizedBox(width: VSDesignTokens.space2),
                    const Text('Loading…'),
                  ],
                )
              : Text(_activeSubscription ?? 'N/A'),
        ),
        const SizedBox(height: VSDesignTokens.space2),
      ],
    );
  }

  Widget _about() {
    return _section(
      icon: Icons.info_outline_rounded,
      title: 'About & legal',
      subtitle: 'Version, policies, manage subscription.',
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
          title: const Text('App version'),
          subtitle: Text(_version.isEmpty ? 'Loading…' : _version),
        ),
        const Divider(indent: VSDesignTokens.space5, endIndent: VSDesignTokens.space5, height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => _launch('https://visionspark.app/privacy-policy.html'),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
          leading: const Icon(Icons.description_outlined),
          title: const Text('Terms of service'),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => _launch('https://visionspark.app/terms-of-service.html'),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space5,
          ),
          leading: const Icon(Icons.subscriptions_outlined),
          title: const Text('Manage subscription'),
          subtitle: const Text('Opens Google Play.'),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => _launch('https://play.google.com/store/account/subscriptions'),
        ),
        const SizedBox(height: VSDesignTokens.space2),
      ],
    );
  }
}
