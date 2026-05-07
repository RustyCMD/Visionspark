import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../shared/design_system/design_system.dart';
import '../shared/utils/snackbar_utils.dart';
import 'firebase_auth_service.dart';
import 'form_validators.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _auth = FirebaseAuthService();

  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordResetEmail(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) showErrorSnackbar(context, FirebaseAuthService.getErrorMessage(e));
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not send reset email. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: VSAuroraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: VSDesignTokens.space6,
                vertical: VSDesignTokens.space5,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _sent ? _success(cs, tt) : _form(cs, tt),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ColorScheme cs, TextTheme tt) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset your password',
            style: tt.headlineMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Text(
            'Enter the email tied to your account and we\'ll send a reset link.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: VSDesignTokens.space6),
          VSAccessibleTextField(
            controller: _email,
            labelText: 'Email',
            hintText: 'you@example.com',
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _send(),
            validator: FormValidators.validateEmail,
          ),
          const SizedBox(height: VSDesignTokens.space5),
          VSButton(
            text: 'Send reset link',
            onPressed: _busy ? null : _send,
            isLoading: _busy,
            isFullWidth: true,
            size: VSButtonSize.large,
          ),
          const SizedBox(height: VSDesignTokens.space3),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }

  Widget _success(ColorScheme cs, TextTheme tt) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mark_email_read_rounded, size: 40, color: cs.primary),
        ),
        const SizedBox(height: VSDesignTokens.space5),
        Text(
          'Check your inbox',
          style: tt.headlineSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: VSTypography.weightBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space2),
        Text(
          'We sent a reset link to',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          _email.text.trim(),
          style: tt.titleMedium?.copyWith(
            color: cs.primary,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space2),
        Text(
          'It might take a minute. Don\'t forget to check spam.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSDesignTokens.space6),
        VSButton(
          text: 'Resend email',
          icon: const Icon(Icons.refresh_rounded),
          variant: VSButtonVariant.outline,
          isFullWidth: true,
          onPressed: _busy
              ? null
              : () {
                  setState(() => _sent = false);
                  _send();
                },
        ),
        const SizedBox(height: VSDesignTokens.space3),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
