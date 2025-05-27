import 'package:flutter/material.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Subscriptions',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
} 