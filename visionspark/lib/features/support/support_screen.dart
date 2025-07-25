import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/utils/snackbar_utils.dart';
import '../../shared/design_system/design_system.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitSupport() async {
    // Validate form before proceeding
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();
      final userEmail = Supabase.instance.client.auth.currentUser?.email;

      if (userEmail == null) {
        if (mounted) {
          showErrorSnackbar(context, 'Could not submit report: User email not found. Please ensure you are logged in.');
        }
        return;
      }
      
      await Supabase.instance.client.functions.invoke(
        'report-support-issue',
        body: {
          'title': title,
          'content': content,
          'email': userEmail,
        },
      );

      if (mounted) {
        showSuccessSnackbar(context, 'Your report has been submitted successfully.');
        _titleController.clear();
        _contentController.clear();
        FocusScope.of(context).unfocus(); // Hide keyboard on success
      }
    } catch (e) {
      if (mounted) {
        // Corrected line: Use e.toString() to avoid the undefined 'FunctionsException' type.
        // This is consistent with error handling in other parts of the app.
        showErrorSnackbar(context, 'Failed to submit: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: VSResponsive.getResponsivePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
                _buildContactForm(context),
                const VSResponsiveSpacing(),
                _buildDisclaimer(context),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactForm(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.contact_support,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space3),
                VSResponsiveText(
                  text: 'Contact Support',
                  baseStyle: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VSDesignTokens.space6),
            VSAccessibleTextField(
              controller: _titleController,
              labelText: 'Subject',
              hintText: 'Brief description of your issue',
              semanticLabel: 'Support request subject',
              prefixIcon: const Icon(Icons.title_rounded),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a subject.';
                }
                return null;
              },
            ),
            const SizedBox(height: VSDesignTokens.space5),
            VSAccessibleTextField(
              controller: _contentController,
              labelText: 'Message',
              hintText: 'Describe your issue or feedback in detail...',
              semanticLabel: 'Support request message',
              prefixIcon: const Icon(Icons.article_outlined),
              maxLines: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please provide a message.';
                }
                if (value.trim().length < 10) {
                  return 'Please provide at least 10 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: VSDesignTokens.space6),
            VSButton(
              text: 'Submit Request',
              icon: _isLoading ? null : const Icon(Icons.send_rounded),
              onPressed: _isLoading ? null : _submitSupport,
              isLoading: _isLoading,
              isFullWidth: true,
              size: VSButtonSize.large,
              variant: VSButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(
          Icons.support_agent_outlined,
          size: VSDesignTokens.iconXXL,
          color: colorScheme.primary,
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSResponsiveText(
          text: 'Support & Feedback',
          baseStyle: textTheme.headlineMedium?.copyWith(
            fontWeight: VSTypography.weightBold,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSDesignTokens.space2),
        VSResponsiveText(
          text: 'Get help with VisionSpark or share your feedback with our team',
          baseStyle: textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
      borderRadius: VSDesignTokens.radiusM,
      border: Border.all(
        color: colorScheme.outline.withValues(alpha: 0.2),
        width: 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: colorScheme.primary,
            size: VSDesignTokens.iconM,
          ),
          const SizedBox(width: VSDesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Disclaimer',
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
                const SizedBox(height: VSDesignTokens.space2),
                RichText(
                  text: TextSpan(
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text: 'If we need more information from you, we will contact you by email from ',
                      ),
                      TextSpan(
                        text: 'visionsparkai@gmail.com',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: VSTypography.weightSemiBold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}