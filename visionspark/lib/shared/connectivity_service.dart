import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class ConnectivityService {
  static ConnectivityService? _instance;

  final Connectivity _connectivity;
  final InternetConnectionChecker _internetChecker;

  factory ConnectivityService({
    Connectivity? connectivity,
    InternetConnectionChecker? internetChecker,
  }) {
    return _instance ??= ConnectivityService._internal(
      connectivity: connectivity,
      internetChecker: internetChecker,
    );
  }

  ConnectivityService._internal({
    Connectivity? connectivity,
    InternetConnectionChecker? internetChecker,
  })  : _connectivity = connectivity ?? Connectivity(),
        _internetChecker = internetChecker ?? InternetConnectionChecker() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
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
    final hasConnection = await _internetChecker.hasConnection;
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
    _instance = null;
  }
} 