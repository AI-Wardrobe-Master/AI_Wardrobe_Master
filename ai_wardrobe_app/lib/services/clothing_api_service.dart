import 'dart:io';
import 'package:dio/dio.dart';
import 'api_config.dart';
import 'auth_service.dart';

class ClothingApiService {
  static final _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  static Future<Dio> _client() async {
    await AuthService.ensureDemoSession();
    _dio.options.headers['Authorization'] = 'Bearer ${AuthService.token}';
    return _dio;
  }

  static Future<Map<String, dynamic>> createClothingItem({
    required File frontImage,
    File? backImage,
    String? name,
    String? description,
  }) async {
    final formData = FormData.fromMap({
      'front_image': await MultipartFile.fromFile(
        frontImage.path,
        filename: 'front.jpg',
      ),
      if (backImage != null)
        'back_image': await MultipartFile.fromFile(
          backImage.path,
          filename: 'back.jpg',
        ),
      if (name != null) 'name': name,
      if (description != null) 'description': description,
    });

    final dio = await _client();
    final resp = await dio.post('/clothing-items', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getProcessingStatus(String itemId) async {
    final dio = await _client();
    final resp = await dio.get('/clothing-items/$itemId/processing-status');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getClothingItem(String itemId) async {
    final dio = await _client();
    final resp = await dio.get('/clothing-items/$itemId');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getAngleViews(String itemId) async {
    final dio = await _client();
    final resp = await dio.get('/clothing-items/$itemId/angle-views');
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> retryProcessing(String itemId) async {
    final dio = await _client();
    await dio.post('/clothing-items/$itemId/retry');
  }
}
