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

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _sparkleController;
  late AnimationController _fadeController;
  late Animation<double> _sparkleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _sparkleController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _sparkleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _sparkleController, curve: Curves.easeInOut),
    );
    
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    
    _fadeController.forward();
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.4, 1.0],
            colors: [
              colorScheme.surface,
              colorScheme.primary.withOpacity(0.02),
              colorScheme.secondary.withOpacity(0.04),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Stack(
              children: [
                // Floating geometric decorations
                _buildFloatingDecorations(colorScheme, size),
                
                // Main content
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: size.width * 0.08,
                    vertical: size.height * 0.02,
                  ),
                  child: Column(
                    children: [
                      // Top spacer - asymmetrical
                      SizedBox(height: size.height * 0.12),
                      
                      // Logo section with unique positioning
                      _buildLogoSection(colorScheme, size),
                      
                      // Dynamic spacer
                      SizedBox(height: size.height * 0.08),
                      
                      // Welcome text with modern typography
                      _buildWelcomeSection(colorScheme, size),
                      
                      // Flexible spacer that adapts to screen size
                      const Spacer(flex: 2),
                      
                      // Sign in section
                      _buildSignInSection(colorScheme, size),
                      
                      // Bottom spacer
                      SizedBox(height: size.height * 0.04),
                      
                      // Terms and policy
                      _buildTermsSection(context, colorScheme),
                      
                      SizedBox(height: size.height * 0.02),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingDecorations(ColorScheme colorScheme, Size size) {
    return Stack(
      children: [
        // Top right decoration
        Positioned(
          top: size.height * 0.08,
          right: -size.width * 0.15,
          child: AnimatedBuilder(
            animation: _sparkleAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _sparkleAnimation.value * 6.28,
                child: Container(
                  width: size.width * 0.4,
                  height: size.width * 0.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withOpacity(0.03),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.1),
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        
        // Bottom left decoration
        Positioned(
          bottom: size.height * 0.15,
          left: -size.width * 0.2,
          child: AnimatedBuilder(
            animation: _sparkleAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: -_sparkleAnimation.value * 4.18,
                child: Container(
                  width: size.width * 0.6,
                  height: size.width * 0.6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size.width * 0.15),
                    color: colorScheme.secondary.withOpacity(0.02),
                    border: Border.all(
                      color: colorScheme.secondary.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogoSection(ColorScheme colorScheme, Size size) {
    return Row(
      children: [
        // Asymmetrical positioning
        SizedBox(width: size.width * 0.05),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: _sparkleAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withOpacity(0.08),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: 1 + (_sparkleAnimation.value * 0.1),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                        ),
                        Transform.scale(
                          scale: 1.2 - (_sparkleAnimation.value * 0.2),
                          child: Icon(
                            Icons.lightbulb_outline,
                            size: 72,
                            color: colorScheme.primary.withOpacity(0.2),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeSection(ColorScheme colorScheme, Size size) {
    final textTheme = Theme.of(context).textTheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w300,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.secondary,
            ],
          ).createShader(bounds),
          child: Text(
            'VisionSpark',
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Text(
            'Ignite your creativity with the power of AI',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.8),
              fontWeight: FontWeight.w400,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignInSection(ColorScheme colorScheme, Size size) {
    final textTheme = Theme.of(context).textTheme;
    
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.primary.withOpacity(0.8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isLoading ? null : _googleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.login,
                          color: colorScheme.onPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Sign In with Google',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTermsSection(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          text: 'By continuing, you agree to our ',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: 'Terms of Service',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.primary.withOpacity(0.5),
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
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.primary.withOpacity(0.5),
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