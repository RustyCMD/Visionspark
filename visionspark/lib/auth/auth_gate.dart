import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/main_scaffold.dart';
import './auth_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Log every auth event to the debug console
        if (snapshot.hasData) {
          debugPrint(
              "[AuthGate] Event: ${snapshot.data?.event}, Session: ${snapshot.data?.session != null}");
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final authState = snapshot.data;

        if (authState?.session != null) {
          return const MainScaffold(selectedIndex: 0);
        }

        return const AuthScreen();
      },
    );
  }
}