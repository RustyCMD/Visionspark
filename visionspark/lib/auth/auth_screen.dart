import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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
        setState(() => _isLoading = false);
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
      if(mounted) showErrorSnackbar(context, 'Sign-In Failed: ${error.message}');
    } catch (error) {
      if(mounted) showErrorSnackbar(context, 'An unexpected error occurred: $error');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log In / Sign Up'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 6,
            color: colorScheme.surface,
            shadowColor: Theme.of(context).shadowColor.withOpacity(0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.lock_outline, size: 72, color: colorScheme.primary),
                  const SizedBox(height: 32),
                  Text(
                    'Welcome to Visionspark',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please sign in or create an account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 36),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                          onPressed: _googleSignIn,
                          icon: const Icon(Icons.login),
                          label: const Text('Sign In with Google'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            textStyle: const TextStyle(fontSize: 18)
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 