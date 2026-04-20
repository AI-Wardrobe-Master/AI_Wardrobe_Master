import 'package:dio/dio.dart';

import 'api_config.dart';

class AuthApiService {
  static final _dio = buildApiDio();

  static Future<void> login({
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post(
      '/auth/login',
      data: {'email': email.trim().toLowerCase(), 'password': password},
    );
    await _persistToken(resp);
  }

  static Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final resp = await _dio.post(
      '/auth/register',
      data: {
        'username': username.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
    await _persistToken(resp);
  }

  static Future<void> loginDemoUser() async {
    await login(email: 'demo@example.com', password: 'demo123456');
  }

  static Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {
      // Clearing the local session is the important step for logout.
    } finally {
      await ApiSession.clearToken();
    }
  }

  static Future<void> _persistToken(Response<dynamic> resp) async {
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>? ?? responseData;
    final token = data['token'] as String?;
    final user = data['user'] as Map<String, dynamic>?;
    if (token == null || token.isEmpty) {
      throw DioException(
        requestOptions: resp.requestOptions,
        message: 'Login response did not include a token.',
      );
    }
    await ApiSession.saveToken(token);
    if (user != null) {
      await ApiSession.saveUser(user);
    }
  }
}
