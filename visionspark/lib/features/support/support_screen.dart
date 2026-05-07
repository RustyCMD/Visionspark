import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/design_system/design_system.dart';
import '../../shared/utils/snackbar_utils.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      showErrorSnackbar(context,
          'Could not submit: no email on this account. Please sign in again.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.functions.invoke(
        'report-support-issue',
        body: {
          'title': _title.text.trim(),
          'content': _content.text.trim(),
          'email': email,
        },
      );
      if (!mounted) return;
      showSuccessSnackbar(context, 'Report submitted.');
      _title.clear();
      _content.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: ListView(
            padding: VSResponsive.getResponsivePadding(context),
            children: [
              _hero(cs, tt),
              const SizedBox(height: VSDesignTokens.space6),
              _form(cs, tt),
              const SizedBox(height: VSDesignTokens.space5),
              _disclaimer(cs, tt),
              const SizedBox(height: VSDesignTokens.space12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(ColorScheme cs, TextTheme tt) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.support_agent_rounded,
              color: cs.primary, size: VSDesignTokens.iconL),
        ),
        const SizedBox(height: VSDesignTokens.space4),
        Text(
          'Support & feedback',
          style: tt.headlineMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: VSTypography.weightBold,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSDesignTokens.space2),
        Text(
          'Send us bugs, ideas, or anything in between.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _form(ColorScheme cs, TextTheme tt) {
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VSSectionHeader(
              icon: Icons.contact_support_outlined,
              title: 'New ticket',
              subtitle: 'A short subject and clear details help us help you.',
            ),
            const SizedBox(height: VSDesignTokens.space5),
            VSAccessibleTextField(
              controller: _title,
              labelText: 'Subject',
              hintText: 'What\'s this about?',
              prefixIcon: const Icon(Icons.title_rounded),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter a subject.' : null,
            ),
            const SizedBox(height: VSDesignTokens.space4),
            VSAccessibleTextField(
              controller: _content,
              labelText: 'Message',
              hintText: 'Describe your issue or feedback…',
              prefixIcon: const Icon(Icons.article_outlined),
              maxLines: 6,
              textAlignVertical: TextAlignVertical.top,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please write a message.';
                if (v.trim().length < 10) return 'At least 10 characters please.';
                return null;
              },
            ),
            const SizedBox(height: VSDesignTokens.space5),
            VSButton(
              text: 'Submit ticket',
              icon: _busy ? null : const Icon(Icons.send_rounded),
              onPressed: _busy ? null : _submit,
              isLoading: _busy,
              isFullWidth: true,
              size: VSButtonSize.large,
            ),
          ],
        ),
      ),
    );
  }

  Widget _disclaimer(ColorScheme cs, TextTheme tt) {
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusL,
      color: cs.surfaceContainerLow,
      border: Border.all(color: cs.outlineVariant),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: cs.primary, size: VSDesignTokens.iconM),
          const SizedBox(width: VSDesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How we reply',
                  style: tt.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'If we need more info, we\'ll reach out from ',
                      ),
                      TextSpan(
                        text: 'visionsparkai@gmail.com',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: VSTypography.weightSemiBold,
                        ),
                      ),
                      const TextSpan(text: '.'),
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
