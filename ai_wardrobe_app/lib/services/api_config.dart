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
    final prefs = await SharedPreferences.getInstance();
    final previousUserId = _userId(_user);
    if (_user == null) {
      final rawUser = prefs.getString(_userKey);
      if (rawUser != null && rawUser.isNotEmpty) {
        try {
          _user = Map<String, dynamic>.from(jsonDecode(rawUser) as Map);
        } catch (_) {
          _user = null;
        }
      }
    }
    final loadedPreviousUserId = _userId(_user) ?? previousUserId;
    final nextUserId = _userId(user);
    if (loadedPreviousUserId != null &&
        nextUserId != null &&
        loadedPreviousUserId != nextUserId) {
      await _clearUserScopedLocalCache(prefs);
    }
    _user = Map<String, dynamic>.from(user);
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

  static String? get currentUserId => _userId(_user);

  static Map<String, String> get authHeaders {
    if (!hasToken) return const {};
    return {'Authorization': 'Bearer $_token'};
  }

  static String? _userId(Map<String, dynamic>? user) {
    final raw = user?['id'] ?? user?['userId'];
    final value = raw?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> _clearUserScopedLocalCache(
    SharedPreferences prefs,
  ) async {
    const exactKeys = <String>{
      'local_clothing_v2_ids',
      'local_clothing_items_list',
      'local_clothing_3d_demo_item',
      'local_wardrobe_v2_ids',
      'local_card_packs_list',
      'local_import_history_ids',
    };
    const prefixes = <String>[
      'local_clothing_v2_',
      'local_clothing_item_',
      'local_wardrobe_v2_',
      'local_card_pack_',
      'local_import_history_',
    ];

    for (final key in prefs.getKeys().toList()) {
      if (exactKeys.contains(key) ||
          prefixes.any((prefix) => key.startsWith(prefix))) {
        await prefs.remove(key);
      }
    }
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
