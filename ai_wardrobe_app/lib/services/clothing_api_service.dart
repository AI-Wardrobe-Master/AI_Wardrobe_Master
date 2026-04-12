import 'dart:io';
import 'dart:typed_data';

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
      if (name case final value?) 'name': value,
      if (description case final value?) 'description': value,
    });

    final resp = await _dio.post('/clothing-items', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createClothingItemFromBytes({
    required Uint8List frontImageBytes,
    Uint8List? backImageBytes,
    String? name,
    String? description,
  }) async {
    final formData = FormData.fromMap({
      'front_image': MultipartFile.fromBytes(
        frontImageBytes,
        filename: 'front.jpg',
      ),
      if (backImageBytes != null)
        'back_image': MultipartFile.fromBytes(
          backImageBytes,
          filename: 'back.jpg',
        ),
      if (name case final value?) 'name': value,
      if (description case final value?) 'description': value,
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

  static Future<List<Map<String, dynamic>>> listClothingItems({
    String? wardrobeId,
    int page = 1,
    int limit = 100,
  }) async {
    if (limit > 100) limit = 100;

    final queryParams = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (wardrobeId != null) {
      queryParams['wardrobeId'] = wardrobeId;
    }

    final resp = await _dio.get(
      '/clothing-items',
      queryParameters: queryParams,
    );
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>? ?? responseData;
    final items = (data['items'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final itemsWithImages = <Map<String, dynamic>>[];
    for (final item in items) {
      if (!item.containsKey('images') || item['images'] == null) {
        try {
          final itemId = item['id'] as String;
          final fullItem = await getClothingItem(itemId);
          final fullData =
              fullItem['data'] as Map<String, dynamic>? ?? fullItem;
          item['images'] = fullData['images'];
        } catch (_) {
          // Keep list response as-is if the detail request fails.
        }
      }
      itemsWithImages.add(item);
    }

    return itemsWithImages;
  }
}
