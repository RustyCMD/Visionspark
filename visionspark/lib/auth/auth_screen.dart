import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../../shared/utils/snackbar_utils.dart';

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
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: colorScheme.onSurface.withOpacity(0.7)),
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outlined, color: colorScheme.onSurface.withOpacity(0.7)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: colorScheme.onSurface.withOpacity(0.7)),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    obscureText: _obscurePassword,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  // Add Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final TextEditingController emailDialogController = TextEditingController();
                        // This local variable is captured by the closures below.
                        // It's used to control the UI state of the dialog via StatefulBuilder.
                        bool isDialogLoading = false;

                        await showDialog(
                          context: context, // This is AuthScreen's BuildContext
                          barrierDismissible: !isDialogLoading, // Initial value is true, will not update dynamically with isDialogLoading
                          builder: (BuildContext dialogContext) { // This is the BuildContext for the AlertDialog itself
                            return StatefulBuilder(
                              builder: (BuildContext sbContext, StateSetter setStateDialog) { // sbContext is for StatefulBuilder
                                return AlertDialog(
                                  title: Text('Reset Password', style: TextStyle(color: colorScheme.onSurface)),
                                  content: TextField(
                                    controller: emailDialogController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                      labelText: 'Enter your email',
                                      labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    style: TextStyle(color: colorScheme.onSurface),
                                    enabled: !isDialogLoading,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: isDialogLoading ? null : () {
                                        if (dialogContext.mounted) { // Ensure AlertDialog's context is valid
                                          Navigator.pop(dialogContext);
                                        }
                                      },
                                      child: Text('Cancel', style: TextStyle(color: colorScheme.primary)),
                                    ),
                                    ElevatedButton(
                                      onPressed: isDialogLoading ? null : () async {
                                        final email = emailDialogController.text.trim();
                                        if (email.isEmpty) {
                                          // Show snackbar on AuthScreen's context
                                          // No need to check this.mounted here as this code path doesn't involve async gaps after dialog display
                                          showErrorSnackbar(this.context, 'Email cannot be empty.');
                                          return; // Keep dialog open
                                        }

                                        // Check if StatefulBuilder's context is still mounted BEFORE calling its setState
                                        if (!sbContext.mounted) return;
                                        
                                        setStateDialog(() {
                                          isDialogLoading = true;
                                        });

                                        String? successMessage;
                                        String? errorMessage;

                                        try {
                                          await Supabase.instance.client.auth.resetPasswordForEmail(email);
                                          successMessage = 'Password reset email sent to $email. Please check your inbox.';
                                        } on AuthException catch (e) {
                                          errorMessage = e.message;
                                        } catch (e) {
                                          errorMessage = 'An unexpected error occurred: \${e.toString()}';
                                        }

                                        // After async operation, check if AlertDialog's context is still valid before popping
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }

                                        // Then, check if AuthScreen's context is still valid before showing snackbar
                                        if (mounted) { // This 'mounted' refers to _AuthScreenState.mounted
                                          if (successMessage != null) {
                                            showSuccessSnackbar(this.context, successMessage);
                                          } else if (errorMessage != null) {
                                            showErrorSnackbar(this.context, errorMessage);
                                          }
                                        }
                                        // No need to call setStateDialog(isDialogLoading = false) as dialog is popped.
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
                                      child: isDialogLoading 
                                          ? SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary)),
                                            )
                                          : Text('Send Reset Email', style: TextStyle(color: colorScheme.onPrimary)),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ).then((_) {
                          // Dispose controller after dialog is closed, regardless of how it was closed.
                          // This runs when the Future from showDialog completes.
                          emailDialogController.dispose();
                        });
                      },
                      child: Text('Forgot Password?', style: TextStyle(color: colorScheme.primary)),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
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
                            foregroundColor: colorScheme.secondary,
                            side: BorderSide(color: colorScheme.secondary, width: 1.5),
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