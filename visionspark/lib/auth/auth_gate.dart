import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/main_scaffold.dart';
import './auth_screen.dart';
// dwa
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Log every auth event to the debug console
        if (snapshot.hasData) {
          final event = snapshot.data?.event;
          final hasSession = snapshot.data?.session != null;
          debugPrint("[AuthGate] Event: $event, Session: $hasSession");

          // Log additional details for sign out events
          if (event == AuthChangeEvent.signedOut) {
            debugPrint("[AuthGate] User signed out - redirecting to login screen");
          } else if (event == AuthChangeEvent.signedIn) {
            debugPrint("[AuthGate] User signed in - redirecting to main app");
          }
        }

        if (!snapshot.hasData) {
          debugPrint("[AuthGate] No auth data available - showing loading");
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final authState = snapshot.data;

        if (authState?.session != null) {
          debugPrint("[AuthGate] Valid session found - showing main app");
          return const MainScaffold(selectedIndex: 0);
        }

        debugPrint("[AuthGate] No valid session - showing login screen");
        return const AuthScreen();
      },
    );
  }
}