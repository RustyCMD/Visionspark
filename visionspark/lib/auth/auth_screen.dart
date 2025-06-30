import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/utils/snackbar_utils.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;

  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // 1. Trigger the Google Authentication flow.
      final googleSignIn = GoogleSignIn(serverClientId: '825189008537-9lpvr3no63a79k8hppkhjfm0ha4mtflo.apps.googleusercontent.com');
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      
      // 2. Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) {
        throw 'No Access Token found.';
      }
      if (idToken == null) {
        throw 'No ID Token found.';
      }

      // 3. Sign in to Supabase with the Google ID token.
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      // AuthGate will handle navigation automatically on success.
    } on AuthException catch (error) {
      debugPrint('Google Sign-In AuthException: ${error.message}');
      if(mounted) showErrorSnackbar(context, 'Sign-In Failed: ${error.message}'); // Supabase messages are usually user-friendly
    } catch (error) {
      debugPrint('Google Sign-In unexpected error: $error');
      if(mounted) showErrorSnackbar(context, 'An unexpected error occurred during sign-in. Please try again.');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Helper function to launch URLs
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showErrorSnackbar(context, 'Could not launch $urlString');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLogo(colorScheme),
                const SizedBox(height: 32),
                Text(
                  'Welcome to VisionSpark',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ignite your creativity with the power of AI',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 48),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildGoogleSignInButton(colorScheme, textTheme),
                  ),
                ),
                const SizedBox(height: 32),
                _buildTermsAndPolicyFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(ColorScheme colorScheme) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 100,
            color: colorScheme.secondary.withOpacity(0.5),
          ),
          Icon(
            Icons.auto_awesome, // Sparkle icon
            size: 60,
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleSignInButton(ColorScheme colorScheme, TextTheme textTheme) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    // Define button colors based on theme
    final Color buttonBackgroundColor = isDarkTheme ? colorScheme.surface : Colors.white;
    final Color buttonForegroundColor = isDarkTheme ? colorScheme.onSurface : Colors.black87;
    final Color iconColor = colorScheme.primary; // Keep using primary for the icon

    return ElevatedButton(
      onPressed: _isLoading ? null : _googleSignIn,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonBackgroundColor,
        foregroundColor: buttonForegroundColor,
        minimumSize: const Size(double.infinity, 50),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 2,
      ),
      child: _isLoading
          ? SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(iconColor), // Use iconColor for consistency
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // In a real app, you might use an Image.asset for the Google logo.
                // If using a themed icon, ensure it contrasts with buttonBackgroundColor.
                Icon(Icons.login, color: iconColor),
                const SizedBox(width: 12),
                Text(
                  'Sign In with Google',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: buttonForegroundColor, // Use the adaptive foreground color
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTermsAndPolicyFooter(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          text: 'By continuing, you agree to our ',
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
          children: [
            TextSpan(
              text: 'Terms of Service',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _launchURL('https://visionspark.app/terms-of-service.html');
                },
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _launchURL('https://visionspark.app/privacy-policy.html');
                },
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}