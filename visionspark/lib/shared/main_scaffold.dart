import 'package:flutter/material.dart';
import '../features/image_generator/image_generator_screen.dart';
import '../features/account/account_section.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/support/support_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';
import 'widgets/page_container.dart';

class MainScaffold extends StatefulWidget {
  final int selectedIndex;
  const MainScaffold({super.key, required this.selectedIndex});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  final List<String> _titles = [
    'Image',
    'Video',
    'Gallery',
    'Subscriptions',
    'Settings',
    'Support',
    'Account',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex;
  }

  Widget _getSectionWidget(int index) {
    switch (index) {
      case 0:
        return const ImageGeneratorScreen();
      case 1:
        return _wipSection('Video');
      case 2:
        return const GalleryScreen();
      case 3:
        return const SubscriptionsScreen();
      case 4:
        return const SettingsScreen();
      case 5:
        return const SupportScreen();
      case 6:
        return const AccountSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _wipSection(String name) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: PageContainer(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction,
                size: 64, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text('$name Section',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Work in progress...',
                style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // final textTheme = Theme.of(context).textTheme; // Not directly used here, but good to have if needed

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 900;
        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[_selectedIndex]),
            centerTitle: true,
          ),
          drawer: wide ? null : _buildDrawer(colorScheme),
          body: Row(
            children: [
              if (wide) _buildNavigationRail(colorScheme),
              Expanded(child: _getSectionWidget(_selectedIndex)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer(ColorScheme colorScheme) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      backgroundColor: colorScheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(colorScheme),
          const SizedBox(height: 8),
          ..._drawerItems(colorScheme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildNavigationRail(ColorScheme colorScheme) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
      labelType: NavigationRailLabelType.all,
      destinations: [
        const NavigationRailDestination(icon: Icon(Icons.image), label: Text('Image')),
        const NavigationRailDestination(icon: Icon(Icons.videocam), label: Text('Video')),
        const NavigationRailDestination(icon: Icon(Icons.photo_library), label: Text('Gallery')),
        const NavigationRailDestination(icon: Icon(Icons.subscriptions), label: Text('Subs')),
        const NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
        const NavigationRailDestination(icon: Icon(Icons.support_agent), label: Text('Support')),
        const NavigationRailDestination(icon: Icon(Icons.account_circle), label: Text('Account')),
      ],
    );
  }

  Widget _buildDrawerHeader(ColorScheme colorScheme) {
    return DrawerHeader(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.only(topRight: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow?.withOpacity(0.1) ?? colorScheme.onSurface.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Vision Spark', style: TextStyle(color: colorScheme.primary, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('AI Creativity Suite', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.67), fontSize: 16)),
        ],
      ),
    );
  }

  List<Widget> _drawerItems(ColorScheme colorScheme) {
    return [
      _drawerItem(Icons.image, 'Image', 0, colorScheme),
      _drawerItem(Icons.videocam, 'Video', 1, colorScheme),
      _drawerItem(Icons.photo_library, 'Gallery', 2, colorScheme),
      _drawerItem(Icons.subscriptions, 'Subscriptions', 3, colorScheme),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
        child: Divider(color: colorScheme.outlineVariant, thickness: 1, height: 24),
      ),
      _drawerItem(Icons.settings, 'Settings', 4, colorScheme),
      _drawerItem(Icons.support_agent, 'Support', 5, colorScheme),
      _drawerItem(Icons.account_circle, 'Account', 6, colorScheme),
    ];
  }

  Widget _drawerItem(IconData icon, String title, int index, ColorScheme colorScheme) {
    final bool isSelected = _selectedIndex == index;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Material(
        // Use primaryContainer for selected background if available and appropriate, or primary.withOpacity
        color: isSelected ? colorScheme.primary.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: Icon(icon,
              // Selected icon uses primary, unselected uses secondary - good distinction
              color: isSelected ? colorScheme.primary : colorScheme.secondary),
          title: Text(title,
              style: textTheme.titleMedium?.copyWith( // Using a standard textTheme style
                color: colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
          selected: isSelected, // This helps with semantics but visual styling is handled by Material widget
          // selectedTileColor: isSelected ? colorScheme.primary.withOpacity(0.09) : null, // Removed to simplify, Material handles it
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}