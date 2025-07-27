import 'dart:convert';
import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class Auth0Service {
  static String get _domain => dotenv.env['AUTH0_DOMAIN'] ?? '';
  static String get _clientId => dotenv.env['AUTH0_CLIENT_ID'] ?? '';

  late final Auth0 _auth0;
  
  Auth0Service() {
    _auth0 = Auth0(_domain, _clientId);
  }

  /// Sign in with Native Google Sign-In + Auth0 token exchange
  Future<UserProfile?> signIn() async {
    try {
      debugPrint('[Auth0Service] Starting native Google sign-in process...');

      // 1. Trigger native Google sign-in
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('[Auth0Service] User cancelled Google sign-in');
        return null;
      }

      debugPrint('[Auth0Service] Google sign-in successful for: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? googleAccessToken = googleAuth.accessToken;
      final String? googleIdToken = googleAuth.idToken;

      if (googleAccessToken == null) {
        debugPrint('[Auth0Service] Failed to get Google access token');
        return null;
      }

      debugPrint('[Auth0Service] Got Google tokens, creating user profile...');
      debugPrint('[Auth0Service] Has ID token: ${googleIdToken != null}');

      // 2. Get user info from Google using the access token
      final userInfoResponse = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $googleAccessToken'},
      );

      if (userInfoResponse.statusCode != 200) {
        debugPrint('[Auth0Service] Failed to get user info from Google. Status: ${userInfoResponse.statusCode}');
        return null;
      }

      final googleUserInfo = jsonDecode(userInfoResponse.body);
      debugPrint('[Auth0Service] Google user info retrieved successfully');

      // 3. Create a UserProfile object with Google user data
      final userProfile = UserProfile.fromMap({
        'sub': 'google-oauth2|${googleUserInfo['id']}',
        'name': googleUserInfo['name'],
        'given_name': googleUserInfo['given_name'],
        'family_name': googleUserInfo['family_name'],
        'nickname': googleUserInfo['name'],
        'email': googleUserInfo['email'],
        'email_verified': googleUserInfo['verified_email'],
        'picture': googleUserInfo['picture'],
        'updated_at': DateTime.now().toIso8601String(),
      });

      debugPrint('[Auth0Service] User: ${userProfile.name}');
      debugPrint('[Auth0Service] Email: ${userProfile.email}');

      // 4. Create a simple session for Supabase using Google tokens
      await _createSupabaseSessionWithGoogleToken(googleAccessToken, googleIdToken, userProfile);

      return userProfile;
    } catch (e) {
      debugPrint('[Auth0Service] Native sign-in error: $e');
      rethrow;
    }
  }

  /// Sign out from Auth0 and Supabase
  Future<void> signOut() async {
    debugPrint('[Auth0Service] Starting sign-out process...');

    // Always sign out from Supabase first - this is critical for app state
    try {
      await Supabase.instance.client.auth.signOut();
      debugPrint('[Auth0Service] Supabase sign-out successful');
    } catch (e) {
      debugPrint('[Auth0Service] Supabase sign-out error: $e');
      // Continue with Auth0 logout even if Supabase fails
    }

    // Clear Auth0 credentials from local storage
    try {
      await _auth0.credentialsManager.clearCredentials();
      debugPrint('[Auth0Service] Auth0 credentials cleared from local storage');
    } catch (e) {
      debugPrint('[Auth0Service] Error clearing Auth0 credentials: $e');
      // Continue with web logout even if credential clearing fails
    }

    // Sign out from Google Sign-In
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      debugPrint('[Auth0Service] Google Sign-In logout successful');
    } catch (e) {
      debugPrint('[Auth0Service] Google Sign-In logout error: $e');
      // Don't rethrow - the important parts (Supabase + credential clearing) are done
      debugPrint('[Auth0Service] Continuing with logout despite Google Sign-In logout failure');
    }

    debugPrint('[Auth0Service] Sign-out process completed');
  }

  /// Get current user from Auth0
  Future<UserProfile?> getCurrentUser() async {
    try {
      final credentials = await _auth0.credentialsManager.credentials();
      return credentials.user;
    } catch (e) {
      debugPrint('[Auth0Service] Get current user error: $e');
      return null;
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final hasValidCredentials = await _auth0.credentialsManager.hasValidCredentials();
      final hasSupabaseSession = Supabase.instance.client.auth.currentSession != null;

      // Both Auth0 and Supabase should be authenticated
      return hasValidCredentials && hasSupabaseSession;
    } catch (e) {
      debugPrint('[Auth0Service] Is authenticated error: $e');
      return false;
    }
  }

  /// Force clear all authentication state (useful for troubleshooting)
  Future<void> forceSignOut() async {
    debugPrint('[Auth0Service] Force sign-out - clearing all authentication state...');

    // Clear Supabase session
    try {
      await Supabase.instance.client.auth.signOut();
      debugPrint('[Auth0Service] Supabase session cleared');
    } catch (e) {
      debugPrint('[Auth0Service] Error clearing Supabase session: $e');
    }

    // Clear Auth0 credentials
    try {
      await _auth0.credentialsManager.clearCredentials();
      debugPrint('[Auth0Service] Auth0 credentials cleared');
    } catch (e) {
      debugPrint('[Auth0Service] Error clearing Auth0 credentials: $e');
    }

    debugPrint('[Auth0Service] Force sign-out completed');
  }

  /// Sign in to Supabase using Auth0 JWT
  Future<void> _signInToSupabase(Credentials credentials) async {
    try {
      debugPrint('[Auth0Service] Signing in to Supabase with Auth0 JWT...');

      // Parse the JWT to get user info
      final jwtPayload = _parseJwt(credentials.idToken);
      final email = jwtPayload['email'] as String?;

      if (email == null) {
        throw Exception('No email found in Auth0 token');
      }

      debugPrint('[Auth0Service] User email: $email');

      // Sign in to Supabase with the Auth0 JWT
      // Note: You'll need to configure Supabase to accept Auth0 JWTs
      // For now, we'll use a custom approach
      await _createOrUpdateSupabaseUser(credentials, email);

    } catch (e) {
      debugPrint('[Auth0Service] Supabase sign-in error: $e');
      rethrow;
    }
  }

  /// Create or update user in Supabase
  Future<void> _createOrUpdateSupabaseUser(Credentials credentials, String email) async {
    try {
      // For now, we'll use Supabase's signInAnonymously and then update the user
      // In production, you should configure Supabase to accept Auth0 JWTs directly
      
      final response = await Supabase.instance.client.auth.signInAnonymously();
      
      if (response.user != null) {
        // Update user metadata with Auth0 info
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(
            email: email,
            data: {
              'auth0_user_id': credentials.user.sub,
              'name': credentials.user.name,
              'picture': credentials.user.pictureUrl?.toString(),
              'provider': 'auth0',
            },
          ),
        );
        
        debugPrint('[Auth0Service] Supabase user updated successfully');
      }
    } catch (e) {
      debugPrint('[Auth0Service] Create/update Supabase user error: $e');
      rethrow;
    }
  }

  /// Parse JWT token to extract payload
  Map<String, dynamic> _parseJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw Exception('Invalid JWT token');
    }

    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    
    return json.decode(decoded) as Map<String, dynamic>;
  }

  /// Create Supabase session with Google token and user profile
  Future<void> _createSupabaseSessionWithGoogleToken(String googleAccessToken, String? googleIdToken, UserProfile userProfile) async {
    try {
      debugPrint('[Auth0Service] Creating Supabase session with Google token...');

      // Use Supabase's signInWithIdToken for Google OAuth if we have an ID token
      // This will create a proper authenticated user with email
      if (googleIdToken != null) {
        final response = await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: googleIdToken,
          accessToken: googleAccessToken,
        );

        if (response.user != null) {
          debugPrint('[Auth0Service] Supabase Google OAuth sign-in successful');
          debugPrint('[Auth0Service] Supabase user ID: ${response.user!.id}');
          debugPrint('[Auth0Service] Supabase user email: ${response.user!.email}');

          // The database trigger should automatically create the profile with email
          // But let's also update user metadata for additional info
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(
              data: {
                'name': userProfile.name,
                'picture': userProfile.pictureUrl?.toString(),
                'provider': 'google',
                'google_id': userProfile.sub,
              },
            ),
          );

          debugPrint('[Auth0Service] Supabase session created and user metadata updated');
          return; // Success, exit early
        }
      }

      // Fallback if ID token is not available or OAuth fails
      debugPrint('[Auth0Service] ID token not available or OAuth failed, using fallback method');
      throw Exception('Google ID token not available');

    } catch (e) {
      debugPrint('[Auth0Service] Supabase session creation error: $e');
      // Fallback to manual profile creation if OAuth fails
      await _createProfileManually(userProfile);
    }
  }

  /// Fallback method to manually create profile if OAuth fails
  Future<void> _createProfileManually(UserProfile userProfile) async {
    try {
      debugPrint('[Auth0Service] Attempting manual profile creation...');

      // Sign in anonymously as fallback
      final response = await Supabase.instance.client.auth.signInAnonymously();

      if (response.user != null) {
        // Manually insert into profiles table with email
        await Supabase.instance.client.from('profiles').upsert({
          'id': response.user!.id,
          'email': userProfile.email,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Update user metadata
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(
            data: {
              'name': userProfile.name,
              'picture': userProfile.pictureUrl?.toString(),
              'provider': 'google',
              'google_id': userProfile.sub,
              'email': userProfile.email, // Store email in metadata too
            },
          ),
        );

        debugPrint('[Auth0Service] Manual profile creation successful');
      }
    } catch (e) {
      debugPrint('[Auth0Service] Manual profile creation error: $e');
      rethrow;
    }
  }
}
