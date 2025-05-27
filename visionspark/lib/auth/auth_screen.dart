import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('An unexpected error occurred.'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user != null) {
        // User signed up successfully, now get and store timezone
        try {
          final String timezone = await FlutterTimezone.getLocalTimezone();
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(data: {'timezone': timezone}),
          );
        } catch (e) {
          // Handle error fetching or saving timezone, but don't block sign-up flow
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save timezone: $e'), backgroundColor: Colors.orangeAccent),
            );
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign up successful! Please check your email to confirm (if required).')),
          );
        }
      } else {
        // Handle case where sign up didn't return a user but also didn't throw an AuthException
        // This is less common but good to be aware of.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Sign up completed, but user data not immediately available.'), backgroundColor: Theme.of(context).colorScheme.error),
          );
        }
      }

    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('An unexpected error occurred during sign up.'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color lilacPurple = Color(0xFFD0B8E1);
    const Color softTeal = Color(0xFF87CEEB);
    const Color darkText = Color(0xFF22223B);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log In / Sign Up'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 6,
            color: Theme.of(context).colorScheme.surface,
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
                  Icon(Icons.lock_outline, size: 72, color: lilacPurple),
                  const SizedBox(height: 32),
                  Text(
                    'Welcome to Visionspark',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: lilacPurple),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please sign in or create an account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 36),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    obscureText: _obscurePassword,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  ),
                  // Add Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Reset Password'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('To reset your password, please join our Discord server and open a "Reset Password Ticket".'),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: () async {
                                    // Replace with your actual Discord invite link
                                    const discordUrl = 'https://discord.gg/EUQh2MQgmm';
                                    // ignore: deprecated_member_use
                                    await launchUrl(Uri.parse(discordUrl));
                                  },
                                  child: Row(
                                    children: const [
                                      Icon(Icons.link, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('Join Discord', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Forgot Password?'),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: lilacPurple,
                            foregroundColor: darkText,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 2,
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                          ),
                          child: const Text('Sign In'),
                        ),
                  const SizedBox(height: 18),
                  _isLoading
                      ? const SizedBox.shrink()
                      : OutlinedButton(
                          onPressed: _signUp,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: softTeal,
                            side: BorderSide(color: softTeal, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          child: const Text('Sign Up'),
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