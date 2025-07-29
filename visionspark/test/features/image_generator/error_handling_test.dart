import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Image Generation Error Handling', () {
    test('detects content policy violation in API response', () {
      final data = {
        'error': 'Your request was rejected as a result of our safety system.',
        'details': {
          'type': 'image_generation_user_error',
          'code': 'content_policy_violation',
          'message': 'Your request was rejected as a result of our safety system.'
        }
      };
      
      final errorMessage = getApiErrorMessage(data);
      
      expect(errorMessage, contains('Content Policy Violation'));
      expect(errorMessage, contains('safety system'));
    });

    test('detects content policy violation in error string', () {
      final data = {
        'error': 'Your request was rejected as a result of our safety system.'
      };
      
      final errorMessage = getApiErrorMessage(data);
      
      expect(errorMessage, contains('Content Policy Violation'));
      expect(errorMessage, contains('safety system'));
    });

    test('handles FunctionException with content policy violation', () {
      final exception = FunctionException(
        status: 400,
        details: {
          'error': {
            'type': 'image_generation_user_error',
            'code': 'content_policy_violation',
            'message': 'Your request was rejected as a result of our safety system.'
          }
        },
        reasonPhrase: 'Bad Request',
      );
      
      final errorMessage = getImageGenerationErrorMessage(exception);
      
      expect(errorMessage, contains('Content Policy Violation'));
      expect(errorMessage, contains('safety system'));
    });

    test('handles FunctionException with safety system message', () {
      final exception = FunctionException(
        status: 400,
        details: {
          'error': 'Your request was rejected as a result of our safety system.'
        },
        reasonPhrase: 'Bad Request',
      );
      
      final errorMessage = getImageGenerationErrorMessage(exception);
      
      expect(errorMessage, contains('Content Policy Violation'));
      expect(errorMessage, contains('safety system'));
    });

    test('handles generic FunctionException', () {
      final exception = FunctionException(
        status: 500,
        details: {'error': 'Internal server error'},
        reasonPhrase: 'Internal Server Error',
      );

      final errorMessage = getImageGenerationErrorMessage(exception);

      // The function should return the direct error message since it's user-friendly
      expect(errorMessage, equals('Internal server error'));
    });

    test('handles generic exception', () {
      final exception = Exception('Network error');
      
      final errorMessage = getImageGenerationErrorMessage(exception);
      
      expect(errorMessage, contains('An unexpected error occurred during image generation'));
    });

    test('returns user-friendly error for valid API error', () {
      final data = {
        'error': 'Generation limit reached'
      };
      
      final errorMessage = getApiErrorMessage(data);
      
      expect(errorMessage, equals('Generation limit reached'));
    });

    test('returns default message for empty error', () {
      final data = {
        'error': null
      };
      
      final errorMessage = getApiErrorMessage(data);
      
      expect(errorMessage, contains('An unexpected error occurred'));
    });
  });
}

/// Helper function to test API error message parsing
String getApiErrorMessage(Map<String, dynamic> data) {
  final error = data['error'];
  if (error == null) return 'An unexpected error occurred during image generation. Please try again.';
  
  final errorString = error.toString();
  
  // Check for content policy violations in the error message
  if (errorString.toLowerCase().contains('safety system') || 
      errorString.toLowerCase().contains('content policy')) {
    return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
  }
  
  // Check for details object with more specific error information
  final details = data['details'];
  if (details != null && details is Map<String, dynamic>) {
    final errorType = details['type'];
    final errorCode = details['code'];
    
    if (errorType == 'image_generation_user_error' && 
        errorCode == 'content_policy_violation') {
      return 'Content Policy Violation: Your prompt contains content that is not allowed by our safety system. Please try rephrasing your prompt to avoid violent, harmful, or inappropriate content.';
    }
  }
  
  // Return the original error message if it's user-friendly
  if (errorString.isNotEmpty && !errorString.toLowerCase().contains('unexpected')) {
    return errorString;
  }
  
  return 'An unexpected error occurred during image generation. Please try again.';
}

/// Helper function to test image generation error message parsing
String getImageGenerationErrorMessage(dynamic error) {
  // Handle FunctionException from Supabase
  if (error is FunctionException) {
    final details = error.details;
    
    // Check if it's a content policy violation
    if (details != null && details is Map<String, dynamic>) {
      final errorDetails = details['error'];
      if (errorDetails != null && errorDetails is Map<String, dynamic>) {
        final errorType = errorDetails['type'];
        final errorCode = errorDetails['code'];
        final errorMessage = errorDetails['message'] ?? '';
        
        // Check for content policy violations
        if (errorType == 'image_generation_user_error' && 
            errorCode == 'content_policy_violation') {
          return 'Content Policy Violation: Your prompt contains content that is not allowed by our safety system. Please try rephrasing your prompt to avoid violent, harmful, or inappropriate content.';
        }
        
        // Check for safety system rejection in message
        if (errorMessage.toLowerCase().contains('safety system') || 
            errorMessage.toLowerCase().contains('content policy')) {
          return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
        }
      }
      
      // Check for error message directly in details
      final directError = details['error'];
      if (directError is String) {
        if (directError.toLowerCase().contains('safety system') || 
            directError.toLowerCase().contains('content policy')) {
          return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
        }
        // Return the direct error message if it's user-friendly
        if (directError.isNotEmpty && !directError.toLowerCase().contains('unexpected')) {
          return directError;
        }
      }
    }
    
    // Handle other FunctionException cases
    if (error.reasonPhrase != null && error.reasonPhrase!.isNotEmpty) {
      return 'Generation failed: ${error.reasonPhrase}';
    }
  }
  
  // Handle other exception types
  final errorString = error.toString();
  if (errorString.toLowerCase().contains('safety system') || 
      errorString.toLowerCase().contains('content policy')) {
    return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
  }
  
  // Default fallback message
  return 'An unexpected error occurred during image generation. Please try again.';
}
