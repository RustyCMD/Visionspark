import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../shared/design_system/design_system.dart';
import '../shared/utils/snackbar_utils.dart';
import 'firebase_auth_service.dart';
import 'form_validators.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _auth = FirebaseAuthService();

  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  int _strength = 0;

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      setState(() => _strength = FormValidators.getPasswordStrength(_password.text));
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await _auth.registerWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
      );
      if (user != null && mounted) {
        showSuccessSnackbar(context, 'Account created. Check your email to verify.');
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) showErrorSnackbar(context, FirebaseAuthService.getErrorMessage(e));
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Create your account',
                        style: tt.headlineMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: VSTypography.weightBold,
                        ),
                      ),
                      const SizedBox(height: VSDesignTokens.space2),
                      Text(
                        'Join VisionSpark and start generating.',
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: VSDesignTokens.space6),
                      VSAccessibleTextField(
                        controller: _name,
                        labelText: 'Display name',
                        hintText: 'How should we call you?',
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: FormValidators.validateDisplayName,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: VSDesignTokens.space4),
                      VSAccessibleTextField(
                        controller: _email,
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: FormValidators.validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: VSDesignTokens.space4),
                      VSAccessibleTextField(
                        controller: _password,
                        labelText: 'Password',
                        hintText: 'Choose a strong password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        obscureText: _obscure,
                        validator: FormValidators.validatePassword,
                        textInputAction: TextInputAction.next,
                      ),
                      if (_password.text.isNotEmpty) ...[
                        const SizedBox(height: VSDesignTokens.space2),
                        _StrengthMeter(level: _strength),
                      ],
                      const SizedBox(height: VSDesignTokens.space4),
                      VSAccessibleTextField(
                        controller: _confirm,
                        labelText: 'Confirm password',
                        hintText: 'Repeat your password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        obscureText: _obscureConfirm,
                        validator: (v) => FormValidators.validatePasswordConfirmation(
                          v,
                          _password.text,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _register(),
                      ),
                      const SizedBox(height: VSDesignTokens.space6),
                      VSButton(
                        text: 'Create account',
                        onPressed: _busy ? null : _register,
                        isLoading: _busy,
                        isFullWidth: true,
                        size: VSButtonSize.large,
                      ),
                      const SizedBox(height: VSDesignTokens.space3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Sign in'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  final int level;
  const _StrengthMeter({required this.level});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = Color(FormValidators.getPasswordStrengthColor(level));
    final label = FormValidators.getPasswordStrengthText(level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < level
                          ? color
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Password strength: $label',
          style: tt.bodySmall?.copyWith(color: color, fontWeight: VSTypography.weightSemiBold),
        ),
      ],
    );
  }
}
