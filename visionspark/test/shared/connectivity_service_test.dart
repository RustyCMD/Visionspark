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
      
      // Reset singleton instance for testing
      ConnectivityService.instance = null;
    });

    tearDown(() {
      connectivityService.dispose();
    });

    test('singleton pattern works correctly', () {
      final service1 = ConnectivityService();
      final service2 = ConnectivityService();
      
      expect(identical(service1, service2), true);
    });

    test('initial state is online', () {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      connectivityService = ConnectivityService();
      
      expect(connectivityService.isOnline, true);
    });

    test('updates status when connectivity changes', () async {
      final controller = StreamController<ConnectivityResult>();
      when(mockConnectivity.onConnectivityChanged).thenAnswer((_) => controller.stream);
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => false);

      connectivityService = ConnectivityService();
      
      final statusUpdates = <bool>[];
      connectivityService.onStatusChange.listen((status) {
        statusUpdates.add(status);
      });

      // Simulate connectivity change
      controller.add(ConnectivityResult.none);
      await Future.delayed(Duration(milliseconds: 100));

      expect(statusUpdates, contains(false));
      controller.close();
    });

    test('retryCheck updates internet status', () async {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      connectivityService = ConnectivityService();
      
      await connectivityService.retryCheck();
      
      verify(mockInternetChecker.hasConnection).called(1);
    });

    test('onStatusChange stream works correctly', () async {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      connectivityService = ConnectivityService();
      
      final statusStream = connectivityService.onStatusChange;
      expect(statusStream, isA<Stream<bool>>());
    });

    test('dispose cleans up resources', () {
      connectivityService = ConnectivityService();
      
      expect(() => connectivityService.dispose(), returnsNormally);
    });

    test('handles internet connection check failure gracefully', () async {
      when(mockInternetChecker.hasConnection).thenThrow(Exception('Network error'));
      
      expect(() => ConnectivityService(), returnsNormally);
    });

    test('status only updates when connectivity actually changes', () async {
      when(mockInternetChecker.hasConnection).thenAnswer((_) async => true);
      
      connectivityService = ConnectivityService();
      
      final statusUpdates = <bool>[];
      connectivityService.onStatusChange.listen((status) {
        statusUpdates.add(status);
      });

      // Multiple calls with same result should not trigger updates
      await connectivityService.retryCheck();
      await connectivityService.retryCheck();
      
      expect(statusUpdates.length, lessThanOrEqualTo(1));
    });
  });
}