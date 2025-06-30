import 'package:flutter/material.dart';
import '../features/image_generator/image_generator_screen.dart'; // Will be created
import '../features/account/account_section.dart'; // Will be created
import '../features/gallery/gallery_screen.dart'; // Import GalleryScreen
import '../features/support/support_screen.dart'; // Import the new SupportScreen
import '../features/settings/settings_screen.dart'; // Import the real SettingsScreen
import '../features/subscriptions/subscriptions_screen.dart'; // Import the new SubscriptionsScreen
import 'dart:ui';

class MainScaffold extends StatefulWidget {
  final int selectedIndex;
  const MainScaffold({super.key, required this.selectedIndex});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _drawerController;
  late Animation<double> _drawerAnimation;

  final List<String> _titles = [
    'Create',
    'Video',
    'Gallery',
    'Subscriptions',
    'Settings',
    'Support',
    'Account',
  ];

  final List<IconData> _icons = [
    Icons.auto_awesome,
    Icons.videocam_rounded,
    Icons.photo_library_rounded,
    Icons.workspace_premium_rounded,
    Icons.settings_rounded,
    Icons.support_agent_rounded,
    Icons.account_circle_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex;
    _drawerController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _drawerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _drawerController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
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
    final size = MediaQuery.of(context).size;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface,
            colorScheme.primary.withOpacity(0.02),
          ],
        ),
      ),
      child: Center(
        child: Container(
          margin: EdgeInsets.all(size.width * 0.1),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withOpacity(0.6),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.construction_rounded,
                  size: 64,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '$name Studio',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Coming soon with revolutionary AI technology',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface.withOpacity(0.8),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.menu_rounded,
                color: colorScheme.primary,
              ),
            ),
            onPressed: () {
              Scaffold.of(context).openDrawer();
              _drawerController.forward();
            },
          ),
        ),
      ),
      drawer: _buildModernDrawer(colorScheme, size),
      body: _getSectionWidget(_selectedIndex),
    );
  }

  Widget _buildModernDrawer(ColorScheme colorScheme, Size size) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.surface.withOpacity(0.9),
                  colorScheme.surfaceContainer.withOpacity(0.8),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: AnimatedBuilder(
              animation: _drawerAnimation,
              builder: (context, child) {
                return Column(
                  children: [
                    _buildDrawerHeader(colorScheme, size),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          const SizedBox(height: 16),
                          ..._buildMainNavigationItems(colorScheme),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    colorScheme.outline.withOpacity(0.3),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          ..._buildSecondaryNavigationItems(colorScheme),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(ColorScheme colorScheme, Size size) {
    final textTheme = Theme.of(context).textTheme;
    
    return Container(
      height: size.height * 0.25,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withOpacity(0.1),
            colorScheme.secondary.withOpacity(0.05),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.secondary,
              ],
            ).createShader(bounds),
            child: Text(
              'VisionSpark',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI Creativity Suite',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMainNavigationItems(ColorScheme colorScheme) {
    return [0, 1, 2, 3].map((index) => _buildDrawerItem(
      _icons[index],
      _titles[index],
      index,
      colorScheme,
      isMainItem: true,
    )).toList();
  }

  List<Widget> _buildSecondaryNavigationItems(ColorScheme colorScheme) {
    return [4, 5, 6].map((index) => _buildDrawerItem(
      _icons[index],
      _titles[index],
      index,
      colorScheme,
      isMainItem: false,
    )).toList();
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,
    int index,
    ColorScheme colorScheme, {
    bool isMainItem = false,
  }) {
    final bool isSelected = _selectedIndex == index;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
            Navigator.of(context).pop();
            _drawerController.reset();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        colorScheme.primary.withOpacity(0.15),
                        colorScheme.primary.withOpacity(0.05),
                      ],
                    )
                  : null,
              border: isSelected
                  ? Border.all(
                      color: colorScheme.primary.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface.withOpacity(0.7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.8),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
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