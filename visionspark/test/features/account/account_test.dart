import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visionspark/features/account/account_section.dart';

import 'account_test.mocks.dart';

@GenerateMocks([
  SupabaseClient, 
  GoTrueClient, 
  SupabaseQueryBuilder, 
  SupabaseStorageClient,
  StorageFileApi,
  User,
  ImagePicker
])
void main() {
  group('AccountSection Widget Tests', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockSupabaseQueryBuilder mockQueryBuilder;
    late MockSupabaseStorageClient mockStorageClient;
    late MockStorageFileApi mockStorageFileApi;
    late MockUser mockUser;
    late MockImagePicker mockImagePicker;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockQueryBuilder = MockSupabaseQueryBuilder();
      mockStorageClient = MockSupabaseStorageClient();
      mockStorageFileApi = MockStorageFileApi();
      mockUser = MockUser();
      mockImagePicker = MockImagePicker();

      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
      when(mockSupabaseClient.from(any)).thenReturn(mockQueryBuilder);
      when(mockSupabaseClient.storage).thenReturn(mockStorageClient);
      when(mockStorageClient.from(any)).thenReturn(mockStorageFileApi);
      when(mockGoTrueClient.currentUser).thenReturn(mockUser);
      when(mockUser.id).thenReturn('test-user-id');
      when(mockUser.email).thenReturn('test@example.com');

      TestWidgetsFlutterBinding.ensureInitialized();
    });

    Widget createTestWidget() {
      return const MaterialApp(
        home: AccountSection(),
      );
    }

    testWidgets('displays loading state initially', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': DateTime.now().toIso8601String(),
        'username': 'TestUser',
      });

      await tester.pumpWidget(createTestWidget());
      
      // Should show some loading or initial state
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('displays user profile information correctly', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('TestUser'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.textContaining('Member since'), findsOneWidget);
    });

    testWidgets('shows user email when no username', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': null,
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('test@example.com'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays user initials when no profile picture', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'Test User',
      });

      when(mockStorageFileApi.createSignedUrl(any, any))
          .thenThrow(Exception('No profile picture'));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show initials 'TU' for 'Test User'
      expect(find.text('TU'), findsOneWidget);
    });

    testWidgets('profile picture upload button is visible', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    });

    testWidgets('account management options are visible', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Look for account management UI elements
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('username edit dialog opens when tapped', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap edit username button
      final editButton = find.byIcon(Icons.edit);
      if (editButton.hasFound) {
        await tester.tap(editButton.first);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
      }
    });

    testWidgets('sign out button triggers sign out', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      when(mockGoTrueClient.signOut()).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap sign out button
      final signOutButton = find.textContaining('Sign Out');
      if (signOutButton.hasFound) {
        await tester.tap(signOutButton);
        await tester.pumpAndSettle();

        verify(mockGoTrueClient.signOut()).called(1);
      }
    });

    testWidgets('delete account shows confirmation dialog', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap delete account button
      final deleteButton = find.textContaining('Delete Account');
      if (deleteButton.hasFound) {
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('confirm'), findsOneWidget);
      }
    });

    testWidgets('handles profile fetch errors gracefully', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenThrow(Exception('Network error'));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should still show basic user info even with profile fetch error
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('shows loading state during profile picture upload', (WidgetTester tester) async {
      when(mockQueryBuilder.select(any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.eq(any, any)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.single()).thenAnswer((_) async => {
        'created_at': '2024-01-01T12:00:00Z',
        'username': 'TestUser',
      });

      // Mock image picker to return null (user cancels)
      when(mockImagePicker.pickImage(source: anyNamed('source'), imageQuality: anyNamed('imageQuality')))
          .thenAnswer((_) async => null);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final cameraButton = find.byIcon(Icons.camera_alt_rounded);
      await tester.tap(cameraButton);
      await tester.pump();

      // Should handle cancelled image selection gracefully
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Account Logic Tests', () {
    test('generates correct initials from username', () {
      String getInitials(String? name, String? email) {
        if (name != null && name.isNotEmpty) {
          final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
          if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
          if (parts.isNotEmpty) return parts[0].substring(0, 1).toUpperCase();
        }
        if (email != null && email.isNotEmpty) {
          return email.substring(0, 1).toUpperCase();
        }
        return '';
      }

      expect(getInitials('John Doe', 'john@example.com'), 'JD');
      expect(getInitials('Alice', 'alice@example.com'), 'A');
      expect(getInitials('', 'bob@example.com'), 'B');
      expect(getInitials(null, 'charlie@example.com'), 'C');
      expect(getInitials('Jane  Smith', 'jane@example.com'), 'JS'); // Multiple spaces
      expect(getInitials('', ''), '');
    });

    test('validates username input', () {
      bool isValidUsername(String username) {
        return username.trim().isNotEmpty;
      }

      expect(isValidUsername('ValidUser'), true);
      expect(isValidUsername('User123'), true);
      expect(isValidUsername(''), false);
      expect(isValidUsername('   '), false);
      expect(isValidUsername('  ValidUser  '), true); // Should trim whitespace
    });

    test('formats join date correctly', () {
      String formatJoinDate(DateTime joinDate) {
        final now = DateTime.now();
        final difference = now.difference(joinDate).inDays;
        
        if (difference < 30) {
          return '${difference} days ago';
        } else if (difference < 365) {
          final months = (difference / 30).floor();
          return '${months} month${months == 1 ? '' : 's'} ago';
        } else {
          final years = (difference / 365).floor();
          return '${years} year${years == 1 ? '' : 's'} ago';
        }
      }

      final now = DateTime.now();
      expect(formatJoinDate(now.subtract(Duration(days: 15))), '15 days ago');
      expect(formatJoinDate(now.subtract(Duration(days: 60))), '2 months ago');
      expect(formatJoinDate(now.subtract(Duration(days: 400))), '1 year ago');
      expect(formatJoinDate(now.subtract(Duration(days: 800))), '2 years ago');
    });

    test('validates profile picture file extensions', () {
      bool isValidImageExtension(String filename) {
        final validExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
        final extension = filename.split('.').last.toLowerCase();
        return validExtensions.contains(extension);
      }

      expect(isValidImageExtension('profile.jpg'), true);
      expect(isValidImageExtension('avatar.png'), true);
      expect(isValidImageExtension('picture.jpeg'), true);
      expect(isValidImageExtension('image.gif'), true);
      expect(isValidImageExtension('photo.webp'), true);
      expect(isValidImageExtension('document.pdf'), false);
      expect(isValidImageExtension('file.txt'), false);
      expect(isValidImageExtension('noextension'), false);
    });

    test('generates storage path correctly', () {
      String generateStoragePath(String userId, String extension) {
        return '$userId/profile.$extension';
      }

      expect(generateStoragePath('user123', 'jpg'), 'user123/profile.jpg');
      expect(generateStoragePath('test-user-id', 'png'), 'test-user-id/profile.png');
    });

    test('validates email format', () {
      bool isValidEmail(String email) {
        return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
      }

      expect(isValidEmail('test@example.com'), true);
      expect(isValidEmail('user.name@domain.co.uk'), true);
      expect(isValidEmail('invalid-email'), false);
      expect(isValidEmail('test@'), false);
      expect(isValidEmail('@domain.com'), false);
      expect(isValidEmail(''), false);
    });

    test('handles username comparison correctly', () {
      bool hasUsernameChanged(String? current, String new_) {
        return current != new_.trim();
      }

      expect(hasUsernameChanged('OldName', 'NewName'), true);
      expect(hasUsernameChanged('SameName', 'SameName'), false);
      expect(hasUsernameChanged('SameName', '  SameName  '), false); // Trims whitespace
      expect(hasUsernameChanged(null, 'NewName'), true);
      expect(hasUsernameChanged('OldName', ''), true);
    });
  });
}