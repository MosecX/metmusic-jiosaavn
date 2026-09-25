import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'jiosaavn_service.dart';

class ConnectivityService extends ChangeNotifier {
  final Dio _dio;

  bool _hasNetwork = true;
  bool _canReachApi = true;
  bool _checking = false;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _results = [];

  ConnectivityService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          headers: {'Accept': 'application/json'},
        ));

  bool get hasNetwork => _hasNetwork;

  bool get canReachApi => _canReachApi;

  /// True only when the device genuinely has an internet connection (a real
  /// network interface is up).
  ///
  /// This deliberately does NOT depend on [canReachApi]: playback streams come
  /// from the JioSaavn CDN and must not be gated by the API proxy's health.
  /// The JioSaavn API proxy can occasionally be slow/down, which previously
  /// made the app report "no internet" and blocked every track even though the
  /// network worked fine. API reachability is shown as an informational
  /// indicator in Settings.
  bool get isOnline => _hasNetwork;

  /// Human-readable label of the active connection (Wi-Fi, mobile data, ...).
  String get connectionTypeLabel {
    if (!_hasNetwork) return 'Sin conexión';
    final types =
        _results.where((r) => r != ConnectivityResult.none).toList();
    if (types.isEmpty) return 'Conectado';
    for (final r in types) {
      switch (r.name) {
        case 'wifi':
          return 'Wi-Fi';
        case 'ethernet':
          return 'Ethernet';
        case 'mobile':
          return 'Datos móviles';
        case 'vpn':
          return 'VPN';
        case 'bluetooth':
          return 'Bluetooth';
        case 'other':
          return 'Red';
      }
    }
    return 'Conectado';
  }

  IconData get connectionIcon {
    final types = _results.where((r) => r != ConnectivityResult.none).toList();
    if (types.isEmpty) return Icons.signal_wifi_off;
    final r = types.first;
    switch (r.name) {
      case 'wifi':
        return Icons.wifi;
      case 'mobile':
        return Icons.signal_cellular_4_bar;
      case 'ethernet':
        return Icons.lan;
      case 'vpn':
        return Icons.vpn_lock;
      case 'bluetooth':
        return Icons.bluetooth;
      default:
        return Icons.network_check;
    }
  }

  Future<void> start() async {
    await _initNetworkListener();
    await _checkReachability();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkReachability(),
    );
  }

  Future<void> _initNetworkListener() async {
    if (kIsWeb) return;
    try {
      final connectivity = Connectivity();
      _sub = connectivity.onConnectivityChanged.listen((results) {
        _setResults(results);
        if (_hasNetwork) _checkReachability();
      });
      final results = await connectivity.checkConnectivity();
      _setResults(results);
    } catch (e) {
      print('[Connectivity] listener error: $e');
    }
  }

  void _setResults(List<ConnectivityResult> results) {
    _results = results;
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    _setNetwork(hasNetwork);
    if (hasNetwork) _checkReachability();
  }

  Future<void> _checkReachability() async {
    if (_checking) return;
    if (!_hasNetwork) return;
    _checking = true;
    try {
      // Probe the JioSaavn API proxy root (CORS-friendly status payload)
      // instead of hitting a catalog endpoint that may 4xx on health checks.
      final healthUrl = JioSaavnService.apiBase;
      final res = await _dio.get(healthUrl);
      _setReachable(res.statusCode != null);
    } catch (_) {
      _setReachable(false);
    } finally {
      _checking = false;
    }
  }

  void _setNetwork(bool value) {
    if (_hasNetwork != value) {
      _hasNetwork = value;
      if (!value) _canReachApi = false;
      notifyListeners();
    }
  }

  void _setReachable(bool value) {
    if (_canReachApi != value) {
      _canReachApi = value;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await _checkReachability();
    await Future.delayed(const Duration(milliseconds: 200));
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}