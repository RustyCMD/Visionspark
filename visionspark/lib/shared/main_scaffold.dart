import 'package:flutter/material.dart';
import '../features/image_generator/image_generator_screen.dart'; // Will be created
import '../features/account/account_section.dart'; // Will be created
import '../features/gallery/gallery_screen.dart'; // Import GalleryScreen
import '../features/support/support_screen.dart'; // Import the new SupportScreen
import '../features/settings/settings_screen.dart'; // Import the real SettingsScreen
import '../features/subscriptions/subscriptions_screen.dart'; // Import the new SubscriptionsScreen
import '../features/image_enhancement/image_enhancement_screen.dart'; // Import the new Image Enhancement Screen

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
    'Image Enhancement',
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
        return const ImageEnhancementScreen();
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // final textTheme = Theme.of(context).textTheme; // Not directly used here, but good to have if needed

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        centerTitle: true,
        // AppBar uses theme colors by default (colorScheme.primary for background, colorScheme.onPrimary for text)
      ),
      drawer: Drawer(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
        ),
        backgroundColor: colorScheme.surface, // Correct: uses theme surface color
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: colorScheme.surface, // Correct
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow?.withOpacity(0.1) ?? colorScheme.onSurface.withOpacity(0.05), // Themed shadow
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Vision Spark',
                      style: TextStyle( // Explicit styling is fine here for branding
                          color: colorScheme.primary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('AI Creativity Suite',
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.67),
                          fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _drawerItem(Icons.image, 'Image', 0, colorScheme),
            _drawerItem(Icons.auto_fix_high, 'Image Enhancement', 1, colorScheme),
            _drawerItem(Icons.photo_library, 'Gallery', 2, colorScheme),
            _drawerItem(Icons.subscriptions, 'Subscriptions', 3, colorScheme),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
              // Use outlineVariant for a more subtle, Material 3 aligned divider
              child: Divider(color: colorScheme.outlineVariant, thickness: 1, height: 24),
            ),
            _drawerItem(Icons.settings, 'Settings', 4, colorScheme),
            _drawerItem(Icons.support_agent, 'Support', 5, colorScheme),
            _drawerItem(Icons.account_circle, 'Account', 6, colorScheme),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: _getSectionWidget(_selectedIndex),
    );
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