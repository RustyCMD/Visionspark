import 'package:email_validator/email_validator.dart';

class FormValidators {
  /// Validate email address
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email address is required';
    }
    
    final email = value.trim();
    if (!EmailValidator.validate(email)) {
      return 'Please enter a valid email address';
    }
    
    return null;
  }

  /// Validate password with strength requirements
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }

    // Check for at least one uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }

    // Check for at least one lowercase letter
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }

    // Check for at least one digit
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }

    // Check for at least one special character
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain at least one special character';
    }

    return null;
  }

  /// Validate password confirmation
  static String? validatePasswordConfirmation(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != password) {
      return 'Passwords do not match';
    }

    return null;
  }

  /// Validate display name
  static String? validateDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name is required';
    }

    final name = value.trim();
    if (name.length < 2) {
      return 'Display name must be at least 2 characters long';
    }

    if (name.length > 50) {
      return 'Display name must be less than 50 characters';
    }

    // Check for valid characters (letters, numbers, spaces, hyphens, apostrophes)
    if (!RegExp(r"^[a-zA-Z0-9\s\-']+$").hasMatch(name)) {
      return 'Display name can only contain letters, numbers, spaces, hyphens, and apostrophes';
    }

    return null;
  }

  /// Get password strength level (0-4)
  static int getPasswordStrength(String password) {
    if (password.isEmpty) return 0;

    int strength = 0;

    // Length check
    if (password.length >= 8) strength++;
    if (password.length >= 12) strength++;

    // Character variety checks
    if (RegExp(r'[a-z]').hasMatch(password)) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9]').hasMatch(password)) strength++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;

    // Cap at 4
    return strength > 4 ? 4 : strength;
  }

  /// Get password strength text
  static String getPasswordStrengthText(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return 'Very Weak';
      case 2:
        return 'Weak';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      default:
        return 'Very Weak';
    }
  }

  /// Get password strength color
  static int getPasswordStrengthColor(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return 0xFFD32F2F; // Red
      case 2:
        return 0xFFFF9800; // Orange
      case 3:
        return 0xFF388E3C; // Green
      case 4:
        return 0xFF1976D2; // Blue
      default:
        return 0xFFD32F2F; // Red
    }
  }

  /// Check if password meets minimum requirements
  static bool isPasswordValid(String password) {
    return validatePassword(password) == null;
  }

  /// Check if email is valid
  static bool isEmailValid(String email) {
    return validateEmail(email) == null;
  }

  /// Sanitize input by trimming whitespace
  static String sanitizeInput(String? input) {
    return input?.trim() ?? '';
  }

  /// Validate form fields for registration
  static Map<String, String?> validateRegistrationForm({
    required String email,
    required String password,
    required String confirmPassword,
    required String displayName,
  }) {
    return {
      'email': validateEmail(email),
      'password': validatePassword(password),
      'confirmPassword': validatePasswordConfirmation(confirmPassword, password),
      'displayName': validateDisplayName(displayName),
    };
  }

  /// Validate form fields for login
  static Map<String, String?> validateLoginForm({
    required String email,
    required String password,
  }) {
    return {
      'email': validateEmail(email),
      'password': password.isEmpty ? 'Password is required' : null,
    };
  }

  /// Validate form fields for password reset
  static Map<String, String?> validatePasswordResetForm({
    required String email,
  }) {
    return {
      'email': validateEmail(email),
    };
  }

  /// Check if any validation errors exist
  static bool hasValidationErrors(Map<String, String?> errors) {
    return errors.values.any((error) => error != null);
  }

  /// Get first validation error message
  static String? getFirstError(Map<String, String?> errors) {
    for (final error in errors.values) {
      if (error != null) return error;
    }
    return null;
  }
}

/// Extension methods for String validation
extension StringValidation on String? {
  /// Check if string is null or empty
  bool get isNullOrEmpty => this == null || this!.isEmpty;

  /// Check if string is null, empty, or only whitespace
  bool get isNullOrWhitespace => this == null || this!.trim().isEmpty;

  /// Get trimmed string or empty string if null
  String get trimmedOrEmpty => this?.trim() ?? '';
}
