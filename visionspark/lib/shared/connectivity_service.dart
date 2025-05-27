import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateStatus);
    _checkInternet();
  }

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  late StreamSubscription _connectivitySubscription;
  bool _isOnline = true;

  Stream<bool> get onStatusChange => _controller.stream;
  bool get isOnline => _isOnline;

  void _updateStatus(ConnectivityResult result) async {
    await _checkInternet();
  }

  Future<void> _checkInternet() async {
    final hasConnection = await InternetConnectionChecker().hasConnection;
    if (_isOnline != hasConnection) {
      _isOnline = hasConnection;
      _controller.add(_isOnline);
    }
  }

  Future<void> retryCheck() async {
    await _checkInternet();
  }

  void dispose() {
    _connectivitySubscription.cancel();
    _controller.close();
  }
} 