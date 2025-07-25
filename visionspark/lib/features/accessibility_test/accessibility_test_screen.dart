import '../../shared/design_system/design_system.dart' hide VSAccessibility;
import '../../shared/accessibility/accessibility_utils.dart';

/// Comprehensive accessibility test screen to demonstrate and test accessibility features
class AccessibilityTestScreen extends StatefulWidget {
  const AccessibilityTestScreen({super.key});

  @override
  State<AccessibilityTestScreen> createState() => _AccessibilityTestScreenState();
}

class _AccessibilityTestScreenState extends State<AccessibilityTestScreen> {
  bool _switchValue = false;
  double _sliderValue = 50.0;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
                _buildAccessibilityInfo(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildInteractiveElements(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildColorContrastTests(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildFocusManagement(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildSemanticElements(context, textTheme, colorScheme),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return VSAccessibility.createAccessibleImage(
      semanticLabel: 'Accessibility test screen header with accessibility icon',
      child: Column(
        children: [
          Icon(
            Icons.accessibility_new,
            size: VSDesignTokens.iconXXL,
            color: colorScheme.primary,
          ),
          const SizedBox(height: VSDesignTokens.space4),
          VSResponsiveText(
            text: 'Accessibility Test',
            baseStyle: textTheme.headlineMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightBold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VSDesignTokens.space2),
          VSResponsiveText(
            text: 'Testing accessibility features and compliance',
            baseStyle: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityInfo(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    final report = VSAccessibilityTesting.generateAccessibilityReport(context);

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      color: colorScheme.primaryContainer.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Accessibility Settings',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space3),
          _buildInfoRow('Screen Reader', report['screenReader'] ? 'Enabled' : 'Disabled', textTheme, colorScheme),
          _buildInfoRow('High Contrast', report['highContrast'] ? 'Enabled' : 'Disabled', textTheme, colorScheme),
          _buildInfoRow('Reduced Motion', report['reducedMotion'] ? 'Enabled' : 'Disabled', textTheme, colorScheme),
          _buildInfoRow('Text Scale Factor', '${report['textScaleFactor'].toStringAsFixed(1)}x', textTheme, colorScheme),
          _buildInfoRow('Large Text', report['isLargeText'] ? 'Yes' : 'No', textTheme, colorScheme),
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

  Widget _buildInteractiveElements(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interactive Elements',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        
        // Accessible Buttons
        VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buttons',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
              Wrap(
                spacing: VSDesignTokens.space3,
                runSpacing: VSDesignTokens.space2,
                children: [
                  VSButton(
                    text: 'Primary Button',
                    onPressed: () => VSAccessibility.announceAction(context, 'Primary button pressed'),
                    variant: VSButtonVariant.primary,
                  ),
                  VSButton(
                    text: 'Secondary Button',
                    onPressed: () => VSAccessibility.announceAction(context, 'Secondary button pressed'),
                    variant: VSButtonVariant.outline,
                  ),
                  VSButton(
                    text: 'Disabled Button',
                    onPressed: null,
                    variant: VSButtonVariant.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: VSDesignTokens.space4),
        
        // Accessible Switch
        VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Switch Control',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
              VSAccessibility.createAccessibleSwitch(
                value: _switchValue,
                semanticLabel: 'Test switch, ${_switchValue ? 'enabled' : 'disabled'}',
                child: SwitchListTile(
                  title: Text('Test Switch'),
                  value: _switchValue,
                  onChanged: (value) {
                    setState(() {
                      _switchValue = value;
                    });
                    VSAccessibility.announceStateChange(
                      context,
                      'Switch ${value ? 'enabled' : 'disabled'}',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: VSDesignTokens.space4),
        
        // Accessible Slider
        VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Slider Control',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
              VSAccessibility.createAccessibleSlider(
                value: _sliderValue,
                min: 0.0,
                max: 100.0,
                semanticLabel: 'Test slider, current value ${_sliderValue.round()}',
                child: Slider(
                  value: _sliderValue,
                  min: 0.0,
                  max: 100.0,
                  divisions: 100,
                  label: _sliderValue.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      _sliderValue = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorContrastTests(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    final testCombinations = [
      {'fg': colorScheme.onSurface, 'bg': colorScheme.surface, 'name': 'Primary Text'},
      {'fg': colorScheme.onSurfaceVariant, 'bg': colorScheme.surface, 'name': 'Secondary Text'},
      {'fg': colorScheme.onPrimary, 'bg': colorScheme.primary, 'name': 'Primary Button'},
      {'fg': colorScheme.onError, 'bg': colorScheme.error, 'name': 'Error Text'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color Contrast Tests',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        ...testCombinations.map((combo) {
          final test = VSAccessibilityTesting.testColorContrast(
            combo['fg'] as Color,
            combo['bg'] as Color,
          );

          return Padding(
            padding: const EdgeInsets.only(bottom: VSDesignTokens.space3),
            child: VSCard(
              padding: const EdgeInsets.all(VSDesignTokens.space4),
              color: combo['bg'] as Color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    combo['name'] as String,
                    style: textTheme.titleMedium?.copyWith(
                      color: combo['fg'] as Color,
                      fontWeight: VSTypography.weightMedium,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    'Contrast Ratio: ${test['ratio'].toStringAsFixed(2)}:1',
                    style: textTheme.bodySmall?.copyWith(
                      color: combo['fg'] as Color,
                    ),
                  ),
                  Text(
                    'WCAG AA: ${test['passesAA'] ? '✓ Pass' : '✗ Fail'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: combo['fg'] as Color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFocusManagement(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Focus Management',
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
              VSAccessibility.createAccessibleTextField(
                semanticLabel: 'Test text field for focus management',
                hint: 'Enter text to test focus',
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Test Text Field',
                    hintText: 'Enter text here',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
              Wrap(
                spacing: VSDesignTokens.space2,
                children: [
                  VSButton(
                    text: 'Focus Field',
                    onPressed: () => VSAccessibility.requestFocus(context, _focusNode),
                    variant: VSButtonVariant.outline,
                    size: VSButtonSize.small,
                  ),
                  VSButton(
                    text: 'Clear Focus',
                    onPressed: () => VSAccessibility.clearFocus(context),
                    variant: VSButtonVariant.outline,
                    size: VSButtonSize.small,
                  ),
                  VSButton(
                    text: 'Next Focus',
                    onPressed: () => VSAccessibility.focusNext(context),
                    variant: VSButtonVariant.outline,
                    size: VSButtonSize.small,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSemanticElements(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Semantic Elements',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        
        // Accessible List
        VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accessible List',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
              ...List.generate(3, (index) {
                return VSAccessibility.createAccessibleListItem(
                  semanticLabel: 'List item ${index + 1} of 3',
                  onTap: () => VSAccessibility.announceAction(context, 'Selected item ${index + 1}'),
                  child: ListTile(
                    leading: Icon(Icons.star),
                    title: Text('Item ${index + 1}'),
                    subtitle: Text('Description for item ${index + 1}'),
                    onTap: () => VSAccessibility.announceAction(context, 'Selected item ${index + 1}'),
                  ),
                );
              }),
            ],
          ),
        ),
        
        const SizedBox(height: VSDesignTokens.space4),
        
        // Accessible Progress
        VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Progress Indicator',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
              VSAccessibility.createAccessibleProgress(
                semanticLabel: 'Loading progress, ${(_sliderValue).round()}% complete',
                value: _sliderValue / 100,
                child: LinearProgressIndicator(
                  value: _sliderValue / 100,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
