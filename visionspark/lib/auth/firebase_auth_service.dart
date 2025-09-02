import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class FirebaseAuthService {
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Get current Firebase user
  User? get currentUser => _firebaseAuth.currentUser;

  /// Get Firebase auth state stream
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  /// Register with email and password
  Future<User?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      debugPrint('[FirebaseAuthService] Starting registration for: $email');

      // Create user with Firebase Auth
      final UserCredential result = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      if (user != null) {
        // Update display name
        await user.updateDisplayName(displayName);

        // Send email verification
        await user.sendEmailVerification();
        debugPrint('[FirebaseAuthService] Email verification sent to: $email');

        // Create user profile in Supabase (don't let this fail the registration)
        try {
          await _createUserProfile(user, displayName);
        } catch (profileError) {
          debugPrint('[FirebaseAuthService] Profile creation failed but continuing with registration: $profileError');
        }

        debugPrint('[FirebaseAuthService] Registration successful for: $email');
        return user;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('[FirebaseAuthService] Registration error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[FirebaseAuthService] Unexpected registration error: $e');
      rethrow;
    }
  }

  /// Sign in with email and password
  Future<User?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('[FirebaseAuthService] Starting sign-in for: $email');

      final UserCredential result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      if (user != null) {
        // Sync user profile with Supabase
        await _syncUserProfile(user);
        debugPrint('[FirebaseAuthService] Sign-in successful for: $email');
        return user;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('[FirebaseAuthService] Sign-in error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[FirebaseAuthService] Unexpected sign-in error: $e');
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      debugPrint('[FirebaseAuthService] Sending password reset email to: $email');
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      debugPrint('[FirebaseAuthService] Password reset email sent successfully');
    } on FirebaseAuthException catch (e) {
      debugPrint('[FirebaseAuthService] Password reset error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[FirebaseAuthService] Unexpected password reset error: $e');
      rethrow;
    }
  }

  /// Send email verification
  Future<void> sendEmailVerification() async {
    try {
      final User? user = _firebaseAuth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        debugPrint('[FirebaseAuthService] Email verification sent to: ${user.email}');
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[FirebaseAuthService] Email verification error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[FirebaseAuthService] Unexpected email verification error: $e');
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      debugPrint('[FirebaseAuthService] Starting sign-out process...');
      
      // Sign out from Firebase
      await _firebaseAuth.signOut();
      
      // Sign out from Supabase
      await _supabase.auth.signOut();
      
      debugPrint('[FirebaseAuthService] Sign-out successful');
    } catch (e) {
      debugPrint('[FirebaseAuthService] Sign-out error: $e');
      rethrow;
    }
  }

  /// Create user profile in Supabase via Edge Function
  Future<void> _createUserProfile(User user, String displayName) async {
    try {
      debugPrint('[FirebaseAuthService] Creating user profile in Supabase...');
      debugPrint('[FirebaseAuthService] User data: UID=${user.uid}, Email=${user.email}, DisplayName=$displayName');

      // Call Supabase Edge Function to create profile
      final response = await _supabase.functions.invoke(
        'create-user-profile',
        body: {
          'firebase_uid': user.uid,
          'email': user.email,
          'full_name': displayName,
          'email_verified': user.emailVerified,
        },
      );

      debugPrint('[FirebaseAuthService] Profile creation response status: ${response.status}');
      debugPrint('[FirebaseAuthService] Profile creation response data: ${response.data}');

      if (response.status == 200 || response.status == 201) {
        debugPrint('[FirebaseAuthService] User profile created/updated in Supabase successfully');
      } else {
        debugPrint('[FirebaseAuthService] Profile creation failed with status: ${response.status}');
      }
    } catch (e, stackTrace) {
      debugPrint('[FirebaseAuthService] Error creating user profile: $e');
      debugPrint('[FirebaseAuthService] Stack trace: $stackTrace');
      rethrow; // Rethrow so the registration method can catch and handle it
    }
  }

  /// Sync user profile with Supabase via Edge Function
  Future<void> _syncUserProfile(User user) async {
    try {
      debugPrint('[FirebaseAuthService] Syncing user profile with Supabase...');

      // Call Supabase Edge Function to sync profile
      final response = await _supabase.functions.invoke(
        'create-user-profile',
        body: {
          'firebase_uid': user.uid,
          'email': user.email,
          'full_name': user.displayName,
          'email_verified': user.emailVerified,
        },
      );

      debugPrint('[FirebaseAuthService] Profile sync response: ${response.status} - ${response.data}');

      if (response.status == 200 || response.status == 201) {
        debugPrint('[FirebaseAuthService] User profile synced with Supabase');
      } else {
        debugPrint('[FirebaseAuthService] Error syncing profile: Status ${response.status}, Data: ${response.data}');
      }
    } catch (e) {
      debugPrint('[FirebaseAuthService] Error syncing user profile: $e');
      // Don't rethrow - profile sync failure shouldn't block authentication
    }
  }

  /// Get user profile from Supabase
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final User? user = _firebaseAuth.currentUser;
      if (user == null) return null;

      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.uid)
          .maybeSingle();

      return profile;
    } catch (e) {
      debugPrint('[FirebaseAuthService] Error getting user profile: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      final User? user = _firebaseAuth.currentUser;
      if (user == null) return;

      // Update Firebase user profile
      await user.updateDisplayName(displayName);
      if (photoURL != null) {
        await user.updatePhotoURL(photoURL);
      }

      // Update Supabase profile
      await _supabase.from('profiles').update({
        'full_name': displayName,
        'avatar_url': photoURL,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.uid);

      debugPrint('[FirebaseAuthService] User profile updated');
    } catch (e) {
      debugPrint('[FirebaseAuthService] Error updating user profile: $e');
      rethrow;
    }
  }

  /// Check if email is verified
  bool get isEmailVerified => _firebaseAuth.currentUser?.emailVerified ?? false;

  /// Reload current user to get updated email verification status
  Future<void> reloadUser() async {
    await _firebaseAuth.currentUser?.reload();
  }

  /// Get error message from FirebaseAuthException
  static String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      default:
        return e.message ?? 'An unexpected error occurred.';
    }
  }
}
