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

  // Store the current user profile locally since we're not using Auth0's credential manager
  UserProfile? _currentUserProfile;

  Auth0Service() {
    _auth0 = Auth0(_domain, _clientId);
  }

  /// Sign in with Native Google Sign-In + Auth0 token exchange
  Future<UserProfile?> signIn() async {
    try {
      debugPrint('[Auth0Service] Starting native Google sign-in process...');

      // 1. Trigger native Google sign-in
      final googleSignIn = GoogleSignIn(
        serverClientId: '825189008537-lugehuiggug9hsc2klqodiu3vul42jh0.apps.googleusercontent.com',
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

      // 4. Store the user profile locally for later retrieval
      _currentUserProfile = userProfile;
      debugPrint('[Auth0Service] User profile stored locally');

      // 5. Create a simple session for Supabase using Google tokens
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

    // Clear local user profile
    _currentUserProfile = null;
    debugPrint('[Auth0Service] Local user profile cleared');

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
      // Return the locally stored user profile
      debugPrint('[Auth0Service] Returning locally stored user profile: ${_currentUserProfile != null ? 'Found' : 'Null'}');
      return _currentUserProfile;
    } catch (e) {
      debugPrint('[Auth0Service] Get current user error: $e');
      return null;
    }
  }

  /// Get current user's profile picture URL from multiple sources with fallbacks
  /// This method tries to retrieve the profile picture URL from:
  /// 1. Auth0 user profile (most reliable)
  /// 2. Supabase user metadata
  Future<String?> getCurrentUserProfilePictureUrl() async {
    try {
      debugPrint('[Auth0Service] ========== STARTING PROFILE PICTURE RETRIEVAL DEBUG ==========');

      // 1. Try Auth0 user profile first (most reliable)
      debugPrint('[Auth0Service] Step 1: Trying Auth0 user profile...');
      try {
        final userProfile = await getCurrentUser();
        debugPrint('[Auth0Service] Auth0 user profile result: ${userProfile != null ? 'Found' : 'Null'}');

        if (userProfile != null) {
          debugPrint('[Auth0Service] Auth0 user profile details:');
          debugPrint('[Auth0Service]   - Name: ${userProfile.name}');
          debugPrint('[Auth0Service]   - Picture URL: ${userProfile.pictureUrl}');

          if (userProfile.pictureUrl != null && userProfile.pictureUrl.toString().isNotEmpty) {
            debugPrint('[Auth0Service] ✅ SUCCESS: Profile picture URL retrieved from Auth0 profile: ${userProfile.pictureUrl}');
            return userProfile.pictureUrl.toString();
          } else {
            debugPrint('[Auth0Service] ❌ Auth0 profile picture URL is null or empty');
          }
        } else {
          debugPrint('[Auth0Service] ❌ Auth0 user profile is null');
        }
      } catch (e) {
        debugPrint('[Auth0Service] ❌ Exception getting Auth0 profile: $e');
        debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      }

      // 2. Try Supabase user metadata as fallback
      debugPrint('[Auth0Service] Step 2: Trying Supabase user metadata...');
      try {
        final supabaseUser = Supabase.instance.client.auth.currentUser;
        debugPrint('[Auth0Service] Supabase user result: ${supabaseUser != null ? 'Found' : 'Null'}');

        if (supabaseUser != null) {
          debugPrint('[Auth0Service] Supabase user metadata: ${supabaseUser.userMetadata}');

          // Check user metadata for picture
          final metadataPicture = supabaseUser.userMetadata?['picture'] as String?;
          debugPrint('[Auth0Service]   - Metadata picture: $metadataPicture');

          if (metadataPicture != null && metadataPicture.isNotEmpty) {
            debugPrint('[Auth0Service] ✅ SUCCESS: Profile picture URL retrieved from Supabase user metadata: $metadataPicture');
            return metadataPicture;
          }

          debugPrint('[Auth0Service] ❌ No profile picture found in Supabase user metadata');
        } else {
          debugPrint('[Auth0Service] ❌ Supabase user is null');
        }
      } catch (e) {
        debugPrint('[Auth0Service] ❌ Exception getting Supabase user metadata: $e');
        debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      }

      debugPrint('[Auth0Service] ========== PROFILE PICTURE RETRIEVAL FAILED - NO URL FOUND ==========');
      return null;
    } catch (e) {
      debugPrint('[Auth0Service] ❌ CRITICAL ERROR in getCurrentUserProfilePictureUrl: $e');
      debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Get current user's email from multiple sources with fallbacks
  /// This method tries to retrieve the email from:
  /// 1. Auth0 user profile (most reliable)
  /// 2. Supabase user metadata
  /// 3. Supabase profiles table
  /// 4. Supabase auth user email (least reliable with Auth0)
  Future<String?> getCurrentUserEmail() async {
    try {
      debugPrint('[Auth0Service] ========== STARTING EMAIL RETRIEVAL DEBUG ==========');

      // 1. Try Auth0 user profile first (most reliable)
      debugPrint('[Auth0Service] Step 1: Trying Auth0 user profile...');
      try {
        final userProfile = await getCurrentUser();
        debugPrint('[Auth0Service] Auth0 user profile result: ${userProfile != null ? 'Found' : 'Null'}');

        if (userProfile != null) {
          debugPrint('[Auth0Service] Auth0 user profile details:');
          debugPrint('[Auth0Service]   - Name: ${userProfile.name}');
          debugPrint('[Auth0Service]   - Email: ${userProfile.email}');
          debugPrint('[Auth0Service]   - Sub: ${userProfile.sub}');

          if (userProfile.email != null && userProfile.email!.isNotEmpty) {
            debugPrint('[Auth0Service] ✅ SUCCESS: Email retrieved from Auth0 profile: ${userProfile.email}');
            return userProfile.email;
          } else {
            debugPrint('[Auth0Service] ❌ Auth0 profile email is null or empty');
          }
        } else {
          debugPrint('[Auth0Service] ❌ Auth0 user profile is null');
        }
      } catch (e) {
        debugPrint('[Auth0Service] ❌ Exception getting Auth0 profile: $e');
        debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      }

      // 2. Try Supabase user metadata and direct email
      debugPrint('[Auth0Service] Step 2: Trying Supabase user data...');
      try {
        final supabaseUser = Supabase.instance.client.auth.currentUser;
        debugPrint('[Auth0Service] Supabase user result: ${supabaseUser != null ? 'Found' : 'Null'}');

        if (supabaseUser != null) {
          debugPrint('[Auth0Service] Supabase user details:');
          debugPrint('[Auth0Service]   - ID: ${supabaseUser.id}');
          debugPrint('[Auth0Service]   - Email: ${supabaseUser.email}');
          debugPrint('[Auth0Service]   - User metadata: ${supabaseUser.userMetadata}');
          debugPrint('[Auth0Service]   - App metadata: ${supabaseUser.appMetadata}');

          // Check user metadata first
          final metadataEmail = supabaseUser.userMetadata?['email'] as String?;
          debugPrint('[Auth0Service]   - Metadata email: $metadataEmail');

          if (metadataEmail != null && metadataEmail.isNotEmpty) {
            debugPrint('[Auth0Service] ✅ SUCCESS: Email retrieved from Supabase user metadata: $metadataEmail');
            return metadataEmail;
          }

          // Check direct email field
          if (supabaseUser.email != null && supabaseUser.email!.isNotEmpty) {
            debugPrint('[Auth0Service] ✅ SUCCESS: Email retrieved from Supabase user email: ${supabaseUser.email}');
            return supabaseUser.email;
          }

          debugPrint('[Auth0Service] ❌ No email found in Supabase user data');
        } else {
          debugPrint('[Auth0Service] ❌ Supabase user is null');
        }
      } catch (e) {
        debugPrint('[Auth0Service] ❌ Exception getting Supabase user: $e');
        debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      }

      // 3. Try profiles table as last resort
      debugPrint('[Auth0Service] Step 3: Trying profiles table...');
      try {
        final supabaseUser = Supabase.instance.client.auth.currentUser;
        if (supabaseUser != null) {
          debugPrint('[Auth0Service] Querying profiles table for user ID: ${supabaseUser.id}');

          final response = await Supabase.instance.client
              .from('profiles')
              .select('email')
              .eq('id', supabaseUser.id)
              .single();

          debugPrint('[Auth0Service] Profiles table response: $response');

          final email = response['email'] as String?;
          debugPrint('[Auth0Service] Profiles table email: $email');

          if (email != null && email.isNotEmpty) {
            debugPrint('[Auth0Service] ✅ SUCCESS: Email retrieved from profiles table: $email');
            return email;
          } else {
            debugPrint('[Auth0Service] ❌ Profiles table email is null or empty');
          }
        } else {
          debugPrint('[Auth0Service] ❌ Cannot query profiles table - Supabase user is null');
        }
      } catch (e) {
        debugPrint('[Auth0Service] ❌ Exception querying profiles table: $e');
        debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      }

      debugPrint('[Auth0Service] ========== EMAIL RETRIEVAL FAILED - NO EMAIL FOUND ==========');
      return null;
    } catch (e) {
      debugPrint('[Auth0Service] ❌ CRITICAL ERROR in getCurrentUserEmail: $e');
      debugPrint('[Auth0Service] Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final hasLocalProfile = _currentUserProfile != null;
      final hasSupabaseSession = Supabase.instance.client.auth.currentSession != null;

      // Both local profile and Supabase session should exist
      debugPrint('[Auth0Service] Authentication check - Local profile: $hasLocalProfile, Supabase session: $hasSupabaseSession');
      return hasLocalProfile && hasSupabaseSession;
    } catch (e) {
      debugPrint('[Auth0Service] Is authenticated error: $e');
      return false;
    }
  }

  /// Force clear all authentication state (useful for troubleshooting)
  Future<void> forceSignOut() async {
    debugPrint('[Auth0Service] Force sign-out - clearing all authentication state...');

    // Clear local user profile
    _currentUserProfile = null;
    debugPrint('[Auth0Service] Local user profile cleared');

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

      // First, check if a user with this Google ID or email already exists
      final existingUser = await _findExistingUserByGoogleId(userProfile.sub, userProfile.email);

      if (existingUser != null) {
        debugPrint('[Auth0Service] Found existing user with Google ID: ${userProfile.sub}');
        debugPrint('[Auth0Service] Existing user ID: ${existingUser['id']}');
        debugPrint('[Auth0Service] Existing user email: ${existingUser['email']}');

        // For existing users, create a custom session that links to the existing Supabase user
        try {
          // Create a custom JWT that will link to the existing user ID
          await _createCustomSessionForExistingUser(existingUser['id'], userProfile);
          debugPrint('[Auth0Service] Successfully linked to existing user account');
          return;
        } catch (e) {
          debugPrint('[Auth0Service] Error linking to existing user: $e');
          // If linking fails, we have a serious problem - don't create duplicate
          throw Exception('Failed to link to existing account. Please contact support.');
        }
      }

      // If no existing user found, create a new one
      debugPrint('[Auth0Service] No existing user found, creating new account...');

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
          debugPrint('[Auth0Service] Updating user metadata with Google ID: ${userProfile.sub}');

          final updateResponse = await Supabase.instance.client.auth.updateUser(
            UserAttributes(
              data: {
                'name': userProfile.name,
                'picture': userProfile.pictureUrl?.toString(),
                'provider': 'google',
                'google_id': userProfile.sub,
                'sub': userProfile.sub, // Store both google_id and sub for compatibility
              },
            ),
          );

          if (updateResponse.user != null) {
            debugPrint('[Auth0Service] ✅ User metadata updated successfully');
            debugPrint('[Auth0Service] Stored Google ID: ${updateResponse.user!.userMetadata?['google_id']}');
            debugPrint('[Auth0Service] Stored sub: ${updateResponse.user!.userMetadata?['sub']}');
          } else {
            debugPrint('[Auth0Service] ⚠️ Warning: User metadata update returned null user');
          }

          debugPrint('[Auth0Service] New user session created and user metadata updated');
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

  /// Find existing user by Google ID to prevent duplicate account creation
  Future<Map<String, dynamic>?> _findExistingUserByGoogleId(String googleId, [String? email]) async {
    try {
      debugPrint('[Auth0Service] Searching for existing user with Google ID: $googleId, email: $email');

      // Use the server-side function to search for existing users
      final response = await Supabase.instance.client.functions.invoke(
        'find-existing-user-by-google-id',
        body: {
          'googleId': googleId,
          'email': email,
        },
      );

      if (response.data != null && response.data['found'] == true) {
        final userData = response.data['user'] as Map<String, dynamic>;
        debugPrint('[Auth0Service] Found existing user: ${userData['id']}');
        return userData;
      }

      debugPrint('[Auth0Service] No existing user found');
      return null;

    } catch (e) {
      debugPrint('[Auth0Service] Error finding existing user by Google ID: $e');
      // Fallback to local search if server function fails
      return await _findExistingUserByGoogleIdInProfiles(googleId);
    }
  }

  /// Alternative method to find user by Google ID in profiles table
  Future<Map<String, dynamic>?> _findExistingUserByGoogleIdInProfiles(String googleId) async {
    try {
      debugPrint('[Auth0Service] Searching profiles table for Google ID: $googleId');

      // Since we can't directly access auth.users from client side,
      // we'll use a different approach: check if current user exists and matches
      final currentUser = Supabase.instance.client.auth.currentUser;

      if (currentUser != null) {
        final currentGoogleId = currentUser.userMetadata?['google_id'] as String?;
        if (currentGoogleId == googleId) {
          debugPrint('[Auth0Service] Current user matches Google ID: ${currentUser.id}');
          return {
            'id': currentUser.id,
            'email': currentUser.email,
          };
        }
      }

      // For a more comprehensive solution, we would need a server-side function
      // to search through all users. For now, we'll return null to create a new user
      // if no current user matches
      debugPrint('[Auth0Service] No matching Google ID found, will create new user');
      return null;

    } catch (e) {
      debugPrint('[Auth0Service] Error searching for existing user: $e');
      return null;
    }
  }

  /// Create a custom session for an existing user to prevent duplicate account creation
  Future<void> _createCustomSessionForExistingUser(String existingUserId, UserProfile userProfile) async {
    try {
      debugPrint('[Auth0Service] Creating custom session for existing user: $existingUserId');

      // Use the server-side function to create a session for the existing user
      final response = await Supabase.instance.client.functions.invoke(
        'create-session-for-existing-user',
        body: {
          'userId': existingUserId,
          'userProfile': {
            'name': userProfile.name,
            'email': userProfile.email,
            'picture': userProfile.pictureUrl?.toString(),
            'google_id': userProfile.sub,
          },
        },
      );

      if (response.data != null && response.data['success'] == true) {
        final sessionData = response.data['session'];

        debugPrint('[Auth0Service] Received session data from server');
        debugPrint('[Auth0Service] Access token: ${sessionData['access_token']?.substring(0, 20)}...');
        debugPrint('[Auth0Service] Refresh token: ${sessionData['refresh_token']?.substring(0, 20)}...');
        debugPrint('[Auth0Service] User ID: ${sessionData['user']?['id']}');

        // Set the session in Supabase client using the refresh token
        // The setSession method in Supabase Flutter takes only the refresh token
        await Supabase.instance.client.auth.setSession(sessionData['refresh_token']);

        debugPrint('[Auth0Service] Custom session set successfully for existing user');
      } else {
        debugPrint('[Auth0Service] Server response: ${response.data}');
        throw Exception('Server failed to create session for existing user');
      }

    } catch (e) {
      debugPrint('[Auth0Service] Error creating custom session for existing user: $e');
      rethrow;
    }
  }
}