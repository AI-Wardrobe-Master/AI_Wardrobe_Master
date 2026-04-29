import 'api_config.dart';

class MeApiService {
  static final _dio = buildApiDio();

  static Future<Map<String, dynamic>> getMe() async {
    try {
      final resp = await _dio.get('/me');
      final raw = resp.data as Map<String, dynamic>;
      final me = Map<String, dynamic>.from(
        raw['data'] as Map<String, dynamic>? ?? raw,
      );
      await ApiSession.saveUser(me);
      return me;
    } catch (_) {
      final cached = ApiSession.cachedUser;
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }
}
