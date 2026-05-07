import 'package:firebase_auth/firebase_auth.dart';

import '../shared/design_system/design_system.dart';
import '../shared/utils/snackbar_utils.dart';
import 'firebase_auth_service.dart';
import 'form_validators.dart';
import 'password_reset_screen.dart';
import 'registration_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = FirebaseAuthService();

  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) showErrorSnackbar(context, FirebaseAuthService.getErrorMessage(e));
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: VSAuroraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: VSDesignTokens.space6,
                vertical: VSDesignTokens.space8,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Brand(cs: cs, tt: tt),
                      const SizedBox(height: VSDesignTokens.space10),
                      VSCard(
                        padding: const EdgeInsets.all(VSDesignTokens.space6),
                        borderRadius: VSDesignTokens.radiusXL,
                        color: cs.surfaceContainer.withValues(alpha: 0.85),
                        border: Border.all(color: cs.outlineVariant),
                        elevation: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome back',
                              style: tt.headlineSmall?.copyWith(
                                color: cs.onSurface,
                                fontWeight: VSTypography.weightBold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: VSDesignTokens.space2),
                            Text(
                              'Sign in to keep creating',
                              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: VSDesignTokens.space6),
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
                              hintText: 'Your password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _signIn(),
                              validator: (v) =>
                                  (v == null || v.isEmpty) ? 'Password is required' : null,
                            ),
                            const SizedBox(height: VSDesignTokens.space2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PasswordResetScreen(),
                                  ),
                                ),
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            const SizedBox(height: VSDesignTokens.space2),
                            VSButton(
                              text: 'Sign in',
                              onPressed: _busy ? null : _signIn,
                              isLoading: _busy,
                              isFullWidth: true,
                              size: VSButtonSize.large,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: VSDesignTokens.space5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "New to VisionSpark?",
                            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegistrationScreen(),
                              ),
                            ),
                            child: const Text('Create account'),
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

class _Brand extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  const _Brand({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 44),
        ),
        const SizedBox(height: VSDesignTokens.space5),
        Text(
          'VisionSpark',
          style: tt.displaySmall?.copyWith(
            color: cs.onSurface,
            fontWeight: VSTypography.weightBold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space2),
        Text(
          'AI image generation, refined.',
          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
