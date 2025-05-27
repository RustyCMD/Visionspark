import 'package:flutter/material.dart';
import '../features/image_generator/image_generator_screen.dart'; // Will be created
import '../features/account/account_section.dart'; // Will be created
import '../features/gallery/gallery_screen.dart'; // Import GalleryScreen
import '../features/support/support_screen.dart'; // Import the new SupportScreen
import '../features/settings/settings_screen.dart'; // Import the real SettingsScreen

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
        return const GalleryScreen(); // New GalleryScreen
      case 3:
        return const SettingsScreen(); // Use the real SettingsScreen
      case 4:
        return const SupportScreen(); // Show the real SupportScreen
      case 5:
        return const AccountSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _wipSection(String name) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('$name Section',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Work in progress...',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lilacPurple = colorScheme.primary;
    final softTeal = colorScheme.secondary;
    final mutedPeach = colorScheme.error.withOpacity(0.12); // Use error as accent, adjust as needed
    final lightGrey = colorScheme.surface;
    final darkText = colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        centerTitle: true,
      ),
      drawer: Drawer(
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
            DrawerHeader(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Vision Spark',
                      style: TextStyle(
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
            _drawerItem(Icons.videocam, 'Video', 1, colorScheme),
            _drawerItem(Icons.photo_library, 'Gallery', 2, colorScheme),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
              child: Divider(color: colorScheme.error.withOpacity(0.12), thickness: 2, height: 24),
            ),
            _drawerItem(Icons.settings, 'Settings', 3, colorScheme),
            _drawerItem(Icons.support_agent, 'Support', 4, colorScheme),
            _drawerItem(Icons.account_circle, 'Account', 5, colorScheme),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: _getSectionWidget(_selectedIndex),
    );
  }

  Widget _drawerItem(IconData icon, String title, int index, ColorScheme colorScheme) {
    final bool isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Material(
        color: isSelected ? colorScheme.primary.withOpacity(0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: Icon(icon,
              color: isSelected ? colorScheme.primary : colorScheme.secondary),
          title: Text(title,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
          selected: isSelected,
          selectedTileColor: colorScheme.primary.withOpacity(0.09),
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