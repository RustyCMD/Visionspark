import 'package:flutter/material.dart';

import '../features/account/account_section.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/image_enhancement/image_enhancement_screen.dart';
import '../features/image_generator/image_generator_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';
import '../features/support/support_screen.dart';
import 'design_system/design_system.dart';

/// One destination per tab. The drawer just navigates between these.
class _Destination {
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
  final bool danger;
  const _Destination({
    required this.title,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.danger = false,
  });
}

class MainScaffold extends StatefulWidget {
  final int selectedIndex;
  const MainScaffold({super.key, required this.selectedIndex});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _index = widget.selectedIndex;

  static final List<_Destination> _destinations = [
    _Destination(
      title: 'Generate',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      builder: (_) => const ImageGeneratorScreen(),
    ),
    _Destination(
      title: 'Enhance',
      icon: Icons.auto_fix_high_outlined,
      selectedIcon: Icons.auto_fix_high,
      builder: (_) => const ImageEnhancementScreen(),
    ),
    _Destination(
      title: 'Gallery',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library,
      builder: (_) => const GalleryScreen(),
    ),
    _Destination(
      title: 'Subscriptions',
      icon: Icons.workspace_premium_outlined,
      selectedIcon: Icons.workspace_premium,
      builder: (_) => const SubscriptionsScreen(),
    ),
    _Destination(
      title: 'Settings',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      builder: (_) => const SettingsScreen(),
    ),
    _Destination(
      title: 'Support',
      icon: Icons.support_agent_outlined,
      selectedIcon: Icons.support_agent,
      builder: (_) => const SupportScreen(),
    ),
    _Destination(
      title: 'Account',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      builder: (_) => const AccountSection(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dest = _destinations[_index];

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(dest.title),
        scrolledUnderElevation: 0,
      ),
      drawer: _AuroraDrawer(
        destinations: _destinations,
        selectedIndex: _index,
        onSelect: (i) {
          setState(() => _index = i);
          Navigator.of(context).pop();
        },
      ),
      body: dest.builder(context),
    );
  }
}

class _AuroraDrawer extends StatelessWidget {
  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _AuroraDrawer({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Drawer(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(VSDesignTokens.radiusXXL),
          bottomRight: Radius.circular(VSDesignTokens.radiusXXL),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand header.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VSDesignTokens.space5,
                VSDesignTokens.space5,
                VSDesignTokens.space5,
                VSDesignTokens.space4,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white),
                  ),
                  const SizedBox(width: VSDesignTokens.space3),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VisionSpark',
                        style: tt.titleLarge?.copyWith(
                          fontWeight: VSTypography.weightBold,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'AI Creativity Suite',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Destinations — first three are creative, then a divider, then admin/account.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: VSDesignTokens.space3),
                children: [
                  for (var i = 0; i < 4; i++)
                    _DrawerTile(
                      destination: destinations[i],
                      selected: selectedIndex == i,
                      onTap: () => onSelect(i),
                    ),
                  const _DrawerGroupDivider(label: 'Account & app'),
                  for (var i = 4; i < destinations.length; i++)
                    _DrawerTile(
                      destination: destinations[i],
                      selected: selectedIndex == i,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(VSDesignTokens.space5),
              child: Text(
                'Made with care',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;
  const _DrawerTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    final bg = selected ? cs.primaryContainer.withValues(alpha: 0.6) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VSDesignTokens.space4,
              vertical: VSDesignTokens.space3,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space4),
                Expanded(
                  child: Text(
                    destination.title,
                    style: tt.titleMedium?.copyWith(
                      color: fg,
                      fontWeight: selected
                          ? VSTypography.weightSemiBold
                          : VSTypography.weightMedium,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerGroupDivider extends StatelessWidget {
  final String label;
  const _DrawerGroupDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(
        top: VSDesignTokens.space4,
        bottom: VSDesignTokens.space2,
        left: VSDesignTokens.space4,
      ),
      child: Text(
        label.toUpperCase(),
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          fontWeight: VSTypography.weightSemiBold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
