import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

//const String apiBaseUrl = 'http://10.0.2.2:8000/api/v1';
//const String fileBaseUrl = 'http://10.0.2.2:8000';

// Use localhost for desktop and physical-device debugging with adb reverse.
const String apiBaseUrl = 'http://localhost:8000/api/v1';
const String fileBaseUrl = 'http://localhost:8000';

class ApiSession {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static String? _token;
  static Map<String, dynamic>? _user;

  static Future<void> loadToken() async {
    if (_token != null && _user != null) return;
    final prefs = await SharedPreferences.getInstance();
    _token ??= prefs.getString(_tokenKey);
    final rawUser = prefs.getString(_userKey);
    if (_user == null && rawUser != null && rawUser.isNotEmpty) {
      try {
        _user = Map<String, dynamic>.from(jsonDecode(rawUser) as Map);
      } catch (_) {
        _user = null;
      }
    }
  }

  static Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    _user = Map<String, dynamic>.from(user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_user));
  }

  static Future<void> clearToken() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  static bool get hasToken => _token != null && _token!.isNotEmpty;
  static Map<String, dynamic>? get cachedUser =>
      _user == null ? null : Map<String, dynamic>.from(_user!);

  static Map<String, String> get authHeaders {
    if (!hasToken) return const {};
    return {'Authorization': 'Bearer $_token'};
  }
}

Dio buildApiDio() {
  final dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        await ApiSession.loadToken();
        options.headers.addAll(ApiSession.authHeaders);
        handler.next(options);
      },
    ),
  );
  return dio;
}

String resolveFileUrl(String path) {
  if (path.startsWith('http') ||
      path.startsWith('data:') ||
      path.startsWith('file:')) {
    return path;
  }
  return '$fileBaseUrl$path';
}
