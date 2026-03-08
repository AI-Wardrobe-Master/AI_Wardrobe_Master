import 'dart:io';
import 'package:dio/dio.dart';
import 'api_config.dart';

class ClothingApiService {
  static final _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

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

    final resp = await _dio.post('/clothing-items', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getProcessingStatus(String itemId) async {
    final resp = await _dio.get('/clothing-items/$itemId/processing-status');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getClothingItem(String itemId) async {
    final resp = await _dio.get('/clothing-items/$itemId');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getAngleViews(String itemId) async {
    final resp = await _dio.get('/clothing-items/$itemId/angle-views');
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> retryProcessing(String itemId) async {
    await _dio.post('/clothing-items/$itemId/retry');
  }

  /// PATCH /clothing-items/:id - 更新标签、名称等（2.3.3, 2.4）
  static Future<Map<String, dynamic>> updateClothingItem(
    String itemId, {
    String? name,
    String? description,
    List<Map<String, String>>? finalTags,
    bool? isConfirmed,
    List<String>? customTags,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (finalTags != null) data['finalTags'] = finalTags;
    if (isConfirmed != null) data['isConfirmed'] = isConfirmed;
    if (customTags != null) data['customTags'] = customTags;
    final resp = await _dio.patch('/clothing-items/$itemId', data: data);
    return resp.data as Map<String, dynamic>;
  }

  /// GET /attributes/options - 获取 style/season/audience 等预定义选项（2.3.1）
  static Future<Map<String, List<String>>> getAttributeOptions() async {
    final resp = await _dio.get('/attributes/options');
    final data = resp.data as Map<String, dynamic>;
    final inner = data['data'] as Map<String, dynamic>;
    return Map.fromEntries(
      inner.entries.map((e) => MapEntry(
            e.key as String,
            (e.value as List).cast<String>(),
          )),
    );
  }
}
