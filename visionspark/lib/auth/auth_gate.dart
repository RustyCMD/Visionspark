import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/main_scaffold.dart';
import './auth_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Log every auth event to the debug console
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint("[AuthGate] Waiting for auth state - showing loading");
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          debugPrint("[AuthGate] User authenticated: ${user.email} - showing main app");
          return const MainScaffold(selectedIndex: 0);
        }

        debugPrint("[AuthGate] No authenticated user - showing login screen");
        return const AuthScreen();
      },
    );
  }
}