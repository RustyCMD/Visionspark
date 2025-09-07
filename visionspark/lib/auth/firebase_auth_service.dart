import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class FirebaseAuthService {
  final FirebaseAuth _firebaseAuth;
  final SupabaseClient _supabase;

  FirebaseAuthService({
    FirebaseAuth? firebaseAuth,
    SupabaseClient? supabase,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _supabase = supabase ?? Supabase.instance.client;

  /// Get current Firebase user
  User? get currentUser => _firebaseAuth.currentUser;

  /// Get Firebase auth state stream
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  static String? _lastEnsuredUid;

  /// Public: ensure profile for current user once per session (idempotent)
  Future<void> ensureCurrentUserProfileExists() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    if (_lastEnsuredUid == user.uid) {
      debugPrint('[FirebaseAuthService] ensureCurrentUserProfileExists: already ensured for ${user.uid}, skipping');
      return;
    }
    await _ensureUserProfileExists(user);
    _lastEnsuredUid = user.uid;
  }

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

        // Create user profile in Supabase (must succeed; otherwise rollback Firebase user)
        try {
          await _createUserProfile(user, displayName);
        } catch (e, stackTrace) {
          debugPrint('[FirebaseAuthService] Profile creation failed, rolling back Firebase user: $e');
          debugPrint('[FirebaseAuthService] Stack trace: $stackTrace');
          await _safeDeleteFirebaseUser(user);
          await _firebaseAuth.signOut();
          rethrow;
        }

        // Send email verification only after successful profile creation
        await user.sendEmailVerification();
        debugPrint('[FirebaseAuthService] Email verification sent to: $email');

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
        // Ensure user profile exists (create only if missing)
        await _ensureUserProfileExists(user);
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


  /// Ensure user profile exists/updated via Edge Function (idempotent)
  Future<void> _ensureUserProfileExists(User user) async {
    try {
      debugPrint('[FirebaseAuthService] Ensuring user profile via Edge Function (idempotent)...');
      final response = await _supabase.functions.invoke(
        'create-user-profile',
        body: {
          'firebase_uid': user.uid,
          'email': user.email,
          'full_name': user.displayName,
          'email_verified': user.emailVerified,
        },
      );
      debugPrint('[FirebaseAuthService] Ensure profile response: ${response.status} - ${response.data}');
    } catch (e, stackTrace) {
      debugPrint('[FirebaseAuthService] Error ensuring user profile exists: $e');
      debugPrint('[FirebaseAuthService] Stack trace: $stackTrace');
      // Non-fatal on login
    }
  }

  /// Delete the just-created Firebase user safely (best-effort)
  Future<void> _safeDeleteFirebaseUser(User user) async {
    try {
      debugPrint('[FirebaseAuthService] Deleting Firebase user ${user.email} (UID=${user.uid}) due to profile creation failure...');
      await user.delete();
      debugPrint('[FirebaseAuthService] Firebase user deleted successfully');
    } on FirebaseAuthException catch (e) {
      debugPrint('[FirebaseAuthService] Failed to delete Firebase user: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('[FirebaseAuthService] Unexpected error deleting Firebase user: $e');
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

      // Update Supabase profile via Edge Function (idempotent)
      final response = await _supabase.functions.invoke(
        'create-user-profile',
        body: {
          'firebase_uid': user.uid,
          'email': user.email,
          'full_name': displayName ?? user.displayName,
          'email_verified': user.emailVerified,
        },
      );
      debugPrint('[FirebaseAuthService] Edge update response: ${response.status} - ${response.data}');
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
