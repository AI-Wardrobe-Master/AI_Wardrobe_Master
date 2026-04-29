import 'dart:io';

import 'package:dio/dio.dart';

import 'api_config.dart';

class OutfitPreviewApiService {
  static final Dio _dio = buildApiDio();

  static Future<Map<String, dynamic>> createTask({
    required File personImage,
    required List<String> clothingItemIds,
    required String personViewType,
    required List<String> garmentCategories,
  }) async {
    final formData = FormData.fromMap({
      'person_image': await MultipartFile.fromFile(
        personImage.path,
        filename: 'person.jpg',
      ),
      'clothing_item_ids[]': clothingItemIds,
      'person_view_type': personViewType,
      'garment_categories[]': garmentCategories,
    });
    final resp = await _dio.post('/outfit-preview-tasks', data: formData);
    final responseData = resp.data as Map<String, dynamic>;
    return responseData['data'] as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> listTasks({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    final resp = await _dio.get(
      '/outfit-preview-tasks',
      queryParameters: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> getTask(String taskId) async {
    final resp = await _dio.get('/outfit-preview-tasks/$taskId');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> saveTask(String taskId) async {
    final resp = await _dio.post('/outfit-preview-tasks/$taskId/save');
    final responseData = resp.data as Map<String, dynamic>;
    return responseData['data'] as Map<String, dynamic>;
  }
}
