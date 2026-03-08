import 'package:dio/dio.dart';

import '../models/wardrobe.dart';
import 'api_config.dart';

/// Module 3: Wardrobe API. Fetch wardrobes, items, add/remove, create/rename/delete wardrobe.
class WardrobeService {
  static final _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  static Future<List<Wardrobe>> fetchWardrobes() async {
    final resp = await _dio.get('/wardrobes');
    final raw = resp.data;
    final list = (raw is Map && raw['items'] != null)
        ? raw['items'] as List
        : <dynamic>[];
    return list
        .map((e) => Wardrobe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<WardrobeItemWithClothing>> fetchWardrobeItems(
    String wardrobeId,
  ) async {
    final resp = await _dio.get('/wardrobes/$wardrobeId/items');
    final raw = resp.data;
    final list = (raw is Map && raw['items'] != null)
        ? raw['items'] as List
        : <dynamic>[];
    return list
        .map((e) =>
            WardrobeItemWithClothing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Wardrobe> createWardrobe({
    required String name,
    String type = 'REGULAR',
    String? description,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      if (description != null && description.isNotEmpty) 'description': description,
    };
    final resp = await _dio.post('/wardrobes', data: body);
    return Wardrobe.fromJson(resp.data as Map<String, dynamic>);
  }

  static Future<Wardrobe> updateWardrobe(
    String wardrobeId, {
    String? name,
    String? description,
  }) async {
    final body = <String, dynamic>{
      ...? (name != null ? {'name': name} : null),
      ...? (description != null ? {'description': description} : null),
    };
    final resp = await _dio.patch('/wardrobes/$wardrobeId', data: body);
    return Wardrobe.fromJson(resp.data as Map<String, dynamic>);
  }

  static Future<void> deleteWardrobe(String wardrobeId) async {
    await _dio.delete('/wardrobes/$wardrobeId');
  }

  static Future<void> addItemToWardrobe(
    String wardrobeId,
    String clothingItemId,
  ) async {
    await _dio.post(
      '/wardrobes/$wardrobeId/items',
      data: {'clothingItemId': clothingItemId},
    );
  }

  static Future<void> removeItemFromWardrobe(
    String wardrobeId,
    String clothingItemId,
  ) async {
    await _dio.delete(
      '/wardrobes/$wardrobeId/items/$clothingItemId',
    );
  }
}
