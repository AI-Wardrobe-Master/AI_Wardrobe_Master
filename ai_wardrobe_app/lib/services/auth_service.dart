import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_config.dart';

class AuthService {
  AuthService._();

  static const _demoEmail = 'demo@example.com';
  static const _demoPassword = 'demo123456';

  static final Dio _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  static String? _token;
  static Future<void>? _pendingLogin;
  static bool _guestMode = false;

  static String? get token => _token;
  static bool get isGuestMode => _guestMode;

  static Future<void> ensureDemoSession() {
    if (localDemoOnly) {
      enterGuestMode();
      return Future.value();
    }

    if (_token != null && _token!.isNotEmpty) {
      return Future.value();
    }

    if (_pendingLogin != null) {
      return _pendingLogin!;
    }

    _pendingLogin = _loginDemo();
    return _pendingLogin!.whenComplete(() {
      _pendingLogin = null;
    });
  }

  static Future<void> _loginDemo() async {
    _guestMode = false;
    final response = await _dio.post(
      '/auth/login',
      data: const {'email': _demoEmail, 'password': _demoPassword},
    );

    final body = response.data;
    final tokenValue = switch (body) {
      {'data': {'token': final String token}} => token,
      _ => null,
    };

    if (tokenValue == null || tokenValue.isEmpty) {
      throw Exception('Demo login did not return an access token.');
    }

    _token = tokenValue;
  }

  static void enterGuestMode() {
    _guestMode = true;
    _token = null;
  }

  @visibleForTesting
  static void resetForTest() {
    _token = null;
    _pendingLogin = null;
    _guestMode = false;
  }
}
