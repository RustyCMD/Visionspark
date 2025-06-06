import 'package:flutter/material.dart';

void showErrorSnackbar(BuildContext context, String message) {
  if (!context.mounted) return; // Check if the context is still valid
  ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove existing snackbar if any
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating, // Optional: for a floating snackbar
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // Optional: for rounded corners
      margin: const EdgeInsets.all(10), // Optional: if using floating behavior
    ),
  );
}

void showSuccessSnackbar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.green, // Or use Theme.of(context).colorScheme.secondary or a success color
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(10),
    ),
  );
} 