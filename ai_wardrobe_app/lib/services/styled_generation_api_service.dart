import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_config.dart';

class StyledGenerationApiService {
  static final Dio _dio = buildApiDio();

  static Future<Map<String, dynamic>> createGeneration({
    required File selfieImage,
    required String gender,
    required String scenePrompt,
    required List<Map<String, String>> clothingItems,
    String? negativePrompt,
    double guidanceScale = 4.5,
    int seed = -1,
    int width = 1024,
    int height = 1024,
  }) async {
    final formData = FormData.fromMap({
      'selfie_image': await MultipartFile.fromFile(
        selfieImage.path,
        filename: 'selfie.jpg',
      ),
      'gender': gender,
      'scene_prompt': scenePrompt,
      'clothing_items': jsonEncode(clothingItems),
      if (negativePrompt != null) 'negative_prompt': negativePrompt,
      'guidance_scale': guidanceScale,
      'seed': seed,
      'width': width,
      'height': height,
    });
    final resp = await _dio.post('/styled-generations', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> listGenerations({
    int page = 1,
    int limit = 20,
  }) async {
    final resp = await _dio.get(
      '/styled-generations',
      queryParameters: {'page': page, 'limit': limit},
    );
    final responseData = resp.data as Map<String, dynamic>;
    final data = responseData['data'] as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> getGeneration(String generationId) async {
    final resp = await _dio.get('/styled-generations/$generationId');
    final responseData = resp.data as Map<String, dynamic>;
    return responseData['data'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> retryGeneration(String generationId) async {
    final resp = await _dio.post('/styled-generations/$generationId/retry');
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteGeneration(String generationId) async {
    await _dio.delete('/styled-generations/$generationId');
  }
}
