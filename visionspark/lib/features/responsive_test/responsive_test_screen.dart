import '../../shared/design_system/design_system.dart';

/// Comprehensive responsive test screen to demonstrate all responsive features
class ResponsiveTestScreen extends StatefulWidget {
  const ResponsiveTestScreen({super.key});

  @override
  State<ResponsiveTestScreen> createState() => _ResponsiveTestScreenState();
}

class _ResponsiveTestScreenState extends State<ResponsiveTestScreen> {
  int _selectedNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: VSResponsive.getResponsivePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildBreakpointInfo(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildResponsiveGrid(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildResponsiveText(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildResponsiveButtons(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildResponsiveCards(context, textTheme, colorScheme),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: VSResponsiveBuilder(
        builder: (context, breakpoint) {
          if (breakpoint == VSBreakpoint.mobile) {
            return VSResponsiveNavigation(
              items: _getNavigationItems(),
              selectedIndex: _selectedNavIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedNavIndex = index;
                });
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      children: [
        Icon(
          Icons.dashboard,
          size: VSResponsive.getIconSize(context, VSDesignTokens.iconXXL),
          color: colorScheme.primary,
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSResponsiveText(
          text: 'Responsive Design Test',
          baseStyle: textTheme.headlineMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightBold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSDesignTokens.space2),
        VSResponsiveText(
          text: 'Testing responsive layouts across different screen sizes',
          baseStyle: textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBreakpointInfo(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    final breakpoint = VSResponsive.getBreakpoint(context);
    final screenSize = MediaQuery.of(context).size;
    final orientation = VSResponsive.isLandscape(context) ? 'Landscape' : 'Portrait';

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      color: colorScheme.primaryContainer.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Breakpoint Info',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space3),
          _buildInfoRow('Breakpoint', breakpoint.name.toUpperCase(), textTheme, colorScheme),
          _buildInfoRow('Screen Size', '${screenSize.width.toInt()} x ${screenSize.height.toInt()}', textTheme, colorScheme),
          _buildInfoRow('Orientation', orientation, textTheme, colorScheme),
          _buildInfoRow('Is Mobile', VSResponsive.isMobile(context).toString(), textTheme, colorScheme),
          _buildInfoRow('Is Tablet', VSResponsive.isTablet(context).toString(), textTheme, colorScheme),
          _buildInfoRow('Is Desktop', VSResponsive.isDesktop(context).toString(), textTheme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, TextTheme textTheme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSDesignTokens.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveGrid(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Grid',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSResponsiveBuilder(
          builder: (context, breakpoint) {
            final columns = VSResponsive.getGridColumns(context);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: VSDesignTokens.space3,
                crossAxisSpacing: VSDesignTokens.space3,
                childAspectRatio: 1.5,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                return VSCard(
                  padding: const EdgeInsets.all(VSDesignTokens.space3),
                  color: colorScheme.surfaceContainer,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.grid_view,
                          color: colorScheme.primary,
                          size: VSDesignTokens.iconM,
                        ),
                        const SizedBox(height: VSDesignTokens.space2),
                        Text(
                          'Item ${index + 1}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildResponsiveText(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Typography',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VSResponsiveText(
                text: 'Headline Text',
                baseStyle: textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightBold,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space2),
              VSResponsiveText(
                text: 'This is body text that scales responsively based on the screen size. On mobile devices, it will be smaller, while on desktop it will be larger for better readability.',
                baseStyle: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space2),
              VSResponsiveText(
                text: 'Caption text for additional information',
                baseStyle: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveButtons(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Buttons',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSResponsiveBuilder(
          builder: (context, breakpoint) {
            if (breakpoint == VSBreakpoint.mobile) {
              return Column(
                children: [
                  VSButton(
                    text: 'Primary Button',
                    onPressed: () => _showResponsiveDialog(context),
                    variant: VSButtonVariant.primary,
                    isFullWidth: true,
                  ),
                  const SizedBox(height: VSDesignTokens.space3),
                  VSButton(
                    text: 'Secondary Button',
                    onPressed: () {},
                    variant: VSButtonVariant.outline,
                    isFullWidth: true,
                  ),
                ],
              );
            } else {
              return Row(
                children: [
                  Expanded(
                    child: VSButton(
                      text: 'Primary Button',
                      onPressed: () => _showResponsiveDialog(context),
                      variant: VSButtonVariant.primary,
                    ),
                  ),
                  const SizedBox(width: VSDesignTokens.space3),
                  Expanded(
                    child: VSButton(
                      text: 'Secondary Button',
                      onPressed: () {},
                      variant: VSButtonVariant.outline,
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildResponsiveCards(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Cards',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSResponsiveBuilder(
          builder: (context, breakpoint) {
            final cards = [
              _buildFeatureCard('Responsive Layout', 'Adapts to screen size', Icons.dashboard, colorScheme, textTheme),
              _buildFeatureCard('Flexible Grid', 'Dynamic column count', Icons.grid_view, colorScheme, textTheme),
              _buildFeatureCard('Adaptive Text', 'Scales with device', Icons.text_fields, colorScheme, textTheme),
            ];

            if (breakpoint == VSBreakpoint.mobile) {
              return Column(children: cards);
            } else {
              return Row(
                children: cards.map((card) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: VSDesignTokens.space3),
                    child: card,
                  ),
                )).toList(),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildFeatureCard(String title, String description, IconData icon, ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSDesignTokens.space3),
      child: VSCard(
        padding: const EdgeInsets.all(VSDesignTokens.space4),
        color: colorScheme.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: colorScheme.primary,
              size: VSDesignTokens.iconL,
            ),
            const SizedBox(height: VSDesignTokens.space3),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: VSTypography.weightSemiBold,
              ),
            ),
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              description,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResponsiveDialog(BuildContext context) {
    VSResponsiveDialog.show(
      context: context,
      title: 'Responsive Dialog',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 48),
          const SizedBox(height: VSDesignTokens.space4),
          const Text('This dialog adapts to screen size. On mobile, it shows as a full-screen dialog, while on larger screens it appears as a traditional dialog.'),
          const SizedBox(height: VSDesignTokens.space4),
          VSButton(
            text: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            variant: VSButtonVariant.primary,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  List<VSNavigationItem> _getNavigationItems() {
    return [
      const VSNavigationItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: 'Home',
      ),
      VSNavigationItem(
        icon: Icon(Icons.dashboard),
        activeIcon: Icon(Icons.dashboard),
        label: 'Responsive',
      ),
      const VSNavigationItem(
        icon: Icon(Icons.settings_outlined),
        activeIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];
  }
}
