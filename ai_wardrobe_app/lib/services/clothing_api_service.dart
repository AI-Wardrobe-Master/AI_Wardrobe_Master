import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_config.dart';
import 'local_clothing_service.dart';

class ClothingApiService {
  static final Dio _dio = buildApiDio();

  static Future<Map<String, dynamic>> createClothingItem({
    required File frontImage,
    File? backImage,
    String? name,
    String? description,
    List<String> manualTags = const <String>[],
    String? category,
    String? material,
    String? style,
    String? wardrobeId,
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
      if (manualTags.isNotEmpty) 'custom_tags_json': jsonEncode(manualTags),
      if (category case final value?) 'category': value,
      if (material case final value?) 'material': value,
      if (style case final value?) 'style': value,
      if (wardrobeId case final value?) 'wardrobe_id': value,
    });

    final resp = await _dio.post('/clothing-items', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createClothingItemFromBytes({
    required Uint8List frontImageBytes,
    Uint8List? backImageBytes,
    String? name,
    String? description,
    List<String> manualTags = const <String>[],
    String? category,
    String? material,
    String? style,
    String? wardrobeId,
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
      if (manualTags.isNotEmpty) 'custom_tags_json': jsonEncode(manualTags),
      if (category case final value?) 'category': value,
      if (material case final value?) 'material': value,
      if (style case final value?) 'style': value,
      if (wardrobeId case final value?) 'wardrobe_id': value,
    });

    final resp = await _dio.post('/clothing-items', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getProcessingStatus(String itemId) async {
    final resp = await _dio.get('/clothing-items/$itemId/processing-status');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getClothingItem(String itemId) async {
    if (LocalClothingService.isLocalItem(itemId)) {
      final local = await LocalClothingService.getItem(itemId);
      if (local == null) {
        throw Exception('Local clothing item not found');
      }
      return local;
    }

    try {
      final resp = await _dio.get('/clothing-items/$itemId');
      final data = resp.data as Map<String, dynamic>;
      final payload = Map<String, dynamic>.from(
        data['data'] as Map<String, dynamic>? ?? data,
      );
      await LocalClothingService.cacheRemoteItem(payload);
      final cached = await LocalClothingService.getItem(itemId);
      final mergedPayload = {
        ...payload,
        if (cached?['previewSvg'] != null) 'previewSvg': cached!['previewSvg'],
        if (cached?['previewSvgStoredLocally'] != null)
          'previewSvgStoredLocally': cached!['previewSvgStoredLocally'],
      };
      return data['data'] != null
          ? <String, dynamic>{...data, 'data': mergedPayload}
          : mergedPayload;
    } on DioException {
      final local = await LocalClothingService.getItem(itemId);
      if (local != null) {
        return local;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getAngleViews(String itemId) async {
    if (LocalClothingService.isLocalItem(itemId)) {
      return {'angleViews': const <dynamic>[]};
    }
    final resp = await _dio.get('/clothing-items/$itemId/angle-views');
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteClothingItem(String itemId) async {
    if (LocalClothingService.isLocalItem(itemId)) {
      await LocalClothingService.deleteItem(itemId);
      return;
    }

    await _dio.delete('/clothing-items/$itemId');
    await LocalClothingService.deleteItem(itemId);
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
    List<String>? customTags,
    bool? isConfirmed,
    String? category,
    String? material,
    String? style,
    List<String>? wardrobeIds,
  }) async {
    if (LocalClothingService.isLocalItem(itemId)) {
      await LocalClothingService.updateItem(
        itemId,
        name: name,
        description: description,
        manualTags: customTags,
        mergedTags: finalTags,
        category: category,
        material: material,
        style: style,
        wardrobeIds: wardrobeIds,
      );
      final local = await LocalClothingService.getItem(itemId);
      return {'success': true, 'data': local};
    }

    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (finalTags != null) 'finalTags': finalTags,
      if (customTags != null) 'customTags': customTags,
      if (isConfirmed != null) 'isConfirmed': isConfirmed,
      if (category != null) 'category': category,
      if (material != null) 'material': material,
      if (style != null) 'style': style,
      if (wardrobeIds != null) 'wardrobeIds': wardrobeIds,
    };
    final resp = await _dio.patch('/clothing-items/$itemId', data: body);
    final data = resp.data as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    await LocalClothingService.cacheRemoteItem(
      payload,
      wardrobeIds: wardrobeIds ?? const <String>[],
    );
    return data;
  }

  /// GET /attributes/options - 获取 style/season/audience 等预定义选项（2.3.1）
  static Future<Map<String, List<String>>> getAttributeOptions() async {
    final resp = await _dio.get('/attributes/options');
    final data = resp.data as Map<String, dynamic>;
    final inner = data['data'] as Map<String, dynamic>;
    return Map.fromEntries(
      inner.entries.map(
        (e) => MapEntry(
          e.key,
          (e.value as List).cast<String>(),
        ),
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> listClothingItems({
    String? wardrobeId,
    int page = 1,
    int limit = 100,
  }) async {
    if (limit > 100) {
      limit = 100;
    }

    final localOnly = await LocalClothingService.listItems(
      wardrobeId: wardrobeId,
      includeCachedRemote: false,
    );

    try {
      final queryParams = <String, dynamic>{'page': page, 'limit': limit};
      if (wardrobeId != null) {
        queryParams['wardrobeId'] = wardrobeId;
      }

      final resp = await _dio.get(
        '/clothing-items',
        queryParameters: queryParams,
      );
      final responseData = resp.data as Map<String, dynamic>;
      final data =
          responseData['data'] as Map<String, dynamic>? ?? responseData;
      final items = (data['items'] as List<dynamic>? ?? const <dynamic>[])
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();

      final itemsWithImages = <Map<String, dynamic>>[];
      for (final item in items) {
        await LocalClothingService.cacheRemoteItem(
          item,
          wardrobeIds: wardrobeId == null
              ? const <String>[]
              : <String>[wardrobeId],
        );
        itemsWithImages.add(item);
      }

      final merged = <String, Map<String, dynamic>>{};
      for (final item in itemsWithImages) {
        merged[item['id'].toString()] = item;
      }
      for (final item in localOnly) {
        merged[item['id'].toString()] = item;
      }
      return merged.values.toList();
    } on DioException {
      return LocalClothingService.listItems(wardrobeId: wardrobeId);
    }
  }
}
