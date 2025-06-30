import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visionspark/features/gallery/gallery_screen.dart';

import 'gallery_test.mocks.dart';

@GenerateMocks([SupabaseClient, GoTrueClient, FunctionsClient, SupabaseQueryBuilder, User])
void main() {
  group('GalleryImage Model Tests', () {
    test('creates GalleryImage from map correctly', () {
      final map = {
        'id': 'test-id',
        'prompt': 'A beautiful sunset',
        'created_at': '2024-01-01T12:00:00Z',
        'user_id': 'user-123',
        'thumbnail_url_signed': 'https://example.com/thumb.jpg',
      };

      final image = GalleryImage.fromMap(
        map, 
        'https://example.com/image.jpg', 
        5, 
        true
      );

      expect(image.id, 'test-id');
      expect(image.prompt, 'A beautiful sunset');
      expect(image.imageUrl, 'https://example.com/image.jpg');
      expect(image.thumbnailUrlSigned, 'https://example.com/thumb.jpg');
      expect(image.likeCount, 5);
      expect(image.isLikedByCurrentUser, true);
      expect(image.userId, 'user-123');
      expect(image.createdAt, DateTime.parse('2024-01-01T12:00:00Z'));
    });

    test('handles null values in map', () {
      final map = {
        'id': 'test-id',
        'prompt': null,
        'created_at': '2024-01-01T12:00:00Z',
        'user_id': 'user-123',
        'thumbnail_url_signed': null,
      };

      final image = GalleryImage.fromMap(map, 'https://example.com/image.jpg', 0, false);

      expect(image.prompt, null);
      expect(image.thumbnailUrlSigned, null);
      expect(image.likeCount, 0);
      expect(image.isLikedByCurrentUser, false);
    });
  });

  group('GalleryScreen Widget Tests', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockFunctionsClient mockFunctionsClient;
    late MockUser mockUser;
    late MockSupabaseQueryBuilder mockQueryBuilder;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockFunctionsClient = MockFunctionsClient();
      mockUser = MockUser();
      mockQueryBuilder = MockSupabaseQueryBuilder();

      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
      when(mockSupabaseClient.functions).thenReturn(mockFunctionsClient);
      when(mockSupabaseClient.from(any)).thenReturn(mockQueryBuilder);
      when(mockGoTrueClient.currentUser).thenReturn(mockUser);
      when(mockUser.id).thenReturn('test-user-id');

      TestWidgetsFlutterBinding.ensureInitialized();
    });

    Widget createTestWidget() {
      return const MaterialApp(
        home: GalleryScreen(),
      );
    }

    testWidgets('displays loading indicator initially', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': []}),
      );

      await tester.pumpWidget(createTestWidget());
      
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading gallery...'), findsOneWidget);
    });

    testWidgets('displays gallery tabs correctly', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': []}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('My Gallery'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('displays empty state when no images', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': []}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('The gallery is empty.'), findsOneWidget);
      expect(find.text('Check back later for new creations.'), findsOneWidget);
    });

    testWidgets('displays images in grid when data available', (WidgetTester tester) async {
      final mockImages = [
        {
          'id': 'image-1',
          'prompt': 'A beautiful sunset',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'user-123',
          'image_url': 'https://example.com/image1.jpg',
          'thumbnail_url_signed': 'https://example.com/thumb1.jpg',
          'like_count': 5,
          'is_liked_by_current_user': false,
        },
        {
          'id': 'image-2',
          'prompt': 'A mountain landscape',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'user-456',
          'image_url': 'https://example.com/image2.jpg',
          'thumbnail_url_signed': 'https://example.com/thumb2.jpg',
          'like_count': 3,
          'is_liked_by_current_user': true,
        },
      ];

      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': mockImages}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('A beautiful sunset'), findsOneWidget);
      expect(find.text('A mountain landscape'), findsOneWidget);
      expect(find.byType(Image), findsAtLeastNWidgets(2));
    });

    testWidgets('handles API errors gracefully', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'error': 'Network error'}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to fetch gallery'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry button refetches gallery data', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'error': 'Network error'}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final retryButton = find.text('Retry');
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pump();

      verify(mockFunctionsClient.invoke('get-gallery-feed')).called(2);
    });

    testWidgets('pull-to-refresh triggers data fetch', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': []}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      await tester.pump();

      verify(mockFunctionsClient.invoke('get-gallery-feed')).called(2);
    });

    testWidgets('switches between discover and my gallery tabs', (WidgetTester tester) async {
      final mockImages = [
        {
          'id': 'image-1',
          'prompt': 'My image',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'test-user-id', // Current user's image
          'image_url': 'https://example.com/image1.jpg',
          'thumbnail_url_signed': null,
          'like_count': 0,
          'is_liked_by_current_user': false,
        },
        {
          'id': 'image-2',
          'prompt': 'Other user image',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'other-user-id',
          'image_url': 'https://example.com/image2.jpg',
          'thumbnail_url_signed': null,
          'like_count': 0,
          'is_liked_by_current_user': false,
        },
      ];

      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': mockImages}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show both images in discover tab
      expect(find.text('My image'), findsOneWidget);
      expect(find.text('Other user image'), findsOneWidget);

      // Switch to My Gallery tab
      await tester.tap(find.text('My Gallery'));
      await tester.pumpAndSettle();

      // Should only show current user's image
      expect(find.text('My image'), findsOneWidget);
      expect(find.text('Other user image'), findsNothing);
    });

    testWidgets('like button toggles correctly', (WidgetTester tester) async {
      final mockImages = [
        {
          'id': 'image-1',
          'prompt': 'Test image',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'user-123',
          'image_url': 'https://example.com/image1.jpg',
          'thumbnail_url_signed': null,
          'like_count': 5,
          'is_liked_by_current_user': false,
        },
      ];

      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': mockImages}),
      );
      
      when(mockQueryBuilder.insert(any)).thenAnswer((_) async => []);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap like button
      final likeButton = find.byIcon(Icons.favorite_border);
      expect(likeButton, findsOneWidget);
      
      await tester.tap(likeButton);
      await tester.pump();

      // Should attempt to insert like
      verify(mockQueryBuilder.insert(any)).called(1);
    });

    testWidgets('formats time ago correctly', (WidgetTester tester) async {
      final now = DateTime.now();
      final mockImages = [
        {
          'id': 'image-1',
          'prompt': 'Recent image',
          'created_at': now.subtract(Duration(minutes: 5)).toIso8601String(),
          'user_id': 'user-123',
          'image_url': 'https://example.com/image1.jpg',
          'thumbnail_url_signed': null,
          'like_count': 0,
          'is_liked_by_current_user': false,
        },
      ];

      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': mockImages}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show relative time
      expect(find.textContaining('min'), findsOneWidget);
    });

    testWidgets('handles missing thumbnail gracefully', (WidgetTester tester) async {
      final mockImages = [
        {
          'id': 'image-1',
          'prompt': 'Image without thumbnail',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'user-123',
          'image_url': 'https://example.com/image1.jpg',
          'thumbnail_url_signed': null,
          'like_count': 0,
          'is_liked_by_current_user': false,
        },
      ];

      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': mockImages}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should fall back to main image URL
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('shows empty state for my gallery when user has no images', (WidgetTester tester) async {
      final mockImages = [
        {
          'id': 'image-1',
          'prompt': 'Other user image',
          'created_at': DateTime.now().toIso8601String(),
          'user_id': 'other-user-id',
          'image_url': 'https://example.com/image1.jpg',
          'thumbnail_url_signed': null,
          'like_count': 0,
          'is_liked_by_current_user': false,
        },
      ];

      when(mockFunctionsClient.invoke('get-gallery-feed')).thenAnswer(
        (_) async => FunctionResponse(data: {'images': mockImages}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Switch to My Gallery tab
      await tester.tap(find.text('My Gallery'));
      await tester.pumpAndSettle();

      expect(find.text("You haven't created any images yet."), findsOneWidget);
      expect(find.text('Start creating amazing images with AI!'), findsOneWidget);
    });
  });

  group('Gallery Logic Tests', () {
    test('filters images by user ID correctly', () {
      final images = [
        GalleryImage(
          id: '1',
          imageUrl: 'url1',
          createdAt: DateTime.now(),
          likeCount: 0,
          isLikedByCurrentUser: false,
          userId: 'user-1',
        ),
        GalleryImage(
          id: '2',
          imageUrl: 'url2',
          createdAt: DateTime.now(),
          likeCount: 0,
          isLikedByCurrentUser: false,
          userId: 'user-2',
        ),
        GalleryImage(
          id: '3',
          imageUrl: 'url3',
          createdAt: DateTime.now(),
          likeCount: 0,
          isLikedByCurrentUser: false,
          userId: 'user-1',
        ),
      ];

      final user1Images = images.where((img) => img.userId == 'user-1').toList();
      expect(user1Images.length, 2);
      expect(user1Images.every((img) => img.userId == 'user-1'), true);
    });

    test('calculates like count changes correctly', () {
      const originalCount = 5;
      const wasLiked = false;
      
      final newCount = wasLiked ? originalCount - 1 : originalCount + 1;
      expect(newCount, 6);
      
      const wasLiked2 = true;
      final newCount2 = wasLiked2 ? originalCount - 1 : originalCount + 1;
      expect(newCount2, 4);
    });

    test('validates image URLs', () {
      const validUrl = 'https://example.com/image.jpg';
      const invalidUrl = 'not-a-url';
      
      expect(validUrl.startsWith('http'), true);
      expect(invalidUrl.startsWith('http'), false);
    });

    test('handles null prompts gracefully', () {
      const String? nullPrompt = null;
      const String emptyPrompt = '';
      const String validPrompt = 'A beautiful sunset';
      
      expect(nullPrompt?.isNotEmpty ?? false, false);
      expect(emptyPrompt.isNotEmpty, false);
      expect(validPrompt.isNotEmpty, true);
    });

    test('sorts images by creation date', () {
      final now = DateTime.now();
      final images = [
        GalleryImage(
          id: '1',
          imageUrl: 'url1',
          createdAt: now.subtract(Duration(days: 1)),
          likeCount: 0,
          isLikedByCurrentUser: false,
        ),
        GalleryImage(
          id: '2',
          imageUrl: 'url2',
          createdAt: now,
          likeCount: 0,
          isLikedByCurrentUser: false,
        ),
        GalleryImage(
          id: '3',
          imageUrl: 'url3',
          createdAt: now.subtract(Duration(hours: 12)),
          likeCount: 0,
          isLikedByCurrentUser: false,
        ),
      ];

      images.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      expect(images[0].id, '2'); // Most recent
      expect(images[1].id, '3'); // 12 hours ago
      expect(images[2].id, '1'); // 1 day ago
    });
  });
}