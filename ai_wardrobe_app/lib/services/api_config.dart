import 'package:flutter/foundation.dart';

const String _apiHostOverride = String.fromEnvironment('API_HOST');

String get _defaultApiHost {
  if (kIsWeb) return 'localhost';
  return defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
}

String get _apiHost =>
    _apiHostOverride.isNotEmpty ? _apiHostOverride : _defaultApiHost;

final String apiBaseUrl = 'http://$_apiHost:8000/api/v1';
final String fileBaseUrl = 'http://$_apiHost:8000';
