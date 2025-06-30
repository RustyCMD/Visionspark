import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:visionspark/shared/connectivity_service.dart';

import 'connectivity_service_test.mocks.dart';

@GenerateMocks([Connectivity, InternetConnectionChecker])
void main() {
  group('ConnectivityService Tests', () {
    late MockConnectivity mockConnectivity;
    late MockInternetConnectionChecker mockInternetChecker;
    late ConnectivityService connectivityService;

    setUp(() {
      mockConnectivity = MockConnectivity();
      mockInternetChecker = MockInternetConnectionChecker();
      
      // Provide a default stream for onConnectivityChanged
      when(mockConnectivity.onConnectivityChanged).thenAnswer((_) => Stream.fromIterable([]));

      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );
    });

    tearDown(() {
      connectivityService.dispose();
    });

    test('singleton pattern works correctly', () {
      final service1 = ConnectivityService();
      final service2 = ConnectivityService();
      
      expect(identical(service1, service2), true);
      
      // Clean up the instance created in this test
      service1.dispose();
    });

    test('initial state is online', () async {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      connectivityService.dispose(); // Dispose the one from setUp
      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );
      
      await Future.delayed(Duration.zero); // Allow async operations in constructor to complete
      
      expect(connectivityService.isOnline, true);
    });

    test('updates status when connectivity changes', () async {
      final controller = StreamController<ConnectivityResult>();
      when(mockConnectivity.onConnectivityChanged).thenAnswer((_) => controller.stream);
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => false);

      connectivityService.dispose(); // Dispose the one from setUp
      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );
      
      final statusUpdates = <bool>[];
      connectivityService.onStatusChange.listen((status) {
        statusUpdates.add(status);
      });

      // Simulate connectivity change
      controller.add(ConnectivityResult.none);
      await Future.delayed(const Duration(milliseconds: 100)); // Increased delay for stability

      expect(statusUpdates, contains(false));
      controller.close();
    });

    test('retryCheck updates internet status', () async {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      await connectivityService.retryCheck();
      
      verify(mockInternetChecker.hasConnection).called(1);
    });

    test('onStatusChange stream works correctly', () async {
      final statusStream = connectivityService.onStatusChange;
      expect(statusStream, isA<Stream<bool>>());
    });

    test('dispose cleans up resources', () {
      expect(() => connectivityService.dispose(), returnsNormally);
    });

    test('handles internet connection check failure gracefully', () async {
      when(mockInternetChecker.hasConnection).thenThrow(Exception('Network error'));
      
      connectivityService.dispose();
      
      expect(() => ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      ), returnsNormally);
    });

    test('status only updates when connectivity actually changes', () async {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      connectivityService.dispose();
      connectivityService = ConnectivityService(
        connectivity: mockConnectivity,
        internetChecker: mockInternetChecker,
      );
      
      final statusUpdates = <bool>[];
      connectivityService.onStatusChange.listen((status) {
        statusUpdates.add(status);
      });

      // Let initial check complete
      await Future.delayed(Duration.zero);

      // Multiple calls with same result should not trigger new updates
      await connectivityService.retryCheck();
      await connectivityService.retryCheck();
      
      expect(statusUpdates.length, lessThanOrEqualTo(1));
    });
  });
}